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
    /// Binary-exact pool: DispatchGroup + NSThread(qualityOfService: .userInitiated),
    /// workerCount = ProcessInfo.activeProcessorCount (min 1, cached once),
    /// each worker owns a 256 KB getattrlistbulk buffer.
    func scan(rootURL: URL, progress: ((Int, Int64, String) -> Void)? = nil) -> FileNode {
        let root = FileNode(name: rootURL.lastPathComponent, isDirectory: true, rootPath: rootURL.path)
        let workerCount = max(1, ProcessInfo.processInfo.activeProcessorCount)

        let group = DispatchGroup()
        for _ in 0..<workerCount {
            group.enter()
            let thread = Thread { [weak self] in
                guard let self else { group.leave(); return }
                while let job = self.stack.pop() {
                    if self.isCancelled { continue }
                    self.scanDirectory(job: job)
                }
                group.leave()
            }
            thread.qualityOfService = .userInitiated
            thread.start()
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
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        // Request bitmap — ATTR_CMN_ERROR is an OUTPUT-only flag (returned in
        // the attrlist error field); requesting it makes getattrlistbulk
        // return EINVAL, which aborted every scan at the root with exactly
        // "1 folders couldn't be read" on the CI runner. ATTR_CMN_OBJTYPE is
        // REQUIRED for directory detection (VDIR) — without it no child is
        // ever classified as a folder and subdirectories are never pushed
        // as jobs (empty treemap). Canonical returned order follows
        // descending bit values: NAME, OBJTYPE, CRTIME, MODTIME, then file
        // sizes.
        attrList.commonattr = attrgroup_t(ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_CRTIME)
        attrList.fileattr = attrgroup_t(ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE | ATTR_FILE_DEVTYPE)

        // each worker owns a 256 KB getattrlistbulk buffer (binary-verified:
        // 0x40000 per worker). Owned allocation — a Data(capacity:) has
        // count 0 and exposes a zero-length mutable buffer, so it must NOT
        // be used as the destination of a bulk syscall.
        let capacity = 256 * 1024
        let attrBuf = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        defer { attrBuf.deallocate() }

        while true {
            if isCancelled { return }
            let n = getattrlistbulk(fd, &attrList, attrBuf, capacity, 0)
            if n == 0 { break }
            if n < 0 {
                let err = errno
                if err == EINTR { continue }  // transient — retry, not unreadable
                noteUnreadable(job.path)
                return
            }
            let consumed = Int(n)
            var offset = 0
            while offset < consumed {
                let entry = attrBuf + offset
                // The layout below mirrors the decompiled entry walk:
                // size, name offset, flags, file type, sizes, dates.
                let sizeField = entry.load(fromByteOffset: 0, as: UInt32.self)
                let infoField = entry.load(fromByteOffset: 4, as: UInt32.self)
                guard sizeField >= 8, infoField != 0 else { break }
                process(entry: entry, parent: job.node, path: job.path, insideApp: job.insideApp)
                offset += Int(sizeField)
                if offset <= 0 { break }
            }
        }
    }

    /// Parse one attribute entry into a child FileNode. Layout per getattrlist(2):
    /// [u32 entrySize][attrgroup returnedBitmap][attrreference_t NAME (8B:
    /// u32 length, u32 dataoffset)][OBJTYPE u32][align8 CRTIME timespec]
    /// [MODTIME timespec][align8 TOTALSIZE off_t][ALLOCSIZE off_t][DEVTYPE u32]
    /// ... name string at attr_dataoffset. Attributes appear in descending
    /// bit-value canonical order (NAME 0x00100000 > OBJTYPE 0x00020000 >
    /// CRTIME 0x00002000 > MODTIME 0x00001000 > file sizes).
    private func process(entry: UnsafeRawPointer, parent: FileNode, path: String, insideApp: Bool) {
        let attrs = entry.load(fromByteOffset: 4, as: UInt32.self)

        var name: String = ""
        var isDirectory = false
        var logicalSize: Int64 = 0
        var sizeOnDisk: Int64 = 0
        var modified: Double = 0
        var created: Double = 0

        if attrs & attrgroup_t(ATTR_CMN_NAME) != 0 {
            let off = entry.load(fromByteOffset: 12, as: UInt32.self)
            let namePtr = entry + Int(off)
            name = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
        }
        var cursor = 16
        if attrs & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            let objType = entry.load(fromByteOffset: cursor, as: vtype.self)
            isDirectory = (objType == VDIR)
            cursor += 4
        }
        // timespec (tv_sec i64 + tv_nsec i64) — 8-byte natural alignment
        cursor = (cursor + 7) & ~7
        if attrs & attrgroup_t(ATTR_CMN_CRTIME) != 0 {
            let t = entry.load(fromByteOffset: cursor, as: timespec.self)
            created = Double(t.tv_sec)
            cursor += MemoryLayout<timespec>.size
        }
        if attrs & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            let t = entry.load(fromByteOffset: cursor, as: timespec.self)
            modified = Double(t.tv_sec)
            cursor += MemoryLayout<timespec>.size
        }
        if attrs & attrgroup_t(ATTR_FILE_TOTALSIZE) != 0 {
            logicalSize = entry.load(fromByteOffset: cursor, as: Int64.self)
            cursor += 8
        }
        if attrs & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            let alloc = entry.load(fromByteOffset: cursor, as: Int64.self)
            cursor += 8
            // Round up to the allocation block (decompiled: block < 2 → 1).
            let block: Int64 = alloc > 0 ? max(1, alloc) : 1
            sizeOnDisk = ((logicalSize + block - 1) / block) * block
            if sizeOnDisk < logicalSize { sizeOnDisk = logicalSize }
        }
        // ATTR_FILE_DEVTYPE (u32) follows when requested — not consumed

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
            // System bookkeeping volumes the scanner refuses to descend into
            // (string literals recovered from the binary).
            if childPath == "/.Spotlight-V100" || childPath == "/.fseventsd" {
                return
            }
            stack.push(Job(node: child, path: childPath, insideApp: insideAppBundle))
        }
    }

    private func noteUnreadable(_ path: String) {
        if ProcessInfo.processInfo.environment["DISKDUDE_DEBUG"] != nil {
            FileHandle.standardError.write(Data("DiskDude scanner: unreadable \(path) errno=\(errno)\n".utf8))
        }
        lock.lock()
        unreadableCount += 1
        if unreadableSamples.count < 12 {
            unreadableSamples.append(path)
        }
        lock.unlock()
    }
}

