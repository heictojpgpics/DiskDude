#!/usr/bin/env python3
"""make_fixtures.py — deterministic, cross-platform fixture tree for CI scans.

Design goals:
  * Physical footprint < ~60 MB (seek-based sparse files for the big stuff)
  * Logical footprint several GB (disk analyzers report logical sizes)
  * Every category bucket populated (video/image/audio/archive/doc/dev/other)
  * Exact duplicate groups (>=64 KB identical content for hash-based finders)
  * Modification dates spread across 2019..2026 (age maps / relative dates)
  * Deep nesting (flame graph) + wide fan-out (folder grids)

Usage: make_fixtures.py <fixture-root> [--home HOME] [--scale 1.0]
"""
import argparse
import os
import random
import shutil
import sys
from datetime import datetime, timedelta
from pathlib import Path

def rand_bytes(n: int, rng: random.Random) -> bytes:
    return rng.randbytes(max(1, n))

def write_sparse(path: Path, logical: int) -> None:
    """Create a file with the given logical size but tiny physical footprint."""
    if logical <= 0:
        path.touch()
        return
    with open(path, "wb") as f:
        f.seek(logical - 1)
        f.write(b"\0")

def write_random(path: Path, n: int, rng: random.Random) -> bytes:
    data = rand_bytes(n, rng)
    path.write_bytes(data)
    return data

def stamp(path: Path, y: int, m: int, d: int, hh=12, mm=0) -> None:
    ts = datetime(y, m, d, hh, mm).timestamp()
    os.utime(path, (ts, ts))

