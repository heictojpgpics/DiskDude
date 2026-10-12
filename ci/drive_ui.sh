#!/bin/bash
# drive_ui.sh — launch DiskDude, drive it through a UI tour, capture per-state shots.
#
# Usage: drive_ui.sh <app-bundle> <shots-dir> <fixture-root> [mode: light|dark] [prefix]
#
# Hardened (rounds 6-7 failure lessons):
#   * launches the executable DIRECTLY (env vars propagate; stdout/stderr captured)
#   * chmod +x the binary (artifact round-trips strip the executable bit)
#   * window discovery via System Events AppleScript (no pyobjc on runners)
#   * TEARDOWN WAITS for the app to actually die — two live "DiskDude"
#     processes make every `tell process "DiskDude"` query ambiguous and
#     that is what killed the rebuilt-app tour in round 7
#   * window size respects the app's 1100x720 minimum
#   * multi-strategy clicks: AX name -> description -> help -> coordinates
#   * dumps the AX tree into the tour log for live debugging
set -u

APP="${1:?app bundle path}"
OUT="${2:?shots dir}"
FIXTURE="${3:?fixture root}"
MODE="${4:-light}"
PREFIX="${5:-app}"

BIN="$APP/Contents/MacOS/DiskDude"
chmod +x "$BIN" 2>/dev/null || true
mkdir -p "$OUT"
LOG="$OUT/${PREFIX}-stdout.log"

# make sure NO stale DiskDude is alive (ambiguity guard)
pkill -x DiskDude 2>/dev/null || true
sleep 1

