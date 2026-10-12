//
//  SHA256.swift
//  DiskDudeCore
//
//  Pure-Swift SHA-256 mirroring the binary's duplicate-finder mechanics
//  (recovered from the 0x1000519xx region):
//    * chunked hashing with a 1 MB buffer (0x100000)
//    * whole-file path for files <= 0xFFFFF bytes
//    * only files >= 0x10000 (64 KB) are hashed at all
//  The macOS app uses CryptoKit's SHA256 with update(bufferPointer:) —
//  identical digest, platform-independent. This port keeps the same
//  chunking semantics so behavior matches on every OS. Blocks are
//  processed in place via unaligned loads (no per-block allocation).
//

import Foundation

public enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// Incremental hasher (mirrors CryptoKit's SHA256() usage in the app).
    public struct Hasher {
        private var h0 = UInt32(0x6a09e667), h1 = UInt32(0xbb67ae85)
        private var h2 = UInt32(0x3c6ef372), h3 = UInt32(0xa54ff53a)
        private var h4 = UInt32(0x510e527f), h5 = UInt32(0x9b05688c)
        private var h6 = UInt32(0x1f83d9ab), h7 = UInt32(0x5be0cd19)
        private var buffer = [UInt8]()   // pending bytes, always < 64
        private var length: UInt64 = 0
        private var w = [UInt32](repeating: 0, count: 64)  // scratch schedule

        public init() {}

        public mutating func update(_ data: [UInt8]) {
            data.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    update(UnsafeRawPointer(base), count: buf.count)
                }
            }
        }

        public mutating func update(_ data: Data) {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                if let base = raw.baseAddress {
                    update(base, count: raw.count)
                }
            }
        }

        mutating func update(_ base: UnsafeRawPointer, count: Int) {
            length &+= UInt64(count)
            var offset = 0
            // 1. fill a partial pending buffer
            if !buffer.isEmpty {
                let need = 64 - buffer.count
                let take = Swift.min(need, count)
                for i in 0..<take {
                    buffer.append(base.load(fromByteOffset: i, as: UInt8.self))
                }
                if take < need { return }  // still partial
                buffer.withUnsafeBufferPointer { buf in
                    processBlock(UnsafeRawPointer(buf.baseAddress!))
                }
                buffer.removeAll(keepingCapacity: true)
                offset = take
            }
            // 2. process full blocks in place (no copies)
            let fullBlocks = (count - offset) / 64
            for b in 0..<fullBlocks {
                processBlock(base + (offset + b * 64))
            }
            // 3. stash the tail
            let tailStart = offset + fullBlocks * 64
            let tailCount = count - tailStart
            if tailCount > 0 {
                for i in 0..<tailCount {
                    buffer.append(base.load(fromByteOffset: tailStart + i, as: UInt8.self))
                }
            }
        }

        public mutating func finalize() -> [UInt8] {
            // Standard SHA-256 padding: 0x80, zeros to 448 mod 512, then
            // the 64-bit big-endian bit length. The length counter is
            // captured first because padding must not count as message.
            let bitLen = length &* 8
            var padding: [UInt8] = [0x80]
            let rem = (Int(length % 64) + 1) % 64
            let zeros = (56 - rem + 64) % 64
            padding += [UInt8](repeating: 0, count: zeros)
            var bl = bitLen
            var lenBytes = [UInt8](repeating: 0, count: 8)
            for i in (0..<8).reversed() {
                lenBytes[i] = UInt8(truncatingIfNeeded: bl)
                bl >>= 8
            }
            padding += lenBytes
            var carry = buffer
            carry.append(contentsOf: padding)
            carry.withUnsafeBufferPointer { buf in
                var off = 0
                while off + 64 <= buf.count {
                    processBlock(UnsafeRawPointer(buf.baseAddress!) + off)
                    off += 64
                }
            }
            buffer = []
            var out = [UInt8]()
            out.reserveCapacity(32)
            for v in [h0, h1, h2, h3, h4, h5, h6, h7] {
                out.append(UInt8(truncatingIfNeeded: v >> 24))
                out.append(UInt8(truncatingIfNeeded: v >> 16))
                out.append(UInt8(truncatingIfNeeded: v >> 8))
                out.append(UInt8(truncatingIfNeeded: v))
            }
            return out
        }

        public mutating func hexDigest() -> String {
            finalize().map { String(format: "%02x", $0) }.joined()
        }

        private mutating func processBlock(_ p: UnsafeRawPointer) {
            for i in 0..<16 {
                w[i] = UInt32(bigEndian: p.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
            }
            for i in 16..<64 {
                let x = w[i - 15], y = w[i - 2]
                let s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
                let s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h0, b = h1, c = h2, d = h3
            var e = h4, f = h5, g = h6, hh = h7
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ ch &+ SHA256.k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d
            h4 = h4 &+ e; h5 = h5 &+ f; h6 = h6 &+ g; h7 = h7 &+ hh
        }

        private func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
            (x >> n) | (x << (32 - n))
        }
    }

    /// One-shot digest of raw bytes.
    public static func digest(_ data: [UInt8]) -> [UInt8] {
        var hasher = Hasher()
        hasher.update(data)
        return hasher.finalize()
    }

    /// File digest with the binary's exact chunking: 1 MB chunks via
    /// update() for large files, whole-file for anything under 1 MB.
    public static func fileDigest(at path: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = Hasher()
        if size <= 0xFFFFF {
            if let data = try handle.readToEnd() {
                hasher.update(data)
            }
        } else {
            let chunkSize = 0x100000  // 1 MB, binary-verified
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                hasher.update(chunk)
            }
        }
        return hasher.hexDigest()
    }
}
