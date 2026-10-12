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
