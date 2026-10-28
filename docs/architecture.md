# How macbox fits together

```
host (Linux, KVM, a Vulkan GPU)
├─ macbox (bash)  ── reads ~/.config/macbox/macbox.env, the environment over it
├─ ssh macbox     ── 127.0.0.1:2226 ──┐
├─ browser        ── 127.0.0.1:6081 ──┼─ Docker publishes them (127.0.0.1 only)
│                                     │
└─ container "macbox" (image macbox:run; /dev/kvm, the render node; MACBOX_HOME mounted at its own path)
   ├─ sway (headless, on the GPU) ── wayvnc :5901 (inside only) ── Selkies :6080 ── host :6081
   │     or, with `macbox view local`, the host's own Wayland socket instead of sway
   └─ QEMU (Reims vGPU's build) under reims-ctl
        ├─ apple-gfx-pci ── reims-vgpu ── metal2vulkan ── Vulkan (Mesa) ── the GPU
        ├─ its window (SDL3 on Wayland): fills sway's output, or a window on the host's desktop
        ├─ passt ── container port 22 ── host :2226
        ├─ NVMe (after install) ── $MACBOX_HOME/home/.local/share/reims-ctl/vms/mac/disk
        └─ macOS 26 (x86-64)
             ├─ Remote Login (user dev, the host's key)
             ├─ ~/.macbox: macbox-guest and its tools; ~/.local/lib/mac-sim: mac-sim's helper + agent-device
             ├─ Xcode, the iOS Simulator runtime, the pool "iPhone NN Pro (macbox slim 1)", ...
             └─ T3 Code's expo-device-hub, rebuilt for Intel ── over ssh ── T3 Code's Device panel
```

## The container

One image, `macbox:run` ([docker/Dockerfile](../docker/Dockerfile)), builds and runs everything:
Ubuntu 26.10 (for Mesa 26.2 and Python 3.14), the build tools for Reims vGPU and QEMU, and the run
stack (passt, sway, wayvnc, noVNC, VA-API drivers). Selkies installs into a venv under
`MACBOX_HOME` on first use.

The container keeps nothing of its own: its HOME is `$MACBOX_HOME/home` (Rust, `reims-ctl`, the
QEMU builds, the VM), mounted at the same path inside and outside, and the checkout is mounted
read-only at its own path. `macbox down` removes the container; `macbox up` makes a new one.

It runs with seccomp and AppArmor unconfined, because passt needs a user namespace. It gets
`/dev/kvm`, the render node and, if there is one, `/dev/udmabuf` (AMD). Its ports are published on
127.0.0.1 only.

## Builds

`container/build-reims.sh` (run by `macbox build` in a throwaway container) checks out Reims vGPU,
QEMU and metal2vulkan at the commits [versions.env](../versions.env) pins, applies
[patches/](../patches/README.md), points Reims's Cargo at the patched metal2vulkan, and builds
`reims-ctl`, the library (`cargo xtask dist --platform vulkan`) and QEMU on it. Each QEMU goes into
`~/.local/share/reims-ctl/qemu/<date>-<commit>-macbox` and `qemu/current` moves to it. A running VM
keeps its QEMU until it restarts, and old builds stay for going back
(`ln -sfn <build> .../qemu/current`). Build trees live in `$MACBOX_HOME/build`, so builds after the
first are incremental.

## The VM

`reims-ctl` owns the VM's directory (`vm.toml`, the disk, OpenCore's image, OVMF and its variables)
and the QEMU command line; `reims-ctl command mac` (inside the container) prints it. macbox sets:

- reims-ctl's own network off, and a passt NIC in `extra_args` instead: passt forwards the
  container's port 22 to the guest, and Docker publishes that as `127.0.0.1:$MACBOX_SSH_PORT`.
  reims-ctl's own forward would listen on the container's loopback, which Docker can't publish.
- `-set drive.disk.discard=unmap` (guest TRIM frees space) and `cache=$MACBOX_DISK_CACHE`.
- `--video-acceleration=false` (no VideoToolbox/M2 scaler devices), a borderless window,
  `REIMS_VGPU_STATS=1` (a line of frame statistics a second in `logs/qemu.log`).
- Before each start: `WAYLAND_DISPLAY` (sway's, or the host's), and the GPU tuning:
  `M2V_LIVE=$MACBOX_HOME/run/live.conf` with `host_rt_in_place=1`, and `M2V_ARL_FACTS` on an
  Arrow Lake GPU ([performance.md](performance.md)).

