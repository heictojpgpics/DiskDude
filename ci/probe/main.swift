//
//  probe_main.swift
//  Standalone harness that runs the REAL DiskScanner over a directory and
//  prints exactly what it produced — isolates the scanner from all SwiftUI.
//  Compiled directly on CI runners with:
//    swiftc -O DiskDude/Services/DiskScanner.swift DiskDude/Models/FileNode.swift \
//           ci/probe_main.swift -o scanner-probe
//

import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: scanner-probe <directory>")
    exit(64)
}
let root = URL(fileURLWithPath: args[1])
print("probing scan of: \(root.path)")

let scanner = DiskScanner()
let start = Date()
let tree = scanner.scan(rootURL: root) { files, bytes, current in
    // progress callback — print the first few to prove the walk advances
    if files % 50 == 0 || files < 5 {
        print("progress: \(files) files, \(bytes) bytes, at \(current)")
    }
}
let elapsed = Date().timeIntervalSince(start)

// raw first-entry dump: helps debug empty trees (layout verification)
let dirfd = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
if dirfd >= 0 {
    var attrList = attrlist()
    attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    attrList.commonattr = attrgroup_t(bitPattern:
        Int32(bitPattern: ATTR_CMN_RETURNED_ATTRS) | ATTR_CMN_ERROR |
        ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_CRTIME)
    attrList.fileattr = attrgroup_t(bitPattern:
        ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE | ATTR_FILE_DEVTYPE)
    var buf = [UInt8](repeating: 0, count: 4096)
    let n = buf.withUnsafeMutableBytes { raw in
        getattrlistbulk(dirfd, &attrList, raw.baseAddress!, 4096, 0)
    }
    print("RAW getattrlistbulk returned: \(n)")
    if n > 0 {
        let hex = buf.prefix(96).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("RAW first 96 bytes: \(hex)")
    }
    close(dirfd)
} else {
    print("RAW open failed: errno=\(errno)")
}

func countFiles(_ node: FileNode) -> (Int, Int, Int64) {
    var f = 0, d = 0, b: Int64 = 0
    for child in node.children {
        let r = countFiles(child)
        f += r.0; d += r.1; b += r.2
        if child.isDirectory { d += 1 } else { f += 1; b += child.logicalSize }
    }
    return (f, d, b)
}
let (files, folders, bytes) = countFiles(tree)

print("scan finished in \(String(format: "%.3f", elapsed))s")
print("root children: \(tree.children.count)")
print("total files: \(files)")
print("total folders: \(folders)")
print("total logical bytes: \(bytes)")
print("unreadable folders: \(scanner.unreadableCount)")
for sample in scanner.unreadableSamples {
    print("  unreadable: \(sample)")
}
print("first-level entries:")
for child in tree.children.prefix(15) {
    print("  \(child.isDirectory ? "D" : "F") \(child.name) \(child.logicalSize)")
}
if files == 0 && tree.children.isEmpty {
    print("PROBE RESULT: EMPTY TREE")
    exit(2)
}
print("PROBE RESULT: OK")
