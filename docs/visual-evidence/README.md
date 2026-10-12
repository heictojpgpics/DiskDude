# Visual evidence — original vs rebuilt (macOS CI runner)

Captured by `.github/workflows/ui-visual.yml` on a GitHub Actions macos-26
runner: both apps were launched, the screen captured via `screencapture`.

- `original-main.png` — DiskDude 1.0.1 as shipped (light-mode window)
- `rebuilt-main.png` — rebuilt from recovered source (first-run state)

First-run states differ (original's idle screen vs ours), which is expected
at this recovery stage — the workflow exists to drive convergence rounds:
window position/size are normalized by AppleScript, and the pixel diff is
computed per run. Each recovery iteration should shrink the delta.
