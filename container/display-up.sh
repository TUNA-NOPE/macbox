#!/bin/bash
# Runs inside the macbox container: the display stack for the VM's window when it doesn't open on
# the host's own desktop. A private headless sway on the GPU (the Reims window fills its output),
# wayvnc on 127.0.0.1:5901 inside the container (noVNC and measurements), and the browser stream
# on port 6080 (stream-up.sh: Selkies by default). Idempotent; logs in $MACBOX_HOME/logs.
set -euo pipefail
: "${MACBOX_HOME:?}" "${MACBOX_REPO:?}"
export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p -m 700 "$XDG_RUNTIME_DIR"
L="$MACBOX_HOME/logs" RUN="$MACBOX_HOME/run"
mkdir -p "$L" "$RUN"
RENDER=${MACBOX_RENDER_NODE:-/dev/dri/renderD128}
if ! pgrep -x sway >/dev/null; then
  WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDER_DRM_DEVICE="$RENDER" \
    setsid sway -c /etc/macbox/sway.conf >"$L/sway.log" 2>&1 </dev/null &
fi
for _ in $(seq 50); do
  ls "$XDG_RUNTIME_DIR"/wayland-? >/dev/null 2>&1 && break
  sleep 0.2
done
# The output's size is the Mac's screen size (run/resolution).
R=$(cat "$RUN/resolution" 2>/dev/null || echo "${MACBOX_RESOLUTION:-1920x1080}")
SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1) \
  swaymsg output HEADLESS-1 mode "$R@60Hz" >/dev/null 2>&1 || true
# sway's socket; Selkies later adds a socket of its own beside it.
[ -s "$XDG_RUNTIME_DIR/sway.display" ] ||
  basename "$(ls "$XDG_RUNTIME_DIR"/wayland-? | head -1)" >"$XDG_RUNTIME_DIR/sway.display"
export WAYLAND_DISPLAY="$(cat "$XDG_RUNTIME_DIR/sway.display")"
if ! pgrep -x wayvnc >/dev/null; then
  # --gpu: H.264 on the GPU's encoder (VA-API) where it has one.
  setsid wayvnc --gpu --output=HEADLESS-1 --max-fps=60 127.0.0.1 5901 >"$L/wayvnc.log" 2>&1 </dev/null &
fi
"$MACBOX_REPO/container/stream-up.sh" "$(cat "$RUN/stream" 2>/dev/null || echo selkies)" >/dev/null
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
