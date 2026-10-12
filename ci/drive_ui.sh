#!/bin/bash
# drive_ui.sh — launch DiskDude, drive it through a UI tour, capture per-state shots.
#
# Usage: drive_ui.sh <app-bundle> <shots-dir> <fixture-root> [mode: light|dark] [prefix]
#
# Hardened against the Round-6 black-screenshot failure:
#   * launches the executable DIRECTLY (env vars propagate; stdout/stderr captured)
#   * verifies the process is alive before any capture
#   * waits for a real CGWindowID (Quartz CGWindowList) instead of blind sleeps
#   * captures the exact window rect (screencapture -R) — never the bare desktop
#   * collects macOS crash reports if the app dies
set -u

APP="${1:?app bundle path}"
OUT="${2:?shots dir}"
FIXTURE="${3:?fixture root}"
MODE="${4:-light}"
PREFIX="${5:-app}"

BIN="$APP/Contents/MacOS/DiskDude"
mkdir -p "$OUT"
LOG="$OUT/${PREFIX}-stdout.log"

# ---------------------------------------------------------------- window utils
win_id() {  # CGWindowNumber of a normal-layer window owned by DiskDude
  /usr/bin/python3 - <<'PY'
import Quartz
wl = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
    Quartz.kCGNullWindowID)
for w in wl:
    if w.get('kCGWindowOwnerName') == 'DiskDude' and w.get('kCGWindowLayer') == 0:
        print(w['kCGWindowNumber'])
        break
PY
}
win_bounds() {  # "x,y,w,h" of that window
  /usr/bin/python3 - "${1:-}" <<'PY'
import Quartz, sys
wl = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID)
for w in wl:
    if w.get('kCGWindowOwnerName') == 'DiskDude' and w.get('kCGWindowLayer') == 0:
        if sys.argv[1] and str(w['kCGWindowNumber']) != sys.argv[1]:
            continue
        b = w['kCGWindowBounds']
        print(f"{int(b['X'])},{int(b['Y'])},{int(b['Width'])},{int(b['Height'])}")
        break
PY
}

# ---------------------------------------------------------------- launch
echo "launching $BIN (DISKDUDE_SCAN=$FIXTURE, DISKDUDE_MODE=$MODE)"
DISKDUDE_SCAN="$FIXTURE" DISKDUDE_MODE="$MODE" "$BIN" > "$LOG" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$OUT/${PREFIX}.pid"

WID=""
for i in $(seq 1 60); do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "FATAL: app died during launch (exit below)"; cat "$LOG"
    ls -t "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | head -3
    exit 1
  fi
  WID=$(win_id)
  [ -n "$WID" ] && break
  sleep 0.5
done
if [ -z "$WID" ]; then
  echo "FATAL: no window appeared after 30s"; cat "$LOG"; exit 1
fi
echo "window up: id=$WID pid=$APP_PID"

# Bring frontmost + normalize geometry (best effort; fall back to natural bounds)
osascript -e 'tell application "System Events" to set frontmost of process "DiskDude" to true' 2>/dev/null || true
osascript -e 'tell application "System Events" to tell process "DiskDude"
  set size of window 1 to {1000, 640}
  set position of window 1 to {12, 44}
end tell' 2>/dev/null || true
sleep 1

# let the auto-scan settle (small fixture → fast, but cover worst case)
sleep 5

shot() { # shot <name> — capture current window rect
  local name="$1"
  local B=$(win_bounds "$WID")
  if [ -z "$B" ]; then echo "capture skipped (window gone): $name"; return 1; fi
  screencapture -x -R"$B" -t png "$OUT/${PREFIX}-${name}.png"
  echo "captured $OUT/${PREFIX}-${name}.png [$B]"
}

ax_click() { # ax_click <button-name> — click a button by AX name in window 1
  local name="$1"
  osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
  click (button 1 of window 1 whose name is \"${name}\" )
end tell" 2>/dev/null && { echo "clicked [${name}]"; return 0; }
  # fallback: search the entire AX tree for the first matching button
  osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
  set hitBtns to every button of window 1
  repeat with el in hitBtns
    if name of el is \"${name}\" then click el; exit repeat
  end repeat
end tell" 2>/dev/null && return 0
  # deeper fallback: entire contents
  osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
  set els to (every button of entire contents of window 1 whose name is \"${name}\")
  if (count of els) > 0 then click item 1 of els
end tell" 2>/dev/null && { echo "clicked(deep) [${name}]"; return 0; }
  echo "MISS [${name}] — button not found in AX tree"
  return 1
}

ax_dump() { # dump AX tree for debugging when clicks miss
  osascript -e 'tell application "System Events" to tell process "DiskDude"
    get name of every button of window 1
  end tell' 2>/dev/null | tr ',' '\n' > "$OUT/${PREFIX}-axbuttons.txt" || true
  osascript -e 'tell application "System Events" to tell process "DiskDude"
    get name of every UI element of window 1
  end tell' 2>/dev/null >> "$OUT/${PREFIX}-axbuttons.txt" || true
}

# ---------------------------------------------------------------- tour
shot "01-explore-initial"
ax_dump

# 9 visualization modes (Explore tab)
for m in Treemap Folders Sunburst Flame Bubbles "Mind Map" "Top Sizes" "Age Map" Outline; do
  n=0
  until ax_click "$m" || [ $n -ge 2 ]; do n=$((n+1)); sleep 1; done
  sleep 1.2
  slug=$(echo "$m" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  shot "02-explore-${slug}"
done

# back to Treemap, then the 5 tabs
ax_click "Treemap" || true; sleep 0.8
shot "03-tabs-explore"

for t in Duplicates "Apps" Monitor Snapshots; do
  n=0
  until ax_click "$t" || [ $n -ge 2 ]; do n=$((n+1)); sleep 1; done
  sleep 1.5
  slug=$(echo "$t" | tr '[:upper:]' '[:lower:]')
  shot "04-tab-${slug}"
done

# Duplicates tab: kick off the duplicate scan, wait for results, capture
if ax_click "Duplicates"; then
  sleep 1
  if ax_click "Scan for Duplicates"; then
    sleep 8   # hash the fixture duplicates
    shot "05-duplicates-results"
  else
    ax_dump
    shot "05-duplicates-noresults"
  fi
fi

# Apps tab: reload + capture the list
if ax_click "Apps"; then
  sleep 1
  ax_click "Reload Apps" || true
  sleep 5
  shot "06-apps-list"
fi

# Dark theme pass on the Explore tab
osascript -e 'tell application "System Events" to tell process "DiskDude"
  keystroke "d" using {command down, option down}
end tell' 2>/dev/null || true
sleep 1
shot "07-explore-dark"

# ---------------------------------------------------------------- teardown
kill "$APP_PID" 2>/dev/null || true
sleep 1
echo "tour complete: $(ls "$OUT" | grep -c "${PREFIX}-") captures"
exit 0
