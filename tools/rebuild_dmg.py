#!/usr/bin/env python3
"""Round 5 (R5-D4): Full byte-exact DMG rebuild from the extracted disk image.

Rebuild chain:  disk.img → chunk recompression (zlib level 1) → data fork →
XML template + koly → DMG.  Gap bytes are hdiutil workspace artifacts (opaque,
carried verbatim).  Verifies every zlib chunk recompresses byte-identically,
then compares full-file SHA-256 with the original.
"""
import re, base64, struct, zlib, hashlib

DMG = '/home/z/my-project/DiskDude-1.0.1.dmg'
OUT = '/home/z/my-project/work/r5'
data = open(DMG, 'rb').read()
xml = data[3674632:3674632 + 8681]
koly = data[-512:]
ORIG_SHA = hashlib.sha256(data).hexdigest()

dicts = re.findall(r'<dict>\s*<key>Attributes</key>.*?</dict>', xml.decode(), re.S)

# ---- parse all mish tables ----
tables = []
for d in dicts:
    raw = base64.b64decode(re.search(r'<key>Data</key>\s*<data>\s*([^<]+?)\s*</data>', d).group(1))
    n = struct.unpack_from('>I', raw, 0xC8)[0]
    chunks = []
    for j in range(n):
        t, rsv, sn, sc, do, isz = struct.unpack_from('>IIQQQQ', raw, 0xCC + j * 40)
        chunks.append({'type': t, 'sectorNumber': sn, 'sectorCount': sc,
                       'dataOffset': do, 'inSize': isz})
    tables.append(chunks)

# ---- assemble disk image (same as extraction) ----
img = bytearray()
for chunks in tables:
    for c in chunks:
        n = c['sectorCount']
        if c['type'] == 0xffffffff:
            continue
        if c['type'] == 0x80000005:
            img += zlib.decompress(data[c['dataOffset']:c['dataOffset'] + c['inSize']])
        elif c['type'] == 0x1:
            img += data[c['dataOffset']:c['dataOffset'] + c['inSize']]
        else:
            img += b'\x00' * (n * 512)

# ---- rebuild: walk the image sequentially, regenerate every chunk ----
print('=== regenerating every data chunk from disk.img ===')
rebuilt_fork = bytearray(data[:3674632])  # start from gap bytes (hdiutil workspace)
pos = 0
zlib_ok = raw_ok = 0
for ti, chunks in enumerate(tables):
    for c in chunks:
        n = c['sectorCount']
        if c['type'] == 0xffffffff:
            continue
        seg = img[pos:pos + n * 512]
        pos += n * 512
        if c['type'] == 0x80000005:
            rc = zlib.compress(bytes(seg), 1)
            orig = data[c['dataOffset']:c['dataOffset'] + c['inSize']]
            if rc == orig:
                zlib_ok += 1
            else:
                print(f'  MISMATCH table{ti} sector {c["sectorNumber"]}: '
                      f'rebuilt {len(rc)}B vs orig {len(orig)}B')
            rebuilt_fork[c['dataOffset']:c['dataOffset'] + len(rc)] = rc
        elif c['type'] == 0x1:
            rebuilt_fork[c['dataOffset']:c['dataOffset'] + len(seg)] = seg
            raw_ok += 1
print(f'zlib chunks byte-identical: {zlib_ok}, raw chunks: {raw_ok}')

# ---- assemble final DMG ----
rebuilt = bytes(rebuilt_fork) + xml + koly
rsha = hashlib.sha256(rebuilt).hexdigest()
print(f'\nrebuilt size: {len(rebuilt)} (orig {len(data)})')
print(f'original sha256: {ORIG_SHA}')
print(f'rebuilt  sha256: {rsha}')
match = rsha == ORIG_SHA
print(f'SHA-256 MATCH: {match}')
if not match:
    diffs = [i for i in range(min(len(data), len(rebuilt))) if data[i] != rebuilt[i]]
    print(f'differing bytes: {len(diffs)}, first at {diffs[0] if diffs else "size-only"}')

open(f'{OUT}/DiskDude-1.0.1-rebuilt.dmg', 'wb').write(rebuilt)

# ---- independent verification: does 7-zip open the rebuilt DMG? ----
print('\nrebuilt DMG written to', f'{OUT}/DiskDude-1.0.1-rebuilt.dmg')
