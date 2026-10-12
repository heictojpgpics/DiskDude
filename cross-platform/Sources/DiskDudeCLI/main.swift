//
//  main.swift
//  DiskDudeCLI
//
//  Windows/Linux/macOS CLI front-end for the recovered DiskDudeCore:
//  scans a directory and prints a report using the byte-exact original
//  formatters. This is the "Windows build" of the recovered codebase —
//  the SwiftUI GUI itself is macOS-only by Apple design.
//

import Foundation
import DiskDudeCore

let args = CommandLine.arguments
let usage = """
usage: diskdude-cli <path> [--top N] [--no-duplicates] [--out FILE]

Scans a directory tree and prints a DiskDude-style report
(sizes, categories, top files, duplicate groups) using the
byte-exact formatters recovered from DiskDude 1.0.1.
"""

guard args.count >= 2 else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(64)
}

var root = args[1]
var topN = 10
var findDuplicates = true
var outFile: String? = nil
var i = 2
while i < args.count {
    switch args[i] {
    case "--top": topN = Int(args[i + 1]) ?? 10; i += 2
    case "--no-duplicates": findDuplicates = false; i += 1
    case "--out": outFile = args[i + 1]; i += 2
    default: i += 1
    }
}

guard FileManager.default.fileExists(atPath: root) else {
    FileHandle.standardError.write(Data("path does not exist: \(root)\n".utf8))
    exit(66)
}

do {
    let report = try Scanner.scan(root: root, findDuplicates: findDuplicates)
    let text = report.render(topN: topN)
    if let outFile {
        try text.write(toFile: outFile, atomically: true, encoding: .utf8)
        print("report written: \(outFile)")
    } else {
        print(text)
    }
    exit(0)
} catch {
    FileHandle.standardError.write(Data("scan failed: \(error)\n".utf8))
    exit(70)
}
