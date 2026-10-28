# Setting up macbox

From a Linux host to macOS with Xcode, an iOS Simulator pool, T3 Code's Device panel and the
agent tools. Plan on two to three hours, mostly downloads and builds. Run `./macbox next` at any
point: it shows which steps are done and prints the next one.

## 1. The host

- **KVM:** `/dev/kvm` must exist and be yours to open: `sudo usermod -aG kvm $USER` on most
  distributions, then log in again.
- **The GPU:** you need its render node (`/dev/dri/renderD128` on most machines with one GPU) and
  the right to open it: `sudo usermod -aG render $USER`. With more than one GPU, pick the node in
  the config (`MACBOX_RENDER_NODE`); `/sys/class/drm/renderD*/device/vendor` says whose each is
  (0x8086 Intel, 0x1002 AMD). An AMD GPU also needs `/dev/udmabuf` (often the `kvm` group).
- **vm.max_map_count:** Reims maps guest memory in many small views, so the default 65530 is far
  too low: `echo vm.max_map_count=2097152 | sudo tee /etc/sysctl.d/60-macbox.conf && sudo sysctl --system`.
- **Docker:** rootless Docker works well and is what macbox was built on. Podman should work too
  (`MACBOX_DOCKER=podman`); it's untested.
- **Disk:** about 150 GB free where `MACBOX_HOME` lives (default `~/.local/share/macbox`), ideally
  on an SSD or NVMe: the VM's disk, Xcode and the build trees all go there.

## 2. Config and checks

```sh
git clone <this repo> ~/macbox && cd ~/macbox
./macbox init
```

`init` writes `~/.config/macbox/macbox.env` with values for this machine (CPUs, memory, the render
node), makes an SSH key `~/.ssh/macbox_ed25519`, and adds a `Host macbox` block to `~/.ssh/config`
(127.0.0.1, port 2226, user `dev`). Look at the config before you go on. Most worth setting:

| Setting | Default | |
|---|---|---|
| `MACBOX_CPUS`, `MACBOX_MEMORY` | half the host's cores (4 to 8), a third of its RAM (8 to 16 GB) | the VM's size |
| `MACBOX_DISK_SIZE` | 160G | the VM's disk (sparse: it takes what macOS writes) |
| `MACBOX_RESOLUTION`, `MACBOX_REFRESH` | 1920x1080, 60 | macOS's screen; more pixels cost GPU time |
| `MACBOX_CPUSET` | empty | pin QEMU to some cores, e.g. a hybrid CPU's performance cores (`0-7`) |
| `MACBOX_BUILD_CPUSET` | empty | cores for `macbox build`, e.g. the efficiency cores |
| `MACBOX_DISK_CACHE` | writeback | `unsafe` is faster, but a crash of the host itself can corrupt the VM's disk |
| `MACBOX_HOME` | ~/.local/share/macbox | everything macbox keeps |

Then:

```sh
./macbox doctor
```

Fix every FAIL. WARN lines are advice.

## 3. Build

```sh
./macbox build
```

This builds the Docker image (`macbox:run`: Ubuntu 26.10, Mesa, sway, passt, the stream's
dependencies), then, in a container, Reims vGPU and its QEMU on metal2vulkan with macbox's patches
([patches/README.md](../patches/README.md)), and `reims-ctl` and `reims-util`. The first build
takes 20 to 60 minutes and about 25 GB; later ones are incremental. `./macbox build --upstream`
builds Reims's current master as it is, without macbox's patches.

## 4. Create the VM

```sh
./macbox create                  # the newest macOS 26 Tahoe, through Apple's recovery image (~1 GB)
./macbox create --macos 26.6.2 --offline   # or one exact release, as a full installer (13 to 20 GB)
./macbox boot-picker on          # OpenCore's boot menu, for the Recovery step below
./macbox up
```

The screen: open http://127.0.0.1:6081/ in a browser on the host (Selkies). Or, if you sit at the
host and it runs a Wayland desktop, `./macbox view local` opens macOS in a window there, with no
encoding at all. Click into it to give it the keyboard; Ctrl+Alt+Super gives the keyboard back.

To watch from another machine, forward the port: `ssh -L 6081:127.0.0.1:6081 <host>`, then open
http://127.0.0.1:6081/ there. Or publish it on a tailnet (`tailscale serve --bg --https=8481
http://127.0.0.1:6081`) and add that origin to `MACBOX_STREAM_ORIGINS` in the config. The stream
has no password of its own, so never publish it on the open internet.

## 5. Install macOS

The VM starts in macOS Recovery, from Apple's installer:

1. In OpenCore's menu, the installer is the default; it boots by itself after 5 seconds.
2. Open **Disk Utility**, choose View > Show All Devices, select **QEMU HARDDISK Media**, and
   **Erase** it as APFS (GUID partition map). Quit Disk Utility.
3. Choose **Reinstall macOS** and follow it onto that disk. It downloads macOS from Apple and
   restarts a few times: 30 to 60 minutes. Leave OpenCore's menu to its default each time.
   (With `--offline`, run `sh /Volumes/Installer/install-macos.sh` in Utilities > Terminal instead.)

