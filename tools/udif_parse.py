#!/usr/bin/env python3
"""Round 5 (R5-D2): Complete UDIF/UDZO structure parser.

Decodes: koly trailer (corrected offsets), XML plist resource fork, all blkx
mish tables with 40-byte chunk entries, and extracts the full uncompressed
disk image. Empirical field mapping validated against the visible MBR/GPT
blocks. Output: work/r5/udif_structure.json + work/r5/disk.img
"""
import struct, json, base64, zlib, os, sys

DMG = '/home/z/my-project/DiskDude-1.0.1.dmg'
OUT = '/home/z/my-project/work/r5'
os.makedirs(OUT, exist_ok=True)
data = open(DMG, 'rb').read()
print(f'DMG size: {len(data)}')

# ---------- koly trailer ----------
koly = data[-512:]
assert koly[:4] == b'koly'
u32 = lambda o: struct.unpack_from('>I', koly, o)[0]
u64 = lambda o: struct.unpack_from('>Q', koly, o)[0]
hdr = {
    'version': u32(4), 'headerSize': u32(8), 'flags': u32(12),
    'runningDataForkOffset': u64(16), 'dataForkOffset': u64(24), 'dataForkLength': u64(32),
    'resourceForkOffset': u64(40), 'resourceForkLength': u64(48),
    'segmentNumber': u32(56), 'segmentCount': u32(60),
    'segmentID': koly[64:80].hex(),
    'dataChecksumType': u32(80), 'dataChecksumSize': u32(84), 'dataChecksum': koly[88:216].hex(),
    'xmlOffset': u64(216), 'xmlLength': u64(224),
    'masterChecksumType': u32(352), 'masterChecksumSize': u32(356),
    'masterChecksum': koly[360:488].hex(),
    'imageVariant': u32(488), 'sectorCount': u32(492),
    'reserved2': koly[496:512].hex(),
}
for k, v in hdr.items():
    print(f'  koly.{k}: {v}')

xml = data[hdr['xmlOffset']:hdr['xmlOffset'] + hdr['xmlLength']]
open(f'{OUT}/dmg_xml.plist', 'wb').write(xml)

# ---------- parse plist blkx entries (regex — we only need the Data blobs) ----------
import re
entries = re.findall(
    r'<key>CFName</key>\s*<string>([^<]+)</string>.*?<key>Data</key>\s*<data>\s*([^<]+?)\s*</data>',
    xml.decode('utf-8'), re.S)
print(f'\nblkx entries: {len(entries)}')

def parse_mish(b64):
    raw = base64.b64decode(b64)
    sig, version = struct.unpack_from('>4sI', raw, 0)
    assert sig == b'mish', sig
    sectorNumber, sectorCount, dataOffset, buffersNeeded = struct.unpack_from('>QQQQ', raw, 8)
    blockDescriptors, reserved = struct.unpack_from('>II', raw, 40)
    checksumType, checksumSize = struct.unpack_from('>II', raw, 48)
    checksum = raw[56:184]
    numChunks = struct.unpack_from('>I', raw, 184)[0]
    chunks = []
    off = 188
    for i in range(numChunks):
        ctype, comment, csec, csecCount, cdataOff, cbufSize = struct.unpack_from('>IIQQQI', raw, off) if False else (
            struct.unpack_from('>IIQQQQ', raw, off))
        # 40-byte entry: type(4), comment(4), sectorNumber(8), sectorCount(8), dataOffset(8), bufferSize(8)?
        chunks.append({
            'type': ctype, 'comment': comment, 'sectorNumber': csec,
            'sectorCount': csecCount, 'dataOffset': cdataOff, 'field5': cbufSize,
        })
        off += 40
    return {
        'name': None, 'sectorNumber': sectorNumber, 'sectorCount': sectorCount,
        'dataOffset': dataOffset, 'buffersNeeded': buffersNeeded,
        'blockDescriptors': blockDescriptors, 'checksumType': checksumType,
        'checksumSize': checksumSize, 'checksum': checksum.hex(),
        'numChunks': numChunks, 'chunks': chunks, 'raw_len': len(raw),
    }

tables = []
for name, b64 in entries:
    t = parse_mish(b64)
    t['name'] = name
    tables.append(t)
    types = {}
    for c in t['chunks']:
        types[c['type']] = types.get(c['type'], 0) + 1
    print(f"  {name[:48]:50s} sectors {t['sectorNumber']}-{t['sectorNumber']+t['sectorCount']}"
          f" chunks={t['numChunks']} types={ {hex(k): v for k, v in types.items()} }")

# chunk type legend
TYPE = {0: 'zero', 1: 'raw', 2: 'ignore', 0x80000004: 'adc', 0x80000005: 'zlib',
        0x80000006: 'bzip2', 0x80000007: 'lzfse', 0x80000008: 'lzma',
        0x7ffffffe: 'comment', 0xffffffff: 'terminator'}

# ---------- extract disk image ----------
SECTOR = 512
total_sectors = sum(t['sectorCount'] for t in tables)
img = bytearray(b'\x00' * (total_sectors * SECTOR))
img_len = 0
for t in tables:
    for c in t['chunks']:
        s = c['sectorNumber']
        n = c['sectorCount']
        if n == 0:
            continue
        start = s * SECTOR
        end = start + n * SECTOR
        ct = TYPE.get(c['type'], hex(c['type']))
        if ct == 'zlib':
            comp = data[c['dataOffset']:c['dataOffset'] + c['field5']]
            raw = zlib.decompress(comp)
            assert len(raw) == n * SECTOR, (len(raw), n * SECTOR)
            img[start:end] = raw
        elif ct == 'raw':
            img[start:end] = data[c['dataOffset']:c['dataOffset'] + n * SECTOR]
        elif ct in ('zero', 'ignore'):
            pass
        img_len = max(img_len, end)
print(f'\nDisk image: {img_len} bytes ({img_len/1e6:.1f} MB), {img_len//SECTOR} sectors')
open(f'{OUT}/disk.img', 'wb').write(img[:img_len])
print('sha256(disk.img):', __import__('hashlib').sha256(img[:img_len]).hexdigest())
# HFS+ signature check
print('signature at sector 2 (HFS+):', img[1024:1028])
print('GPT/MBR at 0:', img[446:510].hex()[:40], '... sig:', img[510:512].hex())

json.dump({'koly': hdr, 'tables': tables}, open(f'{OUT}/udif_structure.json', 'w'), indent=1)
print('structure saved to', f'{OUT}/udif_structure.json')
