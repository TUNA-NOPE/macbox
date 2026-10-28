#!/bin/bash
# Keeps the simulator stream in T3 Code's Device panel light, so it stays responsive over a
# remote link: H.264 at MACBOX_STREAM_BITRATE bit/s (default 1200000) and MACBOX_STREAM_FPS
# frames/s (default 30), and the MJPEG fallback at 20 frames/s, quality 0.5. serve-sim's
# defaults are 6 Mbit/s and 60 frames/s (MJPEG 60, 0.7), more than VideoToolbox's software
# encoder in a VM keeps up with.
# T3 starts expo-device-hub with fixed options and serve-sim forgets runtime settings when it
# restarts, so the LaunchAgent dev.macbox.sim-stream-settings (`macbox-guest stream-settings
# install`) runs this every 20 s. It acts only on a simulator the hub already streams
# (webrtc/stats answers 404 otherwise; asking for stream-settings would start a capture for
# nobody), and only while the stream is at serve-sim's default bitrate, so a setting chosen in
# the panel stays.
BITRATE="${MACBOX_STREAM_BITRATE:-1200000}"
FPS="${MACBOX_STREAM_FPS:-30}"
WANT="{\"h264Bitrate\":$BITRATE,\"h264Fps\":$FPS,\"mjpegFps\":20,\"mjpegQuality\":0.5}"
for hub in "$HOME"/.t3/device/hosts/*/hub.json; do
  [ -f "$hub" ] || continue
  port=$(plutil -extract port raw "$hub" 2>/dev/null) || continue
  for udid in $(xcrun simctl list devices booted | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"); do
    base="http://127.0.0.1:$port/vendor/serve-sim/helper/$udid"
    curl -sf -m 5 -o /dev/null "$base/webrtc/stats" || continue
    url="$base/stream-settings"
    cur=$(curl -s -m 5 "$url") || continue
    case "$cur" in *'"h264Bitrate":6000000'*) ;; *) continue ;; esac
    curl -s -m 10 -X PATCH -H "Content-Type: application/json" -d "$WANT" "$url" >/dev/null &&
      echo "$(date "+%F %T") $udid: $WANT"
  done
done
