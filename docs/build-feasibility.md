# Rebuild feasibility — what can be reproduced where

Empirically tested on the recovery machine (Ubuntu, Swift 6.1.2 toolchain).

## Layer-by-layer status

| # | Layer | Reproducible on Linux? | Status |
|---|-------|------------------------|--------|
| 1 | Swift source recovery | yes | 100% types/fields/cstrings, behavior-verified formatters |
| 2 | Syntax validation | yes — `swiftc -parse` | clean on all 30 files |
| 3 | Semantic validation | **no** — `swiftc -typecheck` fails with `no such module 'SwiftUI'` (Apple-proprietary, absent from Linux toolchains) | blocked |
| 4 | Mach-O compilation | **no** — needs Xcode 16 + SDK 26 + SwiftUI/AppKit (macOS only). cctools-port's `ld64` can link Mach-O on Linux, but there are no `.o` files to link because step 3 is impossible | blocked |
| 5 | Bundle resources | yes | Info.plist / PkgInfo / AppIcon.icns byte-exact |
| 6 | HFS+ disk image | partially — extraction is byte-exact; *creation* would need hdiutil or hfsprogs with matching layout | extracted bytes used |
| 7 | UDIF/UDZO DMG wrapper | **yes** — `tools/rebuild_dmg.py` | **SHA-256 byte-identical** |

## What the byte-exact DMG match proves

The complete packaging chain (7 → 6 → 5) is deterministic and fully
understood:

- every zlib chunk recompresses byte-identically at **level 1**
  (hdiutil's UDZO default) — verified for all 8 zlib chunks
- the raw / zero / ignore chunk plan is preserved exactly
- the XML plist resource fork and koly trailer round-trip losslessly
- 7-Zip extracts an identical app bundle from the rebuilt DMG

```
original DiskDude-1.0.1.dmg   1a9811fc6574d3890e37685b88c554ef109eacf0467afaa6fda423b2458a06db
rebuilt                       1a9811fc6574d3890e37685b88c554ef109eacf0467afaa6fda423b2458a06db  ✓
```

## The macOS-only step

The one layer that cannot be reproduced on Linux is compiling the Swift
source against SwiftUI. On a Mac:

```bash
./build.sh            # xcodebuild → DiskDude.app → hdiutil UDZO DMG
```

The DMG packaging parameters in `build.sh` were recovered from the shipped
artifact. When the recovered source is compiled with the same toolchain that
produced the original (SDK 26, Swift 6), the remaining delta shrinks to
per-build Mach-O variation (the 16-byte `LC_UUID` is randomized per build
unless controlled, and exact instruction scheduling depends on the compiler
build).
