#!/bin/zsh
# Timed walk through RawLight on the Mac: welcome -> new library -> import RAWs -> Develop -> tabs -> next photos -> Export.
# Records the screen and writes a step/stall log. Usage: scripts/perf_run.sh [folder-of-raws] [out-dir]
set -e
ROOT="${0:A:h:h}"
APP="$ROOT/platforms/macos/build/rel/Build/Products/Release/RawLight.app/Contents/MacOS/RawLight"
RAWS="${1:-$HOME/Pictures/New Folder With Items/RAW Photos Edit Practice}"
OUT="${2:-$ROOT/dist/perf-$(date +%H%M%S)}"
mkdir -p "$OUT"
pkill -x RawLight 2>/dev/null || true
defaults delete com.kislay.rawlight.mac 2>/dev/null || true
screencapture -v -x "$OUT/run.mov" &
REC=$!
sleep 1
# `open` gives the app a real window session; running the binary from a shell leaves it without a visible window.
open -n -W --env RAWLIGHT_TIMING=1 --env RAWLIGHT_SCRIPT="$RAWS" --env RAWLIGHT_SCRIPT_LOG="$OUT/steps.txt" --stderr "$OUT/engine.txt" "${APP%/Contents/MacOS/RawLight}"
kill -INT $REC 2>/dev/null || true; sleep 2
echo "Output in $OUT"; cat "$OUT/steps.txt"