The system disk starts on SATA, because macOS's installer may not find a disk on NVMe, and moves to
NVMe with `macbox disk nvme` once macOS is installed.

## The screen

Reims draws each guest display into a window of its own (SDL3). QEMU's VNC would read every frame
back from the GPU, 2 to 3 frames a second, so macbox never uses it.

- **Stream (default).** The window fills the output of a private headless sway in the container.
  Selkies captures that output (wlr-screencopy, zero copy), encodes H.264 on the GPU where it can,
  and sends it over one WebSocket at a bitrate it steers by the browser's acknowledgements, so a
  slow link drops frames instead of queueing seconds of them. The browser draws the cursor.
  `macbox stream novnc` switches to noVNC over wayvnc (no rate control).
- **Local.** `macbox view local` mounts the invoking user's Wayland socket into the container, and
  the window opens on the host's desktop, full screen and 1:1: nothing is captured or encoded.

The screen's size is `$MACBOX_HOME/run/resolution` (`macbox resolution WxH`); sway's output and
Selkies follow it.

## Driving the GUI

`macbox screenshot | click | move | scroll | type | key | wait` run [lib/vmctl.py](../lib/vmctl.py)
in the container against QEMU's QMP socket: screendumps, and absolute mouse and keyboard events. That
is enough for an agent to install macOS, go through Setup Assistant and turn on SSH by itself.
`type -` reads the text from stdin, so a password never shows in a process list.

## The guest

Everything inside macOS comes from [guest/](../guest/README.md), copied to `~/.macbox` by
`macbox provision` and run as `~/.macbox/macbox-guest <step>` over SSH. Each step is idempotent.

## The simulators

| Piece | Where | |
|---|---|---|
| the pool | macOS | `macbox-guest pool create`: simulators named `<device> (<prefix> <label>)`, custom 1x device types copied from the stock profile with `mainScreenScale` changed |
| `mac-sim` | host | claims a pool simulator per checkout (git root), copies the checkout to the Mac, builds there, runs Metro on the host (`macbox-sim-metro-<name>`, a user unit) and reaches it from the Mac through an SSH reverse tunnel, drives the simulator with agent-device. State in `~/.local/state/macbox/mac-sim/` |
| `mac-sim-remote` | macOS, `~/.local/lib/mac-sim/` | the Mac side of mac-sim; mac-sim copies it there when it changes |
| `mac-sim-idle.timer` | host | every 5 minutes, shuts down pool simulators idle for 20 minutes (no mac-sim command, no viewer, no app coming to the front) |
| `sim-fps` | host | reads a recording; fps and dropped frames per stretch of motion |
| `android-sim` | host | the same shape for local Android emulators |

Simulators draw only when their screen changes, and each one booted costs GPU and CPU in the VM,
which is why the pool is small, mostly 1x, and shuts idle ones down.

## T3 Code

T3 Code's Device panel can show iOS devices on another Mac over SSH: a `deviceHosts` entry of kind
`ssh` whose target is an SSH alias. `macbox t3 register` adds one with the target `macbox`. T3 then
installs its device hub (expo-device-hub, which includes serve-sim) on the Mac, and runs it there
over SSH. The hub's native parts ship for Apple silicon only, so `macbox t3 fix-hub` rebuilds them
for x86-64 from the hub's own source, with three changes ([docs/t3-code.md](t3-code.md)).

## Config

`~/.config/macbox/macbox.env`, written by `macbox init`, is plain `KEY=value` and is read by
`macbox`, `mac-sim`, `android-sim` and `phone-build`; the environment overrides it. Every port,
path, name and size is a setting there, so two macboxes on one host only need different
`MACBOX_HOME`, `MACBOX_CONTAINER`, `MACBOX_SSH_HOST` and ports.

## Repo layout

```
macbox                    the CLI
versions.env              the pinned upstream commits
docker/                   the image (Dockerfile, sway.conf)
container/                scripts that run inside the container: build-reims.sh, display-up.sh, stream-up.sh
lib/vmctl.py              screenshots, mouse and keyboard through QMP
patches/                  the series on Reims vGPU and metal2vulkan
guest/                    everything copied into macOS (macbox-guest and its tools)
sims/                     the agent tools on the host (mac-sim, sim-fps, android-sim) and their user units
skills/                   the simulators and phone-builds skills
agents/                   the instructions snippet and the Claude Code hook
bench/                    the benchmark tools (simfps, GlassBench, GenieBench)
docs/                     these documents
```

