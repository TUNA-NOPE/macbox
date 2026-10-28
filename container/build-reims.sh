#!/bin/bash
# Runs inside the macbox container (HOME=$MACBOX_HOME/home): fetches Reims vGPU and metal2vulkan at
# the commits versions.env pins, applies the patches in patches/, and builds:
#   - reims-ctl (into ~/.cargo/bin), which creates and runs the VM, and reims-util beside it, which
#     makes the VM's OpenCore image and downloads macOS from Apple;
#   - the reims-vgpu library on the Vulkan platform, and QEMU on it, installed as
#     ~/.local/share/reims-ctl/qemu/<date>-<commit><suffix> with qemu/current pointing at it.
#
#   build-reims.sh [--upstream] [--no-switch]
#     --upstream    Reims vGPU's master as it is (its own metal2vulkan and QEMU), no patches
#     --no-switch   install the new QEMU beside the others without moving qemu/current
#
# Needs about 25 GB free in MACBOX_HOME and 20 to 60 minutes. Build trees stay in
# $MACBOX_HOME/build, so later builds are incremental.
set -euo pipefail
: "${MACBOX_HOME:?}" "${MACBOX_REPO:?}"
. "$MACBOX_REPO/versions.env"
UPSTREAM=0 SWITCH=1
for a in "$@"; do
  case "$a" in
    --upstream) UPSTREAM=1 ;;
    --no-switch) SWITCH=0 ;;
    *) echo "usage: build-reims.sh [--upstream] [--no-switch]" >&2; exit 2 ;;
  esac
done
say() { printf '== %s %s\n' "$(date +%H:%M:%S)" "$*"; }
SRC="$MACBOX_HOME/src" BUILD="$MACBOX_HOME/build" DATA="$HOME/.local/share/reims-ctl"
mkdir -p "$SRC" "$BUILD" "$DATA/qemu"
free_gb=$(df --output=avail -BG "$MACBOX_HOME" | tail -1 | tr -dc 0-9)
[ "$free_gb" -ge 25 ] || [ "${FORCE:-}" = 1 ] || { echo "only ${free_gb} GB free in $MACBOX_HOME; the build needs about 25 (FORCE=1 to try anyway)" >&2; exit 2; }

# Rust, through rustup, into the container's HOME (kept across containers).
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  say "installing rustup"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none >/dev/null
fi
. "$HOME/.cargo/env"