## 6. Metal's error mode, from Recovery (once)

macOS 26 needs `METAL_ERROR_MODE=5` under Reims, or its icon service crashes and the desktop never
comes up properly (no Dock, or a gray screen). Set it before the first desktop:

1. When the install has finished (Setup Assistant, or a broken desktop, appears), restart the VM
   (`./macbox down && ./macbox up`).
2. In OpenCore's menu, press an arrow key to stop the countdown and choose the **Recovery** entry.
3. In Recovery, open Utilities > **Terminal**, then on the host:

   ```sh
   ./macbox recovery-fix
   ```

   It types the line Reims's README gives into that Terminal. The VM restarts only if every step
   worked. If it doesn't restart, read the error in the screen and fix it.
4. Choose macOS in the menu.

## 7. Setup Assistant

Go through it in the screen: your country, a keyboard, **no** Apple Account (skip it; you don't need
one in macOS), and an **administrator account named `dev`** (or what you set as
`MACBOX_GUEST_USER`) with a password you'll need once more in step 8. Turn off everything else it
offers (Location Services, analytics, Screen Time, Siri).

## 8. SSH

On the desktop, open Terminal (⌘Space, "Terminal", Return), then on the host:

```sh
./macbox ssh-bootstrap
```

It types into that Terminal: your SSH key into `~/.ssh/authorized_keys`, then the commands that
turn Remote Login on. `sudo` asks for the password in the VM's Terminal: type it there (or
`./macbox type -` and `./macbox key ret`). Then:

```sh
ssh macbox sw_vers
```

If Remote Login is still off: System Settings > General > Sharing > **Remote Login** on, and also
"Allow full disk access for remote users" (agents' tools read simulator data over SSH).

From here on, everything is commands.

## 9. Faster disk, no boot menu

```sh
./macbox down
./macbox disk nvme          # ejects the installer and moves the system disk to NVMe
./macbox boot-picker off
./macbox up
```

On NVMe, a 4K read in macOS takes about a third less time than on the emulated SATA, and apps start
up to twice as fast. OpenCore finds the disk by itself.

## 10. Provision macOS

```sh
./macbox provision
```

Copies `guest/` to `~/.macbox` on the Mac and runs it ([guest/README.md](../guest/README.md)):
passwordless sudo (it asks for the password once), no sleep or screen lock, Spotlight indexing and
automatic update downloads off, Node, Ruby 3.4 and CocoaPods, simslim, the `setmode` tool, and the
LaunchAgent that keeps the Device panel's stream light. Safe to run again.

## 11. Xcode

Download Xcode 26's `.xip` from https://developer.apple.com/download/all/ (any free Apple Account
can sign in there; macbox never handles your Apple ID), then:

```sh
./macbox xcode ~/Downloads/Xcode_26.6.xip
```

It copies the file into the VM, expands and installs it, accepts the license, runs its first
launch, and adds the iOS Simulator runtime. Expect 30 to 60 minutes.

## 12. The simulator pool

```sh
./macbox pool
```

Five simulators (`MACBOX_POOL`), named `<iPhone> (macbox <kind>)`:

| Kind | What it's for |
|---|---|
| `slim-1`, `slim-2` | most work: 1x pixels (the highest frame rate) and 168 background services off |
| `full` | widgets, Live Activities, the Dynamic Island, push: every iOS service, 1x |
| `sharp` | screenshots at a real iPhone's pixels (3x) |
| `small` | small-phone layouts (the "e" iPhone, 3x) |

## 13. T3 Code (optional)

If you use [T3 Code](https://github.com/pingdotgg/t3code) on this host:

```sh
./macbox t3 register
```

It adds the VM to T3's `deviceHosts` (`~/.t3/userdata/settings.json`, backed up first). Open T3's
Device panel once: T3 installs its device hub on the Mac. Then:

```sh
./macbox t3 fix-hub
```

T3's hub ships its native parts for Apple silicon only; this rebuilds them for Intel from the
hub's own source. Run it again after T3 updates its hub. [docs/t3-code.md](t3-code.md) has details.

## 14. Agents

```sh
./macbox agents install
```

Links `mac-sim`, `sim-fps`, `android-sim` and `macbox` into `~/.local/bin`, the `simulators` (and
`phone-builds`) skill into `~/.claude/skills` and `~/.agents/skills`, and enables the timer that
shuts idle simulators down. Add [agents/simulators-snippet.md](../agents/simulators-snippet.md) to your
`~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. [docs/agents.md](agents.md) explains it.

Check it from any Expo app's checkout:

```sh
mac-sim up && mac-sim run && mac-sim shot /tmp/home.png && mac-sim down
```

## 15. Android (optional)

`android-sim` runs a pool of Android emulators on the host itself, with KVM and the GPU. It needs
the Android SDK; see [docs/agents.md](agents.md#android).

## Day to day

```sh
./macbox up | down | status
./macbox logs qemu            # or selkies, sway
./macbox ssh                  # a shell on the Mac
./macbox backup before-xcode-27   # a copy of the disk (instant on XFS/Btrfs reflinks), the VM stopped
./macbox build && ./macbox down && ./macbox up    # a newer build
```
