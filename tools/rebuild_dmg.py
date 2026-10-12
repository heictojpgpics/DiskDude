#!/usr/bin/env python3
"""tools/rebuild_dmg.py — byte-exact UDIF (UDZO) container rebuild.

Usage:  python3 tools/rebuild_dmg.py <original.dmg> [output.dmg]

Rebuild chain:  parse koly trailer → parse XML plist mish tables →
decompress chunks → recompress at zlib level 1 (hdiutil UDZO default) →
regenerate data fork → append XML + koly → SHA-256 compare.

This reproduces the DMG *container* byte-for-byte from the original's own
HFS+ payload — the deterministic baseline for the recovery pipeline. It is
path-independent and runs on any OS (pure Python, no deps).

Note: this verifies the CONTAINER layer. A true source-level rebuild must
first produce a byte-identical Mach-O (see .github/workflows/build.yml),
after which the same packaging parameters apply.
"""
import base64
import hashlib
import re
import struct
import sys
import zlib


def parse_koly(dmg):
    """UDIF trailer: 512 bytes at EOF (big-endian).
    Layout: magic 'koly'(0x00), version, headerSize, flags,
    runningDataForkOffset(0x10), dataForkOffset(0x18), dataForkLength(0x20),
    rsrcFork(0x28..0x38), segmentNumber/Count, segmentID uuid (0x40),
    dataChecksum(0x58..0xD8), xmlOffset(0xF8), xmlLength(0x100), ..."""
    koly = dmg[-512:]
    magic, version, headerSize = struct.unpack(">4sII", koly[:12])
    assert magic == b"koly", f"not a UDIF image (magic={magic!r})"
    xmlOffset, xmlLength = struct.unpack(">QQ", koly[0xD8:0xE8])
    dataForkOffset, dataForkLength = struct.unpack(">QQ", koly[0x18:0x28])
    return {"xmlOffset": xmlOffset, "xmlLength": xmlLength,
            "dataForkOffset": dataForkOffset, "dataForkLength": dataForkLength,
            "trailer": koly}


def parse_mish_tables(xml_text):
    """Every <dict> with Attributes/Data holds a mish block (blkx table).
    Chunk entry (40 bytes): type, reserved, sectorNumber, sectorCount,
    dataOffset, inSize — at offset 0xCC within the decoded block."""
    tables = []
    for d in re.findall(r"<dict>\s*<key>Attributes</key>.*?</dict>", xml_text, re.S):
        raw = base64.b64decode(
            re.search(r"<key>Data</key>\s*<data>\s*([^<]+?)\s*</data>", d).group(1))
        n = struct.unpack_from(">I", raw, 0xC8)[0]
        chunks = []
        for j in range(n):
            t, _rsv, sn, sc, do, isz = struct.unpack_from(">IIQQQQ", raw, 0xCC + j * 40)
            chunks.append({"type": t, "sectorNumber": sn, "sectorCount": sc,
                           "dataOffset": do, "inSize": isz})
        tables.append(chunks)
    return tables


def decompress_image(dmg, tables):
    """Walk all mish tables, decompress chunks into the HFS+ disk image."""
    img = bytearray()
    for chunks in tables:
        for c in chunks:
            n = c["sectorCount"]
            if c["type"] == 0xFFFFFFFF:          # zero fill
                continue
            if c["type"] == 0x80000005:           # zlib
                img += zlib.decompress(dmg[c["dataOffset"]:c["dataOffset"] + c["inSize"]])
            elif c["type"] == 0x1:                # raw
                img += dmg[c["dataOffset"]:c["dataOffset"] + c["inSize"]]
            else:                                  # ignore/unknown → zeros
                img += b"\x00" * (n * 512)
    return img


def rebuild(dmg_path, out_path):
    dmg = open(dmg_path, "rb").read()
    orig_sha = hashlib.sha256(dmg).hexdigest()
    koly = parse_koly(dmg)
    xml = dmg[koly["xmlOffset"]:koly["xmlOffset"] + koly["xmlLength"]]
    tables = parse_mish_tables(xml.decode())

    img = decompress_image(dmg, tables)
    print(f"parsed {len(tables)} mish tables; disk image {len(img):,} bytes")

    # Regenerate the data fork: keep hdiutil workspace gap bytes verbatim,
    # rewrite every chunk from the decompressed image.
    fork_end = koly["xmlOffset"]
    fork = bytearray(dmg[:fork_end])
    pos = 0
    zlib_ok = raw_ok = mismatches = 0
    for ti, chunks in enumerate(tables):
        for c in chunks:
            n = c["sectorCount"]
            if c["type"] == 0xFFFFFFFF:
                continue
            seg = img[pos:pos + n * 512]
            pos += n * 512
            if c["type"] == 0x80000005:
                rc = zlib.compress(bytes(seg), 1)
                orig = dmg[c["dataOffset"]:c["dataOffset"] + c["inSize"]]
                if rc == orig:
                    zlib_ok += 1
                else:
                    mismatches += 1
                    print(f"  chunk mismatch table{ti} sector {c['sectorNumber']}: "
                          f"{len(rc)}B vs {len(orig)}B")
                fork[c["dataOffset"]:c["dataOffset"] + len(rc)] = rc
            elif c["type"] == 0x1:
                fork[c["dataOffset"]:c["dataOffset"] + len(seg)] = seg
                raw_ok += 1
    print(f"zlib chunks byte-identical: {zlib_ok}, raw chunks: {raw_ok}, "
          f"mismatches: {mismatches}")

    rebuilt = bytes(fork) + xml + koly["trailer"]
    rebuilt_sha = hashlib.sha256(rebuilt).hexdigest()

    print(f"rebuilt size : {len(rebuilt):,} (orig {len(dmg):,})")
    print(f"original sha256: {orig_sha}")
    print(f"rebuilt  sha256: {rebuilt_sha}")
    match = rebuilt_sha == orig_sha
    print(f"SHA-256 MATCH : {match}")
    if not match:
        diffs = [i for i in range(min(len(dmg), len(rebuilt))) if dmg[i] != rebuilt[i]]
        print(f"differing bytes: {len(diffs)}, first at "
              f"{hex(diffs[0]) if diffs else 'size-only'}")

    open(out_path, "wb").write(rebuilt)
    print(f"wrote {out_path}")
    return 0 if match else 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    out = sys.argv[2] if len(sys.argv) > 2 else "rebuilt.dmg"
    sys.exit(rebuild(sys.argv[1], out))
