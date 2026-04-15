#!/usr/bin/env bash
# Capture a screen recording of the booted iOS Simulator, then convert it
# to a web-friendly MP4 (for GitHub) and a small GIF (for pub.dev).
#
# Requirements: xcrun (Xcode CLT), ffmpeg.
#
# Usage:
#   bash demo/capture.sh                 # records for 16s
#   bash demo/capture.sh 12              # records for 12s
#   bash demo/capture.sh 16 1280         # records for 16s, output width 1280
#
# Output:
#   demo/demo.mp4  (≈500 KB – 2 MB)
#   demo/demo.gif  (≈2–4 MB)

set -euo pipefail

DURATION="${1:-16}"
WIDTH="${2:-640}"

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
RAW="$DEMO_DIR/raw.mov"

command -v xcrun  >/dev/null || { echo "Missing xcrun (Xcode CLT)."; exit 1; }
command -v ffmpeg >/dev/null || { echo "Missing ffmpeg. brew install ffmpeg"; exit 1; }

[[ -f "$RAW" ]] && rm "$RAW"

# Release any leftover ScreenCaptureKit session (Cmd+Shift+5 panel, stuck
# screencapture, or a prior simctl recording). simctl will fail with
# `allocationError` if another capture session is holding the framebuffer.
killall screencapture       2>/dev/null || true
killall ScreenshotUIService 2>/dev/null || true
pkill -f 'simctl io .* recordVideo' 2>/dev/null || true
sleep 0.5

echo "[1/3] Recording booted simulator for ${DURATION}s → $RAW"
# HEVC is the default on Apple silicon and avoids the h264 allocation bug.
xcrun simctl io booted recordVideo --codec=hevc --force "$RAW" &
REC_PID=$!

# Give simctl a beat to actually start, then count down.
sleep 1
echo "       (recording — perform any UI actions on the simulator now)"
sleep "$DURATION"

# Stop cleanly so the .mov is finalised on disk.
kill -INT "$REC_PID"
wait "$REC_PID" 2>/dev/null || true

# Sometimes simctl needs another moment to flush the trailer.
for i in 1 2 3 4 5; do
  [[ -s "$RAW" ]] && break
  sleep 0.5
done

echo "[2/3] Encoding $DEMO_DIR/demo.mp4 (H.264, ${WIDTH}px wide)"
ffmpeg -loglevel error -y -i "$RAW" \
  -vf "scale=${WIDTH}:-2" \
  -c:v libx264 -preset slow -crf 28 \
  -pix_fmt yuv420p -movflags +faststart \
  -an \
  "$DEMO_DIR/demo.mp4"

echo "[3/3] Encoding $DEMO_DIR/demo.gif (15 fps, two-pass palette)"
ffmpeg -loglevel error -y -i "$DEMO_DIR/demo.mp4" \
  -vf "fps=15,scale=${WIDTH}:-1,palettegen=stats_mode=diff" /tmp/_palette.png
ffmpeg -loglevel error -y -i "$DEMO_DIR/demo.mp4" -i /tmp/_palette.png \
  -lavfi "fps=15,scale=${WIDTH}:-1 [v]; [v][1:v] paletteuse=dither=bayer:bayer_scale=4" \
  "$DEMO_DIR/demo.gif"
rm /tmp/_palette.png "$RAW"

echo
echo "Done."
echo "  $DEMO_DIR/demo.mp4 ($(du -h "$DEMO_DIR/demo.mp4" | cut -f1))"
echo "  $DEMO_DIR/demo.gif ($(du -h "$DEMO_DIR/demo.gif" | cut -f1))"