extension FileCategory {
    /// Extension tables stored in the binary as single space-separated
    /// literals; split at runtime (byte-exact recovery).
    static let videoExtensions = "mp4 mov m4v mkv avi wmv flv webm mpg mpeg 3gp mts m2ts vob"
    static let audioExtensions = "mp3 wav aac m4a flac ogg aiff aif alac wma opus mid midi caf m4b"
    static let imageExtensions = "jpg jpeg png gif heic heif tiff tif bmp webp svg raw cr2 cr3 nef arw dng psd ai sketch fig ico icns exr"
    static let documentExtensions = "pdf doc docx xls xlsx ppt pptx key pages numbers txt rtf md csv epub odt ods odp html htm tex"
    static let developerExtensions = "swift m mm h c cc cpp hpp js mjs cjs ts tsx jsx json py pyc rb go rs java kt class jar o a dylib so node wasm map lock yml yaml toml xml sh zsh css scss less gradle pbxproj storyboard xib sql php vue svelte dart lua r ipynb tsbuildinfo d"
    static let archiveExtensions = "zip gz tgz tar bz2 xz 7z rar dmg iso pkg xip zst lz4 cab"
    static let otherExtensions = "plist log db sqlite sqlite3 sqlite-wal sqlite-shm db-wal db-shm wal shm cache dat ldb idx pack vmdk img sparseimage sparsebundle asar"

    private static func matches(_ extensions: String, _ ext: String) -> Bool {
        extensions.split(separator: " ").contains { $0 == ext }
    }

    /// Categorize by file extension.
    static func from(pathExtension ext: String, isApp: Bool) -> FileCategory {
        if isApp { return .application }
        let e = ext.lowercased()
        if matches(videoExtensions, e) { return .video }
        if matches(audioExtensions, e) { return .audio }
        if matches(imageExtensions, e) { return .image }
        if matches(documentExtensions, e) { return .document }
        if matches(developerExtensions, e) { return .developer }
        if matches(archiveExtensions, e) { return .archive }
        if matches(otherExtensions, e) { return .other }
        return .other
    }
}
