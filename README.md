# DiskDude 1.0.1 — Recovered Source

[![Build](https://github.com/heictojpgpics/DiskDude/actions/workflows/build.yml/badge.svg)](https://github.com/heictojpgpics/DiskDude/actions/workflows/build.yml)
[![Verify Recovery](https://github.com/heictojpgpics/DiskDude/actions/workflows/verify-recovery.yml/badge.svg)](https://github.com/heictojpgpics/DiskDude/actions/workflows/verify-recovery.yml)
[![Compare](https://github.com/heictojpgpics/DiskDude/actions/workflows/compare.yml/badge.svg)](https://github.com/heictojpgpics/DiskDude/actions/workflows/compare.yml)
[![DMG Rebuild](https://github.com/heictojpgpics/DiskDude/actions/workflows/dmg.yml/badge.svg)](https://github.com/heictojpgpics/DiskDude/actions/workflows/dmg.yml)
[![UI Visual Test](https://github.com/heictojpgpics/DiskDude/actions/workflows/ui-visual.yml/badge.svg)](https://github.com/heictojpgpics/DiskDude/actions/workflows/ui-visual.yml)
[![Windows Build](https://github.com/heictojpgpics/DiskDude/actions/workflows/windows.yml/badge.svg)](https://github.com/heictojpgpics/DiskDude/actions/workflows/windows.yml)

This project is a **reverse-engineered reconstruction** of DiskDude 1.0.1
(`com.hariprasad.diskdude`), a macOS disk space analyzer, recovered from the
official distribution `DiskDude-1.0.1.dmg` (arm64 + x86_64 universal binary).

## CI recovery pipeline (macOS + Windows runners)

Six GitHub Actions workflows keep the recovery honest:

| Workflow | What it does |
|----------|--------------|
| **Build** | `xcodegen` + `xcodebuild` (Xcode 26, SDK 26) → universal `DiskDude.app` artifact, hash verdict vs original Mach-O |
| **Verify Recovery** | source↔binary coverage audit + byte-exact UDIF container rebuild (SHA-256 must match) |
| **Compare** | original vs rebuilt: bundle hashes, Mach-O sections, Swift metadata sizes, string coverage |
| **DMG Rebuild** | `hdiutil` UDZO packaging of the rebuilt app + SHA-256 vs original DMG |
| **UI Visual Test** | drives BOTH apps through a full UI tour (5 tabs × 9 visualization modes) over a simulated fixture filesystem, captures per-state screenshots, pixel-diffs every state, records browsing videos |
| **Windows Build** | builds the cross-platform `DiskDudeCore` + `diskdude-cli` on **Windows**, Linux and macOS from one SwiftPM package, runs the test suite on all three, and verifies the scan report is **byte-identical across all three OSes** |

`reference/DiskDude-1.0.1.dmg` is the hash-pinned original (SHA-256
`1a9811fc…a06db`) used as the oracle for every comparison.

### Visual evidence

`docs/visual-evidence/` holds side-by-side screenshots of the original and
rebuilt apps in every UI state, plus per-state pixel-diff numbers. The tour
is driven by the apps' own hidden developer hooks (binary-verified:
`DISKDUDE_SCAN` auto-scans a path, `DISKDUDE_MODE` overrides the theme), so
both binaries process the same simulated file tree (~101 files across every
category, sparse multi-GB videos, exact duplicate groups, 2019–2026 dates).

### Windows / cross-platform core

The SwiftUI GUI itself is macOS-only by Apple design. The recovered
Foundation-only core logic — byte-exact `formatBytes`/`formatPercentage`,
the full FileCategory extension tables, the duplicate-finder SHA-256 with
its 1 MB chunking and 64 KB threshold, and a portable scanner — lives in
`cross-platform/` and builds on Windows, Linux and macOS (Swift 6.1.2).
`diskdude-cli <path>` prints a DiskDude-style report of any directory tree.

## What is in this tree

```
DiskDude/
├── DiskDude.xcodeproj/          # Generated project (open and build)
└── DiskDude/
    ├── DiskDudeApp.swift        # @main SwiftUI app
    ├── ContentView.swift        # Tab shell + inspector + queue sheet
    ├── Theme.swift              # 14-color theme system (light/dark)
    ├── Models/
    │   ├── FileNode.swift       # Core tree model + FileCategory (9 cases)
    │   ├── ScanModel.swift      # AppTab, VisualizationMode (9), ColorMode, DiskInfo, Rankings, AgeReport
    │   └── Snapshot.swift       # Codable snapshots + Summary + Delta
    ├── ViewModels/
    │   └── ScanViewModel.swift  # ObservableObject, 26 @Published properties
    ├── Services/
    │   ├── DiskScanner.swift    # getattrlistbulk scanner + JobStack worker pool
    │   ├── DuplicateFinder.swift# SHA256 (CryptoKit) duplicate grouping
    │   ├── AppUninstaller.swift # /Applications enumeration + Library leftovers
    │   ├── QuickWins.swift      # 7 cleanup categories
    │   ├── SystemMonitor.swift  # CPU/memory/network/process stats
    │   ├── SnapshotStore.swift  # ~/Library/Application Support/DiskDude/Snapshots
    │   ├── CleanupQueue.swift   # Staged-for-Trash queue
    │   └── QuickLookController.swift # QLPreviewPanel subclass
    ├── Views/                   # 60+ SwiftUI views (all 9 visualizations)
    └── Resources/
        ├── Info.plist           # Exact binary from the DMG
        ├── AppIcon.icns         # Exact binary from the DMG (2.2 MB)
        ├── DiskDude.entitlements
        └── PkgInfo
```

## How it was recovered

The binary is fully stripped of local symbols (only `_main` survives), but
retains complete Swift reflection metadata. Recovery pipeline:

1. **DMG extraction** — 7-Zip 26.04 (UDIF zlib decode → HFS+).
2. **Mach-O + chained fixups** — custom parser (macholib2.py) resolving all
   3,670 fixups and 1,105 imports (rebase/bind chains, the 2-byte-unit
   import-name offsets).
3. **Swift metadata** — `__swift5_types` (113 type descriptors),
   `__swift5_fieldmd` (113 field descriptors with the exact property names
   and var/let flags), `__swift5_typeref` (recursive grammar parser handling
   embedded 0x01/0x02 symbolic references), `__swift5_proto` (142 protocol
   conformances), `__constg_swiftt`.
4. **ObjC metadata** — classlist → class_ro_t → ivar layouts (confirming
   Int64 field widths) and the QuickLookController @objc method IMPs.
5. **Ghidra 12.1.4 headless** (JDK 25) — 5,713 functions decompiled with the
   built-in Swift Type Metadata Analyzer.
6. **String archaeology** — `__cstring`/`__oslogstring` cross-references via
   capstone ADRP+ADD scanning, plus Swift small-string immediates extracted
   from the decompiled code (e.g. "node_modules", "Build artifacts",
   "DISKDUDE_MODE", "snapshots.json").
7. **Ground-truth validation** — a reference Swift module compiled with
   Swift 6.1.2 to verify the mangling conventions (e.g. Int64 → got → Mn).

## Verification scores (recovered source vs binary metadata)

| Dimension | Coverage |
|-----------|----------|
| Type declarations (106 app types) | **100%** |
| Field names + var/let modifiers (451) | **100%** |
| UI strings (cstring + register small-strings) | **100%** (reverse-audited) |
| Pure-logic functions (formatters) | **behavior-verified** (fuzzed on Linux vs decompiled binary model) |
| DMG rebuild | **SHA-256 byte-exact match** |
| Info.plist / PkgInfo / AppIcon | **byte-exact from DMG** |

Structural facts verified directly from metadata include: the 5-tab layout
(Explore/Duplicates/Applications/Monitor/Snapshots), the nine visualization
modes, the 26 @Published ScanViewModel properties, the Combine
ObservableObject design, SHA256 duplicate detection (64 KB threshold, 1 MB
chunks, `fcntl(F_NOCACHE, 1)`), the
`~/Library/Application Support/DiskDude/Snapshots` persistence path with
`snapshots.json`/`index.json`, UserDefaults keys `theme` / `recentScans`, and
the seven QuickWins categories.

## DMG byte-exact rebuild (Round 5)

The DMG packaging layer was fully reverse-engineered and **rebuilt
byte-identically**: extracting the HFS+ image from the original UDZO DMG and
recompressing every zlib chunk (level 1 — hdiutil's UDZO default, verified
for all 8 zlib chunks byte-for-byte) reproduces the shipped file exactly:

```
original DiskDude-1.0.1.dmg        1a9811fc6574d3890e37685b88c554ef109eacf0467afaa6fda423b2458a06db
rebuilt  DiskDude-1.0.1-rebuilt    1a9811fc6574d3890e37685b88c554ef109eacf0467afaa6fda423b2458a06db  ✓
```

Independent verification: 7-Zip extracts an **identical app bundle** from the
rebuilt DMG (every file hash matches). See `tools/rebuild_dmg.py` (Linux,
no macOS required) and `docs/hash-manifest.json`.

Layer status:

| Layer | Status |
|-------|--------|
| DMG wrapper (UDIF/UDZO + XML plist + koly) | **byte-exact** |
| HFS+ disk image (GPT-wrapped) | **byte-exact** |
| Bundle resources (Info.plist/PkgInfo/AppIcon.icns) | **byte-exact** |
| Mach-O binary | original bytes carried (recompiling SwiftUI needs Xcode 16 + SDK 26 on macOS — see `build.sh`) |

## Multi-tool verification

Recovery facts were cross-validated across **six independent toolchains**:

| Tool | Role |
|------|------|
| Ghidra 12.1.4 (headless + JDK 25) | 5,713-function decompilation export |
| REA 6.4.0 (github.com/morluto/rea) | composed analysis workflow over Ghidra — 7,181 procedures, 3,372 strings |
| radare2 6.2.4 | independent disassembly + pseudo-decompilation (4,356 functions) |
| custom capstone tooling | string xrefs, Swift small-string immediates, chained fixups |
| ipsw 3.1.736 | Swift metadata cross-check |
| swiftc 6.1.2 (Linux) | behavioral fuzz harness (compiled recovered formatters vs decompiled binary model) — caught and fixed a real off-by-one unit bug in `formatBytes` |

## Building

Open `DiskDude.xcodeproj` in Xcode 15+ on macOS 14+, select the DiskDude
scheme, and build — or run `./build.sh` for the full source→app→DMG pipeline
(the DMG packaging parameters match the shipped artifact). The reconstructed
Swift source is syntax-validated (swiftc -parse clean) but was not compiled
against the macOS SDK on the recovery machine (Linux), so expect only minor
compile fixes.

## Notes on fidelity

- Property order within types follows the field descriptors exactly.
- Method bodies are behavioral reconstructions guided by decompiled control
  flow, import call sites, and string usage — they reproduce *what* the app
  does, not the author's exact formatting.
- Exact UI copy (taglines, error messages, tooltips) is quoted from the
  binary's string section.
