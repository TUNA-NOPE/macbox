# Troubleshooting

Start with `./macbox doctor` and `./macbox status`. Logs: `./macbox logs qemu` (QEMU and Reims;
with `REIMS_VGPU_STATS=1`, a line of frame statistics a second), `./macbox logs selkies`,
`./macbox logs sway`.

## Building

| Symptom | |
|---|---|
| `a patch does not apply` | `versions.env` and `patches/` belong together; a local edit to one of them breaks the other. `git status` in the checkout |
| `only N GB free` | the build needs about 25 GB in `MACBOX_HOME`. `FORCE=1 ./macbox build` tries anyway |
| QEMU's configure stops on a missing package | the image changed under it: `./macbox build` again rebuilds the image first |
| the build stops at rustup | `MACBOX_HOME/build/rustup.log`; rustup needs https://sh.rustup.rs and static.rust-lang.org |

## Starting

| Symptom | |
|---|---|
| `the image macbox:run isn't built` | `./macbox build` |
| QEMU exits at once, `vm.max_map_count` in the log | raise it (docs/setup.md, step 1). Reims needs about 64 mappings per MiB of guest RAM |
| `Could not access KVM kernel module` / permission denied on `/dev/kvm` or the render node | your user's groups (`kvm`, `render`); log in again after `usermod` |
| AMD: a warning about `/dev/udmabuf` | the same: its group, often `kvm` |
| `docker: Error ... seccomp` or passt fails | the container needs `--security-opt seccomp=unconfined`; some hardened Docker setups forbid it |
| port already in use | another service on 2226 or 6081: change `MACBOX_SSH_PORT` / `MACBOX_SCREEN_PORT` |

## The screen

| Symptom | |
|---|---|
| a black page at http://127.0.0.1:6081/ | macOS may be asleep or still booting; `./macbox screenshot /tmp/s.png` shows what QEMU sees. `./macbox logs selkies` |
| "origin not allowed" | you opened it under another address: add it to `MACBOX_STREAM_ORIGINS` (comma-separated), then `./macbox down && ./macbox up` |
| choppy over the network | Selkies lowers the bitrate to what the path carries; a relayed path (e.g. Tailscale DERP) adds its round trip. Lower the resolution, or watch locally (`./macbox view local`) |
| `view local` opens nothing | run `macbox up` from a shell inside your Wayland session (`WAYLAND_DISPLAY` set). If the compositor restarted, its socket changed: `./macbox down && ./macbox up` |
| the keyboard is stuck in the VM's window | Ctrl+Alt+Super releases it |

## Installing macOS

| Symptom | |
|---|---|
| the installer finds no disk | the disk must be on SATA during the install (`macbox create` leaves it there). Erase "QEMU HARDDISK Media" in Disk Utility first |
| a desktop with no Dock, or a gray screen with a menu bar | Metal's error mode isn't set: docs/setup.md step 6 (`macbox recovery-fix`) |
| a blank Dock icon | `rm -rf "$(getconf DARWIN_USER_CACHE_DIR)com.apple.dock.iconcache"; killall Dock` in the VM's Terminal |
| OpenCore's menu doesn't appear | `./macbox down; ./macbox boot-picker on; ./macbox up` |
| after `macbox disk nvme` macOS doesn't boot | `./macbox down; ./macbox disk ahci; ./macbox up`; in OpenCore's menu choose the disk and press Ctrl+Enter to make it the default |

## SSH

| Symptom | |
|---|---|
| `ssh macbox` times out | Remote Login is off (System Settings > General > Sharing), or macOS isn't up yet |
| `Permission denied (publickey)` | the key line didn't reach `~/.ssh/authorized_keys`: `./macbox ssh-bootstrap` again, or check that file's permissions (700 for `~/.ssh`, 600 for the file) |
| `Operation not permitted` on `~/Downloads` and the like | macOS keeps those folders private from SSH unless "Allow full disk access for remote users" is on (the (i) next to Remote Login). macbox uses `~/.macbox/downloads` instead |

## Simulators

| Symptom | |
|---|---|
| `mac-sim` says a pool simulator is "not on the Mac" | `./macbox pool` |
| every simulator shut down at once | something restarted CoreSimulatorService, which does that. Don't run `killall -9 com.apple.CoreSimulator.CoreSimulatorService` while simulators run |
| a simulator stuck in "Shutting Down" | kill its leftover render services, then the CoreSimulatorService process with `kill -9` (it ignores SIGTERM then) |
| low frame rates everywhere | another simulator animating, Simulator.app open, or a 3x simulator: `mac-sim status`, and quit Simulator.app |
| the first launch of an app after a new build is slow | shaders compile and the pipeline caches fill; later launches are fast |
| blocky noise at the wallpaper's edge or under Safari's glass bar | a known Reims rendering artefact, cosmetic |

## T3 Code's Device panel

| Symptom | |
|---|---|
| the Mac isn't listed | `./macbox t3 status`; T3 reads `deviceHosts` from its settings file. T3's server must be able to `ssh macbox` as its own user |
| the device shows, but no picture | the hub is still Apple-silicon only: `./macbox t3 fix-hub` (again after every T3 update) |
| taps do nothing, buttons work | the hub kept a stale input connection after the simulator rebooted: `ssh macbox 'pkill -f expo-device-hub'` |
| a short pause every two minutes | T3's relay reconnects idle streams; nothing to fix here |
| `DEVICE_IN_USE` | two agent-device sessions on one simulator: use `mac-sim ad`, not the command `device_open` returns |
