#!/bin/zsh
# End-to-end check of RawLight on the Mac, on real RAW files.
#   1. every slider, look, crop, mask, heal, history, export and watermark flow (headless, no window)
#   2. a recorded walk through the real window: welcome, new library, import, Develop, tabs, next photo, Export
# Usage: scripts/e2e_mac.sh [folder-of-raws]   (the walk needs the screen on and Screen Recording permission)
set -e
ROOT="${0:A:h:h}"
APP="$ROOT/platforms/macos/build/rel/Build/Products/Release/RawLight.app"
RAWS="${1:-$HOME/Pictures/New Folder With Items/RAW Photos Edit Practice}"
OUT="$ROOT/dist/e2e-$(date +%H%M%S)"; mkdir -p "$OUT"
pkill -x RawLight 2>/dev/null || true
echo "== 1/2 headless feature check on real RAWs"
RAWLIGHT_SELFTEST_RAWS="$RAWS" RAWLIGHT_SELFTEST="$OUT/features.txt" "$APP/Contents/MacOS/RawLight" || true
tail -1 "$OUT/features.txt"; grep -v '^PASS' "$OUT/features.txt" || true
echo "== 2/2 recorded walk"
"$ROOT/scripts/perf_run.sh" "$RAWS" "$OUT/walk" | tail -3
echo "Results in $OUT"