def build(root: Path, home: Path, scale: float) -> None:
    rng = random.Random(20261012)  # deterministic across platforms
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)

    def sparse_mb(mb: int) -> int:
        return int(mb * 1_000_000 * scale)

    # ---------------- Photos (image) ----------------
    vac = root / "Photos" / "2023-vacation"
    fam = root / "Photos" / "2024-family"
    vac.mkdir(parents=True)
    fam.mkdir(parents=True)
    for i, name in enumerate(
        ["beach", "sunset", "harbor", "forest", "mountain", "city",
         "night", "market", "temple", "lake", "road", "field", "sky",
         "crowd", "boat"], start=1):
        write_random(vac / f"IMG_{i:04d}.jpg", 120_000 + i * 37_000, rng)
        stamp(vac / f"IMG_{i:04d}.jpg", 2023, max(1, i % 12), min(28, i))
    for j in range(1, 7):
        write_random(fam / f"DSC_{j:04d}.heic", 300_000 + j * 51_000, rng)
        stamp(fam / f"DSC_{j:04d}.heic", 2024, j, 18)
    write_random(root / "Photos" / "wallpaper.png", 2_048_000, rng)
    stamp(root / "Photos" / "wallpaper.png", 2025, 2, 10)
    write_random(root / "Photos" / "portrait.tiff", 512_000, rng)
    stamp(root / "Photos" / "portrait.tiff", 2024, 11, 30)

    # ---------------- Videos (sparse big logical sizes) ----------------
    vid = root / "Videos"; vid.mkdir()
    write_sparse(vid / "short-clip.mp4", sparse_mb(500))
    stamp(vid / "short-clip.mp4", 2024, 6, 1, 20)
    write_sparse(vid / "go-pro-dive.mov", sparse_mb(1024))
    stamp(vid / "go-pro-dive.mov", 2023, 7, 22, 9)
    write_sparse(vid / "4k-timelapse.mp4", sparse_mb(2048))
    stamp(vid / "4k-timelapse.mp4", 2025, 3, 12)
    write_random(vid / "phone-memo.mov", 900_000, rng)
    stamp(vid / "phone-memo.mov", 2026, 1, 12)

    # ---------------- Music ----------------
    mus = root / "Music"; mus.mkdir()
    for k in range(1, 6):
        write_random(mus / f"track-0{k}.mp3", 8_000_000 + k * 1_100_000, rng)
        stamp(mus / f"track-0{k}.mp3", 2021, k, 15)
    write_sparse(mus / "lossless-album.flac", sparse_mb(300))
    stamp(mus / "lossless-album.flac", 2022, 1, 1)
    write_random(mus / "voice-note.wav", 44_000, rng)

    # ---------------- Documents ----------------
    doc = root / "Documents"; inv = doc / "invoices"
    inv.mkdir(parents=True)
    write_random(doc / "resume.pdf", 350_000, rng); stamp(doc / "resume.pdf", 2025, 3, 14)
    write_random(doc / "tax-return-2024.pdf", 900_000, rng); stamp(doc / "tax-return-2024.pdf", 2025, 4, 1)
    write_random(inv / "invoice-001.pdf", 128_000, rng); stamp(inv / "invoice-001.pdf", 2025, 1, 1)
    write_random(inv / "invoice-002.pdf", 128_000, rng); stamp(inv / "invoice-002.pdf", 2025, 2, 1)
    write_random(doc / "notes.txt", 72_000, rng); stamp(doc / "notes.txt", 2026, 10, 1)
    write_random(doc / "budget.xlsx", 260_000, rng); stamp(doc / "budget.xlsx", 2025, 9, 20)
    write_random(doc / "report.docx", 480_000, rng); stamp(doc / "report.docx", 2025, 8, 15)
    write_random(doc / "todo.md", 8_000, rng); stamp(doc / "todo.md", 2026, 10, 5)

    # ---------------- Archives ----------------
    arc = root / "Archives"; arc.mkdir()
    write_random(arc / "backup-2024.zip", 1_500_000, rng); stamp(arc / "backup-2024.zip", 2024, 12, 28)
    write_sparse(arc / "installer.dmg", sparse_mb(700)); stamp(arc / "installer.dmg", 2025, 5, 1)
    write_sparse(arc / "linux.iso", sparse_mb(1024)); stamp(arc / "linux.iso", 2025, 2, 20)
    write_random(arc / "project.tar.gz", 999_000, rng); stamp(arc / "project.tar.gz", 2025, 6, 30)

    # ---------------- Developer + deep node_modules ----------------
    dev = root / "Developer" / "MyProject"
    (dev / "src").mkdir(parents=True)
    (dev / "build").mkdir()
    for f in ["main", "model", "view", "store", "scanner", "helper", "parser", "router"]:
        write_random(dev / "src" / f"{f}.swift", 14_000 + rng.randrange(40_000), rng)
    write_random(dev / "src" / "bridge.h", 5_000, rng)
    write_random(dev / "src" / "legacy.m", 8_000, rng)
    write_random(dev / "build" / "MyProject.app", 210_000, rng)
    write_sparse(dev / "build" / "DerivedData-artifacts", sparse_mb(400))
    write_sparse(dev / "build" / "XCBuild-data", sparse_mb(600))

    nm = dev / "node_modules"
    deep = nm / "@scope" / "tool-a"
    for d in "abcdefghijklmn":
        deep = deep / d
    deep.mkdir(parents=True)
    for pkg in ["react", "webpack", "babel", "lodash", "typescript"]:
        (nm / pkg).mkdir()
    write_sparse(nm / "react" / "react.production.min.js", sparse_mb(64))
    stamp(nm / "react" / "react.production.min.js", 2024, 11, 10)
    write_random(nm / "webpack" / "bundle.js", 150_000, rng)
    write_random(nm / "babel" / "parser.js", 200_000, rng)
    write_random(nm / "lodash" / "lodash.min.js", 300_000, rng)
    stamp(nm / "lodash" / "lodash.min.js", 2023, 9, 15)
    write_sparse(nm / "typescript" / "typescript.js", sparse_mb(90))
    write_random(deep / "leaf.bin", 66_000, rng)
    for n in range(1, 13):
        write_random(nm / f"pkg-0{n:02d}.js", 20_000 + n * 900, rng)

    # ---------------- Duplicates (identical content, >= 64 KB) ----------------
    dup = root / "Duplicates"; dup.mkdir()
    photo = write_random(dup / "photo-original.jpg", 131_072, rng)
    (dup / "photo-copy-1.jpg").write_bytes(photo)
    (dup / "photo-copy-2.jpg").write_bytes(photo)
    vid_src = write_random(dup / "video-source.mp4", 262_144, rng)
    (dup / "video-duplicate.mp4").write_bytes(vid_src)
    backup = write_random(dup / "backup.zip", 200_000, rng)
    (dup / "backup-old.zip").write_bytes(backup)
    (dup / "backup-final.zip").write_bytes(backup)
    tiny = write_random(dup / "too-small.txt", 40_000, rng)
    (dup / "too-small-copy.txt").write_bytes(tiny)  # below threshold: must NOT pair
    stamp(dup / "photo-copy-2.jpg", 2020, 5, 1)
    stamp(dup / "backup-old.zip", 2022, 10, 1)

    # ---------------- Old stuff (age map spread) ----------------
    old19 = root / "OldStuff" / "2019"; old21 = root / "OldStuff" / "2021"
    old19.mkdir(parents=True); old21.mkdir()
    write_random(old19 / "taxes-2019.pdf", 61_000, rng); stamp(old19 / "taxes-2019.pdf", 2019, 4, 15)
    write_random(old19 / "photos-archive.zip", 95_000, rng); stamp(old19 / "photos-archive.zip", 2019, 12, 20)
    write_random(old21 / "presentation.key", 77_000, rng); stamp(old21 / "presentation.key", 2021, 6, 10)
    write_random(old21 / "lecture.mp4", 152_000, rng); stamp(old21 / "lecture.mp4", 2021, 10, 5)
    write_sparse(old21 / "old-backup.dmg", sparse_mb(250)); stamp(old21 / "old-backup.dmg", 2021, 3, 1)

    # ---------------- Downloads (mixed) ----------------
    dl = root / "Downloads"; dl.mkdir()
    write_random(dl / "invoice-download.pdf", 500_000, rng)
    write_random(dl / "screenshot.png", 130_000, rng)
    write_random(dl / "data.csv", 80_000, rng)
    write_sparse(dl / "big-podcast.mp3", sparse_mb(200))
    write_random(dl / "unknown.blob", 11_000, rng)
    write_random(dl / "presentation.pptx", 1_000_000, rng)

    # ---------------- Root odds and ends ----------------
    write_random(root / "README.txt", 2_200, rng)
    (root / "zero-byte.dat").touch()
    write_sparse(root / "HugeVideo_archive.mov", sparse_mb(3072))
    stamp(root / "HugeVideo_archive.mov", 2025, 3, 1)
    (root / "Empty folder").mkdir()

    # ---------------- Fake .app in ~/Applications (Apps tab) ----------------
    fake_root = home / "Applications" / "DemoWidget.app"
    if fake_root.exists():
        shutil.rmtree(fake_root)
    fake = fake_root / "Contents"
    (fake / "MacOS").mkdir(parents=True, exist_ok=True)
    (fake / "Resources").mkdir()
    (fake / "MacOS" / "DemoWidget").write_text("#!/bin/bash\necho demo\n")
    (fake / "MacOS" / "DemoWidget").chmod(0o755)
    (fake / "Info.plist").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict>'
        '<key>CFBundleExecutable</key><string>DemoWidget</string>'
        '<key>CFBundleIdentifier</key><string>com.demowidget.fixture</string>'
        '<key>CFBundleName</key><string>DemoWidget</string>'
        '<key>CFBundlePackageType</key><string>APPL</string>'
        '<key>CFBundleShortVersionString</key><string>1.0</string>'
        '</dict></plist>\n')
    write_random(fake / "Resources" / "icon.icns", 60_000, rng)
    stamp(fake / "MacOS" / "DemoWidget", 2025, 7, 4)

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path)
    ap.add_argument("--home", type=Path, default=Path.home())
    ap.add_argument("--scale", type=float, default=1.0,
                    help="shrink sparse logical sizes (disk-tight environments)")
    args = ap.parse_args()
    build(args.root, args.home, args.scale)
    total_logical = 0
    count = 0
    for p in args.root.rglob("*"):
        if p.is_file():
            total_logical += p.stat().st_size
            count += 1
    print(f"fixture ready: {args.root}")
    print(f"files: {count}, logical total: {total_logical/1e9:.2f} GB")

if __name__ == "__main__":
    main()
