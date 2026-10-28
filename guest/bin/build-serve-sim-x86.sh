#!/bin/bash
# Builds Intel (x86_64) copies of serve-sim's native parts from expo-device-hub's source, for
# T3 Code's Device panel on an Intel macOS VM. Upstream ships them for Apple silicon only.
# `macbox-guest t3-hub` runs it; it can also run on its own:
#
#   build-serve-sim-x86.sh <expo-device-hub source dir> <output dir> [native]
#
# Each upstream build.sh is copied with arm64 replaced by x86_64. Two source changes:
# - CoreDeviceShim's async function pointers ("...Descriptor") point at symbols defined in
#   other files, which x86_64 Mach-O can't express, so each gets a local jump thunk.
# - A VM has only VideoToolbox's software H.264 encoder, which holds frames back for look-ahead
#   (0.3-0.45 s; MaxFrameDelayCount is unsupported). serve-sim waits for each frame's sample,
#   times out and falls back to MJPEG. H264Encoder flushes every frame with
#   VTCompressionSessionCompleteFrames instead.
# The output dir is laid out like vendor/serve-sim/dist in the npm package.
# "native" as the third argument rebuilds only SimNative.
set -euo pipefail
SRC="$(cd "$1" && pwd)"
OUT="$2"
PKG="$SRC/packages/serve-sim/packages/serve-sim"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cd "$PKG"

# node-swift is the only npm dependency the Swift build needs.
if [ ! -d node_modules/node-swift ]; then
  version="$(sed -n 's/.*"node-swift": "\(.*\)".*/\1/p' package.json | head -1)"
  mkdir -p node_modules/node-swift
  tmp="$(mktemp -d)"
  (cd "$tmp" && npm pack "node-swift@$version" --silent >/dev/null && tar -xzf node-swift-*.tgz -C "$PKG/node_modules/node-swift" --strip-components=1)
  rm -rf "$tmp"
fi

# Thunks for CoreDeviceShim (done once; marked by the comment line).
S=Sources/CoreDeviceShim/CoreDeviceTrampolines.S
if [ -f "$S" ] && ! grep -q "x86_64 thunks" "$S"; then
  perl -0pi -e '
    my @t; while (/^\.long (_\w+) - (_\w+Descriptor)$/mg) { push @t, $1 }
    if (@t) {
      my $th = "// x86_64 thunks: x86_64 Mach-O cannot subtract a symbol defined in another\n// file, so these async function pointers point at local jumps to it.\n#if defined(__x86_64__)\n.text\n"
        . join("", map { "${_}Local:\n    jmp $_\n" } @t)
        . "#define SSCD_LOCAL(x) x##Local\n#else\n#define SSCD_LOCAL(x) x\n#endif\n\n";
      s/^\.data$/$th.data/m;
      s/^\.long (_\w+) - (_\w+Descriptor)$/.long SSCD_LOCAL($1) - $2/mg;
    }' "$S"
fi

# Flush each H.264 frame (done once; marked by the comment line).
E=Sources/SimNative/H264Encoder.swift
if [ -f "$E" ] && ! grep -q "x86_64 software encoder" "$E"; then
  perl -0pi -e 's/(            if status != noErr \{\n                completion\.resume\(returning: nil\)\n            \})/$1 else {\n                \/\/ x86_64 software encoder: emit this frame now instead of after the look-ahead.\n                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: presentationTimeStamp)\n            }/' "$E"
  grep -q "x86_64 software encoder" "$E" || { echo "H264Encoder patch did not apply (expo-device-hub changed: update this script)" >&2; exit 1; }
fi

build() { # build <source dir> <output subdir>
  [ -f "Sources/$1/build.sh" ] || return 0
  local script="Sources/$1/build-x86.sh"
  sed 's/arm64/x86_64/g' "Sources/$1/build.sh" > "$script"
  chmod +x "$script"
  echo "== $1" >&2
  "$script" "$OUT/$2"
}
if [ "${3:-all}" = all ]; then
  build ServeSimCapabilityLoader capability-loader
  build SimCameraInjector simcam
  build SimCameraHelper simcam
  build SimAXSettings simax
  build SimPasteboard simpb
  build SimPasteboardReader simpb
fi
build SimNative native
find "$OUT" -type f -exec file {} + | grep Mach-O
