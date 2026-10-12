//
//  FormatterTests.swift
//  DiskDudeCoreTests
//
//  Byte-exact expectations derived from the recovered binary behavior
//  (fuzz-verified in Round 5 against the decompiled model).
//

import XCTest
@testable import DiskDudeCore

final class FormatterTests: XCTestCase {
    func testSmallValues() {
        XCTAssertEqual(formatBytes(0), "0 B")
        XCTAssertEqual(formatBytes(1), "1 B")
        XCTAssertEqual(formatBytes(999), "999 B")
        XCTAssertEqual(formatBytes(-42), "-42 B")
    }

    func testUnitBoundaries() {
        // Round-5 fuzz-verified: 1000 divides FIRST, so 1000 -> KB
        XCTAssertEqual(formatBytes(1000), "1.00 KB")
        XCTAssertEqual(formatBytes(999_999), "1.00 MB")     // 999.999 KB >= 999.5 rolls to MB
        XCTAssertEqual(formatBytes(1_000_000), "1.00 MB")
        XCTAssertEqual(formatBytes(1_000_000_000), "1.00 GB")
        XCTAssertEqual(formatBytes(1_000_000_000_000), "1.00 TB")
    }

    func testThresholds() {
        // value >= 99.95 -> %.0f (rounds!), >= 9.995 -> %.1f, else %.2f
        XCTAssertEqual(formatBytes(99_950), "100 KB")        // %.0f rounds 99.95 -> 100
        XCTAssertEqual(formatBytes(9_995), "10.0 KB")       // %.1f at the 9.995 edge
        XCTAssertEqual(formatBytes(12_345), "12.3 KB")      // 12.345 >= 9.995 -> %.1f
        XCTAssertEqual(formatBytes(9_123), "9.12 KB")       // 9.123 < 9.995 -> %.2f
        XCTAssertEqual(formatBytes(123_456), "123 KB")      // 123.456 >= 99.95 -> %.0f
    }

    func testRollover() {
        // 999.5 rollover: 999500000 B -> 999500 KB -> 999.5 MB -> 0.9995 GB
        XCTAssertEqual(formatBytes(999_500_000), "1.00 GB")
        XCTAssertEqual(formatBytes(999_999_999), "1.00 GB")
        XCTAssertEqual(formatBytes(2_500_000_000), "2.50 GB")
    }

    func testPercentage() {
        XCTAssertEqual(formatPercentage(0, of: 0), "0%")
        XCTAssertEqual(formatPercentage(500, of: 1_000_000), "<0.1%")
        XCTAssertEqual(formatPercentage(1_000, of: 0), "0%")
        XCTAssertEqual(formatPercentage(1, of: 1_000), "0.1%")  // exactly 0.1 -> not below
        XCTAssertEqual(formatPercentage(250, of: 1_000), "25.0%")
        XCTAssertEqual(formatPercentage(1, of: 3), "33.3%")
    }

    func testRelativeDate() {
        XCTAssertEqual(relativeDateText(nil), "Unknown")
        XCTAssertEqual(relativeDateText(Date()), "Just now")
        XCTAssertEqual(relativeDateText(Date().addingTimeInterval(-30)), "Just now")
    }
}

final class CategoryTests: XCTestCase {
    func testCascadeOrder() {
        XCTAssertEqual(FileCategory.category(forExtension: "mp4"), .video)
        XCTAssertEqual(FileCategory.category(forExtension: "MP4"), .video)  // lowercased
        XCTAssertEqual(FileCategory.category(forExtension: "mp3"), .audio)
        XCTAssertEqual(FileCategory.category(forExtension: "heic"), .image)
        XCTAssertEqual(FileCategory.category(forExtension: "pdf"), .document)
        XCTAssertEqual(FileCategory.category(forExtension: "swift"), .developer)
        XCTAssertEqual(FileCategory.category(forExtension: "dmg"), .archive)  // NOT other: archive comes first
        XCTAssertEqual(FileCategory.category(forExtension: "sqlite"), .other)
        XCTAssertEqual(FileCategory.category(forExtension: "zip"), .archive)
        XCTAssertEqual(FileCategory.category(forExtension: "exe"), .other)
        XCTAssertEqual(FileCategory.category(forExtension: ""), .other)
    }

    func testThresholdConstant() {
        XCTAssertEqual(FileCategory.duplicateMinimumBytes, 65_536)
    }
}

final class SHA256Tests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(SHA256.digest(Array("".utf8)).map { String(format: "%02x", $0) }.joined(),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.digest(Array("abc".utf8)).map { String(format: "%02x", $0) }.joined(),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.digest(Array("The quick brown fox jumps over the lazy dog".utf8))
            .map { String(format: "%02x", $0) }.joined(),
                       "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
    }

    func testLongInputMultiBlock() {
        // 1,000,000 x 'a' — classic multi-block vector
        let input = Array(String(repeating: "a", count: 1_000_000).utf8)
        XCTAssertEqual(SHA256.digest(input).map { String(format: "%02x", $0) }.joined(),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func testChunkedEqualsWhole() {
        // 1 MB chunking path must give the same digest as one-shot
        let data = Array((0..<2_500_000).map { UInt8($0 % 251) })
        var chunked = SHA256.Hasher()
        var offset = 0
        while offset < data.count {
            let end = min(offset + 0x100000, data.count)
            chunked.update(Array(data[offset..<end]))
            offset = end
        }
        let chunkedHex = chunked.hexDigest()
        let wholeHex = SHA256.digest(data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(chunkedHex, wholeHex)
    }

    func testFileDigest() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("f.bin")
        try Data(Array("abc".utf8)).write(to: f)
        XCTAssertEqual(try SHA256.fileDigest(at: f.path),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class ScannerTests: XCTestCase {
    func testScanFixture() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // video file
        try Data(repeating: 7, count: 100_000).write(to: dir.appendingPathComponent("v.mp4"))
        // duplicate pair (>= 64 KB)
        let payload = Data((0..<70_000).map { UInt8($0 % 253) })
        try payload.write(to: dir.appendingPathComponent("dup-a.bin"))
        try payload.write(to: dir.appendingPathComponent("dup-b.bin"))
        // subfolder + tiny file
        let sub = dir.appendingPathComponent("Sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: sub.appendingPathComponent("note.txt"))

        let report = try Scanner.scan(root: dir.path)
        XCTAssertEqual(report.fileCount, 4)
        XCTAssertEqual(report.folderCount, 1)
        XCTAssertEqual(report.totalBytes, 100_000 + 70_000 * 2 + 2)
        XCTAssertEqual(report.duplicates.count, 1)
        XCTAssertEqual(report.duplicates[0].paths.count, 2)
        XCTAssertEqual(report.duplicates[0].wasted, 70_000)
        XCTAssertTrue(report.categories.first?.category == .other)  // .bin files
    }
}
