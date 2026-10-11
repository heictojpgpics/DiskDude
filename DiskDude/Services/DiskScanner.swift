//
//  DiskScanner.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + decompiled logic:
//  uses Darwin open(2) + getattrlistbulk(2) to walk the tree as fast as
//  the kernel can hand back entries, with a small worker pool
//  (JobStack / Job with NSCondition) for parallel folder recursion.
//

import Foundation
import Darwin

/// Fast recursive disk scanner. One FileNode tree is built for the scan
/// root; progress and unreadable folders are reported through the
/// observable properties (guarded by the lock).
final class DiskScanner: ObservableObject {

    /// Producer/consumer stack of folders still to scan.
    final class JobStack {
        let condition = NSCondition()
        var jobs: [Job] = []
        var active: Int = 0

        func push(_ job: Job) {
            condition.lock()
            jobs.append(job)
            condition.signal()
            condition.unlock()
        }

        func pop() -> Job? {
            condition.lock()
            defer { condition.unlock() }
            while true {
                if let job = jobs.popLast() {
                    return job
                }
                if active == 0 {
                    return nil
                }
                condition.wait()
            }
        }

        func jobDidStart() {
            condition.lock()
            active += 1
            condition.unlock()
        }

        func jobDidFinish() {
            condition.lock()
            active -= 1
            condition.signal()
            condition.unlock()
        }
    }

    struct Job {
        let node: FileNode
        let path: String
        let insideApp: Bool
    }

    let lock = NSLock()
    @Published var filesScanned: Int = 0
    @Published var bytesScanned: Int64 = 0
    @Published var currentPath: String = ""
    var unreadableCount: Int = 0
    var unreadableSamples: [String] = []
    var cancelled: Bool = false

    private let stack = JobStack()

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    // MARK: - Scan