# checkout <dir> <repo> <ref>: a clean detached checkout of <ref>; local changes are discarded
# (build trees live outside it).
checkout() {
  local dir=$1 repo=$2 ref=$3
  [ -d "$dir/.git" ] || git clone -q "$repo" "$dir"
  git -C "$dir" am --abort >/dev/null 2>&1 || true
  git -C "$dir" fetch -q origin "$ref" 2>/dev/null || git -C "$dir" fetch -q origin
  git -C "$dir" checkout -q -f --detach "$ref"
  git -C "$dir" reset -q --hard
}
apply() {  # apply <dir> <patch dir>
  local p
  for p in "$2"/*.patch; do
    [ -e "$p" ] || continue
    git -C "$1" -c user.name=macbox -c user.email=macbox@localhost am -q --committer-date-is-author-date "$p" ||
      { echo "a patch does not apply: $p" >&2; exit 1; }
  done
}

R="$SRC/reims-vgpu"
if [ "$UPSTREAM" = 1 ]; then
  say "Reims vGPU: master, no patches"
  checkout "$R" "$REIMS_REPO" master
  git -C "$R" submodule update -q --init --depth 1 vendor/qemu || git -C "$R" submodule update -q --init vendor/qemu
  SUFFIX=-upstream
else
  say "Reims vGPU ${REIMS_REF:0:7} + patches/reims-vgpu"
  checkout "$R" "$REIMS_REPO" "$REIMS_REF"
  apply "$R" "$MACBOX_REPO/patches/reims-vgpu"
  git -C "$R" submodule update -q --init vendor/qemu
  git -C "$R/vendor/qemu" fetch -q origin "$QEMU_REF" 2>/dev/null || true
  git -C "$R/vendor/qemu" checkout -q -f --detach "$QEMU_REF"
  SUFFIX=-macbox
fi
COMMIT=$(git -C "$R" rev-parse --short HEAD)

# reims-ctl first, from the tree as committed (the [patch] below is for the library only).
say "reims-ctl"
(cd "$R" && CARGO_TARGET_DIR="$BUILD/ctl" cargo install --locked --force --quiet --path crates/reims-ctl)

if [ "$UPSTREAM" = 0 ]; then
  M="$SRC/metal2vulkan"
  say "metal2vulkan ${M2V_REF:0:8} + patches/metal2vulkan"
  checkout "$M" "$M2V_REPO" "$M2V_REF"
  apply "$M" "$MACBOX_REPO/patches/metal2vulkan"
  cat >>"$R/Cargo.toml" <<EOF

# macbox: metal2vulkan ${M2V_REF:0:8} with macbox's patches (patches/metal2vulkan).
[patch."https://github.com/steelbrain/metal2vulkan"]
metal2vulkan = { path = "$M/crates/metal2vulkan" }
metal2vulkan-runtime = { path = "$M/crates/metal2vulkan-runtime" }
EOF
fi

say "the reims-vgpu library (cargo xtask dist --platform vulkan)"
TARGET="$BUILD/target"
(cd "$R" && CARGO_PROFILE_RELEASE_DEBUG=0 CARGO_TARGET_DIR="$TARGET" cargo xtask dist --platform vulkan)
PC="$TARGET/dist-vulkan/lib/pkgconfig"
[ -f "$PC/reims-vgpu.pc" ] || { echo "the library's build left no $PC/reims-vgpu.pc" >&2; exit 1; }

QB="$BUILD/qemu"
mkdir -p "$QB"
if [ ! -f "$QB/build.ninja" ] || ! cmp -s "$PC/reims-vgpu.pc" "$QB/reims-vgpu.pc.configured"; then
  say "configuring QEMU"
  (cd "$QB" && PKG_CONFIG_PATH="$PC" "$R/vendor/qemu/configure" --prefix=/reims-ctl-qemu \
    --target-list=x86_64-softmmu --enable-kvm --disable-sdl --enable-gtk --enable-slirp \
    --enable-pvg --disable-docs --disable-tests --disable-werror >/dev/null)
  cp "$PC/reims-vgpu.pc" "$QB/reims-vgpu.pc.configured"
fi
say "building QEMU"
ninja -C "$QB" >/dev/null
STAGE="$BUILD/qemu-stage"
rm -rf "$STAGE"
DESTDIR="$STAGE" ninja -C "$QB" install >/dev/null
[ -x "$STAGE/reims-ctl-qemu/bin/qemu-system-x86_64" ]
find "$STAGE/reims-ctl-qemu" -name ReimsVgpu.rom -type f | grep -q . || { echo "QEMU has no ReimsVgpu.rom" >&2; exit 1; }
ID="$(date +%Y%m%d-%H%M%S)-$COMMIT$SUFFIX"
mv "$STAGE/reims-ctl-qemu" "$DATA/qemu/$ID"
rm -rf "$STAGE"
if [ "$SWITCH" = 1 ] || [ ! -e "$DATA/qemu/current" ]; then
  ln -sfn "$ID" "$DATA/qemu/current"
  say "QEMU installed as qemu/$ID (now qemu/current)"
else
  say "QEMU installed as qemu/$ID (qemu/current unchanged: $(readlink "$DATA/qemu/current"))"
fi

# reims-util, at the commit this reims-ctl names (what upstream's scripts/install-ctl.sh does).
say "reims-util"
reims-ctl __record-install --repo "$R" --qemu "$DATA/qemu/current" --commit "$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -- Cargo.toml   # drop the [patch] again
say "done: $(reims-ctl --version 2>/dev/null || echo reims-ctl), QEMU $ID"