# crash-report helper: prints the newest DiskDude crash report if any
dump_crash_reports() {
  local newest
  newest=$(ls -t "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | grep -i diskdude | head -2)
  if [ -n "$newest" ]; then
    for f in $newest; do
      echo "--- crash report: $f ---"
      head -80 "$HOME/Library/Logs/DiagnosticReports/$f" 2>/dev/null
    done
  else
    echo "(no DiskDude crash reports found)"
    ls -t "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | head -5
  fi
}

# ---------------------------------------------------------------- window utils
win_rect() {
  osascript -e 'tell application "System Events" to tell process "DiskDude"
    get {position, size} of window 1
  end tell' 2>/dev/null | tr -d ' '
}

# ---------------------------------------------------------------- launch
echo "launching $BIN (DISKDUDE_SCAN=$FIXTURE, DISKDUDE_MODE=$MODE)"
DISKDUDE_SCAN="$FIXTURE" DISKDUDE_MODE="$MODE" "$BIN" > "$LOG" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$OUT/${PREFIX}.pid"

RECT=""
for i in $(seq 1 60); do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "FATAL: app died during launch (stdout below)"; cat "$LOG"
    dump_crash_reports
    exit 1
  fi
  # zombie guard: kill -0 succeeds on zombies — a crashed child looks "alive"
  if [ "$(ps -o stat= -p "$APP_PID" 2>/dev/null | tr -d ' ')" = "Z" ]; then
    echo "FATAL: app crashed at launch (zombie process — crash report below)"
    cat "$LOG" 2>/dev/null
    dump_crash_reports
    exit 1
  fi
  RECT=$(win_rect)
  [ -n "$RECT" ] && break
  sleep 0.5
done
if [ -z "$RECT" ]; then
  echo "FATAL: no window appeared after 30s"; cat "$LOG" 2>/dev/null
  # the process may be hung OR crashed with reports — dump both
  ps -o pid,stat,etime,command -p "$APP_PID" 2>/dev/null || true
  sample "$APP_PID" 2 2>/dev/null | head -60 || true
  dump_crash_reports
  exit 1
fi
echo "window up: pid=$APP_PID rect=$RECT"

# Bring frontmost + normalize geometry (respect the app's 1100x720 minimum)
osascript -e 'tell application "System Events" to set frontmost of process "DiskDude" to true' 2>/dev/null || true
osascript -e 'tell application "System Events" to tell process "DiskDude"
  set size of window 1 to {1100, 730}
  set position of window 1 to {12, 30}
end tell' 2>/dev/null || true
sleep 1

# let the auto-scan settle (small fixture completes in ~1s; cover worst case)
sleep 5

shot() { # shot <name> — capture the current window rect
  local name="$1"
  local B=$(win_rect)
  if [ -z "$B" ]; then echo "capture skipped (window gone): $name"; return 1; fi
  screencapture -x -R"$B" -t png "$OUT/${PREFIX}-${name}.png"
  echo "captured $OUT/${PREFIX}-${name}.png [$B]"
}

# click at screen coordinates: click_xy <x> <y>
click_xy() {
  osascript -e "tell application \"System Events\" to click at {$1, $2}" 2>/dev/null
}

# screen coords of a window-relative point: win_xy <relx> <rely>
win_xy() {
  local B=$(win_rect)
  [ -z "$B" ] && return 1
  local wx wy
  wx=$(echo "$B" | cut -d, -f1)
  wy=$(echo "$B" | cut -d, -f2)
  echo "$((wx + $1)),$((wy + $2))"
}

ax_click() { # ax_click <button-name> [relx rely] — AX then coordinate fallback
  local name="$1"
  local relx="${2:-}" rely="${3:-}"
  # strategy 1: AX name
  if osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
  click (button 1 of window 1 whose name is \"${name}\")
end tell" >/dev/null 2>&1; then echo "clicked(ax-name) [${name}]"; return 0; fi
  # strategy 2: entire-contents by name
  if osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
  set els to (every button of entire contents of window 1 whose name is \"${name}\")
  if (count of els) > 0 then click item 1 of els
end tell" >/dev/null 2>&1; then echo "clicked(ax-deep) [${name}]"; return 0; fi
  # strategy 3: entire-contents by description
  if osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
  set els to (every button of entire contents of window 1 whose description is \"${name}\")
  if (count of els) > 0 then click item 1 of els
end tell" >/dev/null 2>&1; then echo "clicked(ax-desc) [${name}]"; return 0; fi
  # strategy 4: coordinate fallback (window-relative)
  if [ -n "$relx" ] && [ -n "$rely" ]; then
    local P=$(win_xy "$relx" "$rely")
    if [ -n "$P" ]; then
      click_xy "${P%,*}" "${P#*,}"
      echo "clicked(xy) [${name}] @ $P"
      return 0
    fi
  fi
  echo "MISS [${name}]"
  return 1
}

ax_dump() { # dump the AX tree into the tour log (visible in CI logs)
  echo "--- AX tree (levels 0-2) of DiskDude window 1 ---"
  osascript -e 'tell application "System Events" to tell process "DiskDude"
    set out to ""
    repeat with el in UI elements of window 1
      set out to out & (role of el) & " | " & (value of el as text) & " | " & (name of el as text) & linefeed
      try
        repeat with sub in UI elements of el
          set out to out & "  " & (role of sub) & " | " & (name of sub as text) & linefeed
        end repeat
      end try
    end repeat
    return out
  end tell' 2>/dev/null || echo "(AX dump failed)"
  echo "--- end AX tree ---"
}

# ---------------------------------------------------------------- tour
shot "01-explore-initial"
ax_dump

# 5 tabs — top bar, window-relative centers measured from the live layout
# (tab row ≈ y 93; x centers: Explore 114, Duplicates 219, Apps 344,
#  Monitor 456, Snapshots 564 — derived from the runner screenshot)
ax_click "Explore" 114 93 || true
for t in Duplicates Apps Monitor Snapshots; do
  case "$t" in
    Duplicates) relx=219 ;;
    Apps) relx=344 ;;
    Monitor) relx=456 ;;
    Snapshots) relx=564 ;;
  esac
  ax_click "$t" "$relx" 93 || true
  sleep 1.5
  slug=$(echo "$t" | tr '[:upper:]' '[:lower:]')
  shot "04-tab-${slug}"
  # return to Explore after each tab so the mode strip is visible again
  ax_click "Explore" 114 93 || true
  sleep 1
done

# 9 visualization modes (Explore tab, mode strip under the tab bar)
# first click Explore to make sure we are on it, then try each mode
ax_click "Explore" 114 93 || true
sleep 1
for m in Treemap Folders Sunburst Flame Bubbles "Mind Map" "Top Sizes" "Age Map" Outline; do
  n=0
  until ax_click "$m" || [ $n -ge 1 ]; do n=$((n+1)); sleep 1; done
  sleep 1.2
  slug=$(echo "$m" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  shot "02-explore-${slug}"
done

# Duplicates tab: run the duplicate scan, wait, capture
ax_click "Duplicates" 219 93 || true
sleep 1
ax_click "Scan for Duplicates" 167 200 || true
sleep 8   # hash the fixture duplicates
shot "05-duplicates-results"

# Apps tab: reload + capture the list
ax_click "Apps" 344 93 || true
sleep 1
ax_click "Reload Apps" || true
sleep 5
shot "06-apps-list"

# ---------------------------------------------------------------- teardown
kill "$APP_PID" 2>/dev/null || true
# WAIT for the app to die — a lingering DiskDude process makes the next
# app's System Events queries ambiguous (round-7 lesson)
for i in $(seq 1 20); do
  kill -0 "$APP_PID" 2>/dev/null || break
  sleep 0.5
done
pkill -x DiskDude 2>/dev/null || true
sleep 1
echo "tour complete: $(ls "$OUT" 2>/dev/null | grep -c "${PREFIX}-") captures"
exit 0