    /// Scan `rootURL` and return the FileNode tree.
    func scan(rootURL: URL, progress: ((Int, Int64, String) -> Void)? = nil) -> FileNode {
        let root = FileNode(name: rootURL.lastPathComponent, isDirectory: true, rootPath: rootURL.path)
        let workerCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

        let group = DispatchGroup()
        for _ in 0..<workerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { group.leave(); return }
                while let job = self.stack.pop() {
                    if self.isCancelled { continue }
                    self.scanDirectory(job: job)
                }
                group.leave()
            }
        }

        stack.push(Job(node: root, path: rootURL.path, insideApp: false))
        group.wait()
        return root
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Scan one directory using getattrlistbulk (recovered from imports:
    /// open + getattrlistbulk + errno handling + close).
    private func scanDirectory(job: Job) {
        stack.jobDidStart()
        defer { stack.jobDidFinish() }

        let fd = open(job.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else {
            noteUnreadable(job.path)
            return
        }
        defer { close(fd) }

        var attrList = attrlist()
        attrList.bitmapcount = u_int16_t(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = attrgroup_t(ATTR_CMN_NAME | ATTR_CMN_ERROR | ATTR_CMN_MODTIME | ATTR_CMN_CRTIME)
        attrList.fileattr = attrgroup_t(ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE | ATTR_FILE_DEVTYPE)

        let capacity = 256 * 1024
        var buffer = Data(capacity: capacity)
        let attrBuf = UnsafeMutableRawPointer(buffer.withUnsafeMutableBytes { $0.baseAddress! })
        var consumed = 0

        while true {
            if isCancelled { return }
            let n = getattrlistbulk(fd, &attrList, attrBuf, capacity, 0)
            if n == 0 { break }
            if n < 0 {
                noteUnreadable(job.path)
                return
            }
            consumed = Int(n)
            var offset = 0
            while offset < consumed {
                let entry = attrBuf + offset
                let record = entry.assumingMemoryBound(to: attrlist_extent_t?.self)
                // The layout below mirrors the decompiled entry walk:
                // size, name offset, flags, file type, sizes, dates.
                let sizeField = entry.load(fromByteOffset: 0, as: UInt32.self)
                let infoField = entry.load(fromByteOffset: 4, as: UInt32.self)
                guard sizeField >= 8, infoField & ATTR_CMN_NAME != 0 || infoField != 0 else { break }
                process(entry: entry, parent: job.node, path: job.path, insideApp: job.insideApp)
                offset += Int(sizeField)
                if offset <= 0 { break }
            }
        }
    }

    /// Parse one attribute entry into a child FileNode (structure recovered
    /// from the decompiled buffer walk: name, type, logical size, allocation
    /// size with block rounding, dates).
    private func process(entry: UnsafeRawPointer, parent: FileNode, path: String, insideApp: Bool) {
        let attrs = entry.load(fromByteOffset: 4, as: UInt32.self)
        var cursor = 16

        var name: String = ""
        var isDirectory = false
        var logicalSize: Int64 = 0
        var sizeOnDisk: Int64 = 0
        var modified: Double = 0
        var created: Double = 0

        if attrs & ATTR_CMN_NAME != 0 {
            let off = entry.load(fromByteOffset: 12, as: UInt32.self)
            let namePtr = entry + Int(off)
            name = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
        }
        if attrs & ATTR_CMN_OBJTYPE != 0 || attrs & ATTR_CMN_ERROR != 0 {
            let objType = entry.load(fromByteOffset: cursor, as: UInt32.self)
            isDirectory = (objType == VDIR)
            cursor += 4
        }
        if attrs & ATTR_CMN_MODTIME != 0 {
            let t = entry.load(fromByteOffset: cursor, as: timespec.self)
            modified = Double(t.tv_sec)
            cursor += MemoryLayout<timespec>.alignment
        }
        if attrs & ATTR_CMN_CRTIME != 0 {
            let t = entry.load(fromByteOffset: cursor, as: timespec.self)
            created = Double(t.tv_sec)
            cursor += MemoryLayout<timespec>.alignment
        }
        if attrs & ATTR_FILE_TOTALSIZE != 0 {
            logicalSize = entry.load(fromByteOffset: cursor, as: Int64.self)
            cursor += 8
        }
        if attrs & ATTR_FILE_ALLOCSIZE != 0 {
            let alloc = entry.load(fromByteOffset: cursor, as: Int64.self)
            // Round up to the allocation block (decompiled: block < 2 → 1).
            let block: Int64 = alloc > 0 ? max(1, alloc) : 1
            sizeOnDisk = ((logicalSize + block - 1) / block) * block
            if sizeOnDisk < logicalSize { sizeOnDisk = logicalSize }
            cursor += 8
        }

        guard !name.isEmpty, name != ".", name != ".." else { return }

        let childPath = path + "/" + name
        let insideAppBundle = insideApp || name.hasSuffix(".app")
        let child = FileNode(name: name, isDirectory: isDirectory, rootPath: nil)
        child.category = isDirectory ? .other : FileCategory.from(pathExtension: (name as NSString).pathExtension, isApp: name.hasSuffix(".app"))
        child.logicalSize = logicalSize
        child.sizeOnDisk = sizeOnDisk
        child.modifiedStamp = modified
        child.createdStamp = created
        if isDirectory {
            child.folderCount = 1
        } else {
            child.fileCount = 1
        }
        parent.add(child: child)

        lock.lock()
        filesScanned += 1
        bytesScanned += sizeOnDisk
        currentPath = childPath
        if unreadableSamples.count < 8 { /* keep bounded */ }
        lock.unlock()

        if isDirectory {
            stack.push(Job(node: child, path: childPath, insideApp: insideAppBundle))
        }
    }

    private func noteUnreadable(_ path: String) {
        lock.lock()
        unreadableCount += 1
        if unreadableSamples.count < 12 {
            unreadableSamples.append(path)
        }
        lock.unlock()
    }
}

extension FileCategory {
    /// Categorize by file extension (recovered switch on extension sets).
    static func from(pathExtension ext: String, isApp: Bool) -> FileCategory {
        if isApp { return .application }
        switch ext.lowercased() {
        case "mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg":
            return .video
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "wma":
            return .audio
        case "jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp", "svg", "raw", "cr2":
            return .image
        case "pdf", "doc", "docx", "txt", "rtf", "md", "pages", "key", "ppt", "pptx", "xls", "xlsx", "csv", "epub":
            return .document
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "pkg", "ipa":
            return .archive
        case "swift", "m", "h", "c", "cpp", "mm", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "sh", "pl", "php", "json", "yaml", "yml", "toml", "xcodeproj", "xcworkspace", "plist":
            return .developer
        default:
            return .other
        }
    }
}
