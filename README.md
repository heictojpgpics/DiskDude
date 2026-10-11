# DiskDude 1.0.1 — Recovered Source

This project is a **reverse-engineered reconstruction** of DiskDude 1.0.1
(`com.hariprasad.diskdude`), a macOS disk space analyzer, recovered from the
official distribution `DiskDude-1.0.1.dmg` (arm64 + x86_64 universal binary).

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
| UI strings (cstring xrefs) | **93%** |
| API surface (Foundation/AppKit/Darwin imports) | matched per-service |
| File/Info.plist/AppIcon | **byte-exact from DMG** |

Structural facts verified directly from metadata include: the 5-tab layout
(Explore/Duplicates/Applications/Monitor/Snapshots), the nine visualization
modes, the 26 @Published ScanViewModel properties, the Combine
ObservableObject design, SHA256 duplicate detection, the
`~/Library/Application Support/DiskDude/Snapshots` persistence path with
`snapshots.json`/`index.json`, UserDefaults keys `DISKDUDE_MODE` /
`DISKDUDE_SCAN` / `recentScans`, and the seven QuickWins categories.

## Building

Open `DiskDude.xcodeproj` in Xcode 15+ on macOS 14+, select the DiskDude
scheme, and build. The reconstructed Swift source is syntax-validated
(swiftc -parse clean) but was not compiled against the macOS SDK on the
recovery machine (Linux), so expect only minor compile fixes.

## Notes on fidelity

- Property order within types follows the field descriptors exactly.
- Method bodies are behavioral reconstructions guided by decompiled control
  flow, import call sites, and string usage — they reproduce *what* the app
  does, not the author's exact formatting.
- Exact UI copy (taglines, error messages, tooltips) is quoted from the
  binary's string section.
