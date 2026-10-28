#!/bin/bash
# Runs inside the macbox container: the browser stream of the Mac's screen on port 6080
# (published on the host as 127.0.0.1:$MACBOX_SCREEN_PORT).
#   stream-up.sh selkies   Selkies (default): H.264 over one WebSocket, on the GPU's encoder
#                          (VA-API or NVENC) where there is one, else in software. Its bitrate
#                          follows the path, so a slow link drops frames instead of queueing them.
#   stream-up.sh novnc     noVNC over wayvnc: no rate control; fine on a fast, direct path
#   stream-up.sh restart   Selkies again, at the size in run/resolution
#   stream-up.sh status
# The choice is kept in $MACBOX_HOME/run/stream. Selkies is installed into $MACBOX_HOME/selkies-venv
# on first use (pip, the version versions.env pins).
set -euo pipefail
: "${MACBOX_HOME:?}" "${MACBOX_REPO:?}"
. "$MACBOX_REPO/versions.env"
export XDG_RUNTIME_DIR=/tmp/xdg
L="$MACBOX_HOME/logs" RUN="$MACBOX_HOME/run" VENV="$MACBOX_HOME/selkies-venv"
mkdir -p "$L" "$RUN"
pids() {  # PIDs of the Python program $1 (path suffix) listening on 6080
  ps -eo pid=,args= | awk -v prog="$1" '$2 ~ /python3(\.[0-9]+)?$/ && substr($3, length($3) - length(prog) + 1) == prog && / (--port=)?6080( |$)/ {print $1}'
}
stop_all() {  # both run under setsid: the PID is the group, so helpers go too
  for p in $(pids /bin/websockify) $(pids selkies-venv/bin/selkies); do
    kill -- "-$p" 2>/dev/null || kill "$p" 2>/dev/null || true
  done
  for _ in $(seq 30); do [ -z "$(pids /bin/websockify)$(pids selkies-venv/bin/selkies)" ] && break; sleep 0.2; done
}
RES=$(cat "$RUN/resolution" 2>/dev/null || echo "${MACBOX_RESOLUTION:-1920x1080}")
case "${1:-status}" in
  restart)
    for p in $(pids selkies-venv/bin/selkies); do kill -- "-$p" 2>/dev/null || kill "$p" 2>/dev/null || true; done
    for _ in $(seq 30); do [ -z "$(pids selkies-venv/bin/selkies)" ] && break; sleep 0.2; done
    exec "$0" selkies
    ;;
  selkies)
    if [ ! -x "$VENV/bin/selkies" ] || ! "$VENV/bin/pip" show selkies 2>/dev/null | grep -qx "Version: $SELKIES_VERSION"; then
      python3 -m venv "$VENV"
      "$VENV/bin/pip" install -q "selkies==$SELKIES_VERSION" >"$L/selkies-install.log" 2>&1
    fi
    if [ -z "$(pids selkies-venv/bin/selkies)" ]; then
      stop_all
      # zwlr: sway 1.12's ext-image-copy-capture never delivers a frame to pixelflux;
      # wlr-screencopy works, still zero copy into the encoder.
      PIXELFLUX_HOST_CAPTURE=zwlr setsid "$VENV/bin/selkies" \
        --wayland=true --wayland-host-display="$(cat "$XDG_RUNTIME_DIR/sway.display")" \
        --public --port=6080 --enable-basic-auth=false \
        --allowed-origins="${MACBOX_STREAM_ORIGINS:-http://127.0.0.1:${MACBOX_SCREEN_PORT:-6081},http://localhost:${MACBOX_SCREEN_PORT:-6081}}" \
        --encode-dri="${MACBOX_RENDER_NODE:-/dev/dri/renderD128}" --framerate=60 \
        --video-bitrate="${MACBOX_STREAM_BITRATE:-8000,500-100000}" --scaling-dpi=96 \
        --manual-resolution=true --manual-width="${RES%x*}" --manual-height="${RES#*x}" --enable-resize=false \
        --audio-enabled=false --microphone-enabled=false --webcam-enabled=false \
        --gamepad-enabled=false --printing-enabled=false --file-transfers=none \
        --ui-title="${MACBOX_STREAM_TITLE:-macbox}" --ui-sidebar-show-audio-settings=false \
        --ui-sidebar-show-gamepads=false --ui-sidebar-show-webcam=false \
        --ui-sidebar-show-sharing=false --ui-sidebar-show-apps=false --ui-sidebar-show-files=false \
        >"$L/selkies.log" 2>&1 </dev/null &
    fi
    echo selkies >"$RUN/stream"
    ;;
  novnc)
    if [ -z "$(pids /bin/websockify)" ]; then
      stop_all
      setsid websockify --web /usr/share/novnc 6080 127.0.0.1:5901 >"$L/websockify.log" 2>&1 </dev/null &
    fi
    echo novnc >"$RUN/stream"
    ;;
  status) ;;
  *) echo "usage: stream-up.sh selkies|novnc|restart|status" >&2; exit 2 ;;
esac
s=none
[ -n "$(pids selkies-venv/bin/selkies)" ] && s=selkies
[ -n "$(pids /bin/websockify)" ] && s=novnc
echo "stream: $s (chosen: $(cat "$RUN/stream" 2>/dev/null || echo selkies))"
