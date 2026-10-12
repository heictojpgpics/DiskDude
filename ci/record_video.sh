#!/bin/bash
# record_video.sh — relaunch the app and record a browsing video of the full screen.
# Usage: record_video.sh <app-bundle> <out.mov> <fixture-root> [duration-seconds]
set -u
APP="${1:?app bundle}"
OUT="${2:?out mov}"
FIXTURE="${3:?fixture}"
DUR="${4:-20}"

BIN="$APP/Contents/MacOS/DiskDude"
DISKDUDE_SCAN="$FIXTURE" DISKDUDE_MODE=light "$BIN" > /tmp/video-app.log 2>&1 &
PID=$!

# wait for window
for i in $(seq 1 40); do
  W=$(/usr/bin/python3 - <<'PY' 2>/dev/null
import Quartz
wl = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements, Quartz.kCGNullWindowID)
for w in wl:
    if w.get('kCGWindowOwnerName') == 'DiskDude' and w.get('kCGWindowLayer') == 0:
        print(w['kCGWindowNumber']); break
PY
)
  [ -n "$W" ] && break
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.5
done
osascript -e 'tell application "System Events" to set frontmost of process "DiskDude" to true' 2>/dev/null || true
sleep 4   # auto-scan settles on fixture

screencapture -v "$OUT" &
REC=$!
sleep 1

# browse: modes, then tabs (each ~1.6s while recording)
for m in Treemap Sunburst Flame Bubbles "Mind Map" "Age Map" Outline; do
  osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
    set els to (every button of entire contents of window 1 whose name is \"${m}\")
    if (count of els) > 0 then click item 1 of els
  end tell" 2>/dev/null || true
  sleep 1.6
done
for t in Duplicates Applications Monitor Snapshots Explore; do
  name=$t; [ "$t" = "Applications" ] && name="Apps"
  osascript -e "tell application \"System Events\" to tell process \"DiskDude\"
    set els to (every button of entire contents of window 1 whose name is \"${name}\")
    if (count of els) > 0 then click item 1 of els
  end tell" 2>/dev/null || true
  sleep 2
done

kill -INT "$REC" 2>/dev/null || kill "$REC" 2>/dev/null || true
sleep 2   # let screencapture finalize the container
kill "$PID" 2>/dev/null || true
pkill -x screencapture 2>/dev/null || true
echo "video: $OUT ($(stat -f %z "$OUT" 2>/dev/null) bytes)"
