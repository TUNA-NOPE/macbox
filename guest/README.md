# guest/: what runs inside macOS

`macbox provision` copies this folder to `~/.macbox/` in the VM. One entry point, `~/.macbox/macbox-guest` (also linked as `~/.macbox/bin/macbox-guest`, which is on PATH after `base`), sets up macOS for Xcode, the iOS Simulator and T3 Code. It runs as the VM's user, normally over SSH from the host.

Every subcommand can run again. It changes only what isn't set up yet, and prints one line per item:
- `done`: it changed that now.
- `ok`: it was already so.
- `todo`: it's left for you, with the command or the setting that does it.

```
~/.macbox/
  macbox-guest               the entry point
  bin/                       on PATH: build-serve-sim-x86.sh, sim-stream-settings.sh, setmode (compiled by `tools`)
  share/versions.env         pinned versions and SHA-256 checksums of what `tools` downloads
  share/setmode.swift        the source of `setmode`
  downloads/                 downloads, kept so reruns don't fetch again; also the place for Xcode's .xip
  src/                       build trees (expo-device-hub sources, Intel builds of serve-sim)
  config.env                 optional KEY=value settings written by the host (MACBOX_SIM_PREFIX, MACBOX_POOL, ...)
```

Settings come from the environment first, then `~/.macbox/config.env`, then `share/versions.env`.

## Order

1. **By hand, in the VM's window** (see "Steps on the Mac's screen" below):
   1. Install macOS.
   2. Set Metal's error mode.
   3. Go through Setup Assistant.
   4. Turn on SSH.
2. `macbox-guest base`: run once with a terminal (`ssh -t`), so sudo can ask for the password.
3. `macbox-guest tools`.
4. `macbox-guest stream-settings install`.
5. `macbox-guest xcode <Xcode_NN.N.xip>`, then `macbox-guest runtime`.
6. `macbox-guest pool create`.
7. Open the Mac once in T3 Code's Device panel; T3 installs its device hub. Then run `macbox-guest t3-hub`.
8. `macbox-guest doctor`.

## Subcommands

| Command | Input | What it does |
|---|---|---|
| `base [--reduce-transparency] [--autologin]` | With `--autologin`, the user's password on stdin (`printf '%s\n' "$pw" \| macbox-guest base --autologin`). Without it, a terminal for sudo's prompt the first time. | <ul><li>Passwordless sudo for the user (`/etc/sudoers.d/macbox-<user>`, checked with `visudo`).</li><li>`METAL_ERROR_MODE` 5 in `/Library/Preferences/.GlobalPreferences` (and `chmod 644`).</li><li>pmset: no sleep, display sleep, disk sleep, standby or Power Nap, and restart after a power failure (skips the keys a VM doesn't have).</li><li>Screen saver off. Screen lock off with `sysadminctl` (it asks for the password; prints how without a terminal).</li><li>Spotlight indexing off.</li><li>No automatic macOS or App Store update downloads.</li><li>`--reduce-transparency`: Accessibility's Reduce Transparency, which costs the GPU less.</li><li>A marked PATH block in `~/.zshenv` with `~/.macbox/bin`, portable Ruby, gems, Go and `/usr/local/bin`, plus `LANG`.</li><li>`--autologin`: writes `/etc/kcpassword` and `autoLoginUser` (refused while FileVault is on). The password goes through stdin, never into a command line.</li></ul> |
| `tools` | Network access to nodejs.org, github.com, go.dev and proxy.golang.org. | <ul><li>Node.js (official `.pkg`, pinned, SHA-256 checked). An existing other version is kept unless `NODE_FORCE=1`.</li><li>Homebrew's portable Ruby in `~/.local/portable-ruby/<version>` (`current` points at it).</li><li>CocoaPods with `gem install --user-install`.</li><li>Go (official `.pkg`).</li><li>simslim with `go install …@<version>`, which Go checks against its checksum database.</li><li>`setmode` compiled into `~/.macbox/bin` once Xcode is there.</li></ul> |
| `xcode <file.xip>` | A `.xip` you downloaded from Apple. | <ol><li>Checks that Apple signed it (`pkgutil --check-signature`) and that there is room to expand it.</li><li>Expands it (15–45 min) and moves it to `/Applications/Xcode.app`, keeping a different older one as `Xcode-<version>.app`.</li><li>Selects it with `xcode-select`, accepts the licence and runs the first launch (system packages).</li><li>Enables `DevToolsSecurity`, so debugging doesn't put up a password dialog.</li><li>Compiles `setmode`.</li></ol>Skips the expansion when `Xcode_<version>.xip` is already installed. |
| `xcode status` | | Version, licence and first-launch state. |
| `runtime [file.dmg]` | Optional: a runtime `.dmg`. | <ul><li>With a `.dmg`: `xcrun simctl runtime add`.</li><li>Without one: `xcodebuild -downloadPlatform iOS -exportPath ~/.macbox/downloads/runtimes -architectureVariant universal`, then `simctl runtime add` (no Apple Account needed).</li><li>Skips if an iOS runtime is already there (`RUNTIME_FORCE=1` downloads again).</li></ul> |
| `pool create [--delete-defaults]` | `MACBOX_SIM_PREFIX` (default `macbox`), `MACBOX_POOL` (default `full slim-1 slim-2 sharp small`). | The simulator pool, on the newest iOS runtime. See below. With `--delete-defaults`, it also deletes the shut-down devices CoreSimulator made by itself: those named exactly like a stock device type. |
| `pool list` | Same variables. | One line per pool simulator: UDID, state, name, device type, slim or stock. Exits 1 if one is missing. |
| `pool delete --yes [--types]` | Same variables. | Deletes the pool's simulators (without `--yes` it only lists them). `--types` also removes the `dev.macbox.*` device types. |
| `t3-hub [version]` | T3 Code's hub in `~/.t3/device/tools/` (T3 installs it). | For each installed `expo-device-hub@<version>` still on arm64:<ol><li>Downloads the matching expo/expo-device-hub source.</li><li>Builds serve-sim's native parts for x86_64 (`bin/build-serve-sim-x86.sh`) and swaps them in.</li><li>Stops the hub; T3 starts it again.</li></ol>Run it again whenever T3 updates the hub, or the Device panel's stream fails. |
| `stream-settings install\|remove\|status` | `MACBOX_STREAM_BITRATE` (default 1200000), `MACBOX_STREAM_FPS` (default 30). | Installs the LaunchAgent `dev.macbox.sim-stream-settings`. Every 20 s it sets a stream the hub has open to H.264 at that bitrate and frame rate; serve-sim's defaults are 6 Mbit/s and 60. A setting chosen in the panel stays. |
| `doctor` | | One line per item: everything above, the pool and the T3 hubs. Changes nothing. |

### The pool

| Kind | Name (prefix `macbox`) | Device type | Pixels | Services |
|---|---|---|---|---|
| `full` | `iPhone 17 Pro (macbox full)` | `dev.macbox…iPhone-17-Pro-1x` | 402x874 | stock: widgets, wallpaper, Live Activities, Dynamic Island |
| `slim-1`, `slim-2`, … | `iPhone 17 Pro (macbox slim 1)` | the same 1x type | 402x874 | simslim: about 170 background services off |
| `sharp` | `iPhone 17 Pro (macbox sharp)` | Apple's own | 1206x2622 | simslim |
| `small` | `iPhone 17e (macbox small)` | Apple's own | 1170x2532 | simslim |

- **The device models are the newest ones the runtime has.** `iPhone NN Pro` is the newest Pro. `iPhone NNe` is the newest "e" model; without one, the newest plain `iPhone NN`.
- **The 1x and 2x device types are copies of Apple's profile with a different `mainScreenScale`.**
  - The pixels and DPI follow the scale; the layout in points stays the same.
  - `createByDefaultForRuntimeVersions` and `pairByDefaultForRuntimeVersions` are removed, so CoreSimulator doesn't make devices of its own from them.
  - They live in `~/Library/Developer/CoreSimulator/Profiles/DeviceTypes/` as `iPhone 17 Pro (1x).simdevicetype`, identifier `dev.macbox.CoreSimulator.SimDeviceType.iPhone-17-Pro-1x`.
  - The 2x type is for switching a simulator's resolution; the default pool doesn't use it.
- **CoreSimulatorService reads device types when it starts.** The first `pool create` restarts it, but only while no simulator is booted, because a restart shuts down every booted simulator. With simulators running it stops and says which; `FORCE=1` overrides.
- **Slimming a simulator boots it once and shuts it down again** (`simslim on --preserve-boot-state`). Whether a simulator is slim is read from simslim's store in `/private/var/tmp/com.apple.CoreSimulator.SimDevice.<UDID>/disabled.plist`.
- **Simulators outside the pool are never touched.** `--delete-defaults` is the only exception, and deletes only shut-down devices named exactly like a stock device type.

## Steps on the Mac's screen

These need the VM's window, which `macbox` shows in the browser or on the host's desktop. An agent can do them with `macbox screenshot` / `click` / `type`.

1. **Install macOS:**
   1. The VM boots macOS Recovery.
   2. In Disk Utility, erase the VM's disk ("QEMU HARDDISK Media", or "QEMU NVMe Ctrl") as APFS.
   3. Quit Disk Utility and choose Reinstall macOS.
2. **Metal's error mode, before the first desktop.** Without it, macOS's icon service crashes on Reims vGPU and the desktop never finishes: a wallpaper with no Dock, or a grey screen. In Recovery's Terminal (Utilities > Terminal), as one line:
   ```sh
   cd /Volumes/*Data/Library/Preferences && defaults write "$PWD/.GlobalPreferences" METAL_ERROR_MODE -int 5 && chmod 644 .GlobalPreferences.plist && reboot
   ```
   Reims vGPU's README ("Set Metal's error mode in the guest") has the details, including how to reach Recovery through OpenCore's picker. `macbox-guest base` checks it later, and sets it if it's missing.
3. **Setup Assistant:**
   - Create the user that `MACBOX_GUEST_USER` names (default `dev`), as an administrator.
   - Skip signing in with an Apple Account: Xcode's download page needs one in a browser, macOS itself doesn't.
   - Leave FileVault off: automatic login needs that.
   - Skip Location Services, analytics and Screen Time.
4. **Turn on SSH and let the host in.** `macbox ssh-bootstrap` types this line into Terminal (Applications > Utilities > Terminal); the public key is the host's `~/.ssh/macbox_ed25519.pub`. You can also type it yourself:
   ```sh
   mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo 'ssh-ed25519 AAAA… macbox' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sudo launchctl enable system/com.openssh.sshd && sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist
   ```
   - `sudo` asks for the user's password once, in Terminal.
   - If Remote Login was already on, the last command answers `Bootstrap failed: 5: Input/output error`. SSH works anyway.
   - **Why not `systemsetup -setremotelogin on`:** since macOS 13 it refuses to run from Terminal ("Turning Remote Login on or off requires Full Disk Access privileges") until you give Terminal Full Disk Access in System Settings. `launchctl` starts the same `ssh.plist` service without that.
   - **If the line fails,** turn on System Settings > General > Sharing > Remote Login instead. It is the same switch.
   - **Not tested on a fresh install.** The VM this repo came from was set up this way, but the line hasn't yet run on a fresh macOS 26 install from this repo.
5. **Optional: Full Disk Access for remote users.** This is the (i) next to Remote Login, "Allow full disk access for remote users".
   - Without it, SSH sessions can't read or write `~/Downloads`, `~/Desktop` or `~/Documents`, which are macOS's private folders. So put Xcode's `.xip` in `~/.macbox/downloads/`, which SSH can always read.
   - It also lets `base --reduce-transparency` write the Accessibility setting over SSH.
   - Only the GUI can turn it on; it lives in the SIP-protected TCC database.
6. **Download Xcode.**
   1. Sign in at https://developer.apple.com/download/all/?q=Xcode with an Apple Account (a free one is enough).
   2. Download `Xcode_26.6.xip`, on any computer.
   3. Copy it into the VM: `scp Xcode_26.6.xip <ssh-host>:.macbox/downloads/`.
   4. Run `macbox-guest xcode ~/.macbox/downloads/Xcode_26.6.xip`.

   On an Intel (x86-64) Mac, which is what this VM is, the newest versions are macOS 26, Xcode 26.6 and the iOS 26.5 Simulator. Apple's macOS 27, Xcode 27 and iOS 27 simulator runtimes are for Apple silicon only.

## Learned the hard way

- **Restarting CoreSimulatorService shuts down every booted simulator.**
  - Simulators that were shutting down can stick in "Shutting Down".
  - A stuck service then ignores SIGTERM. Kill its leftover render services, then `kill -9` it.
  - `pool create` restarts it only when nothing is booted.
- **Don't open Simulator.app.**
  - It opens a window for every booted simulator and doubles the GPU's work.
  - `npx expo run:ios` opens it, so build with `xcodebuild` and install with `simctl`, as `mac-sim` does.
  - T3's Device panel reads the simulator directly.
- **Release builds for the simulator on Intel need `ONLY_ACTIVE_ARCH=YES`.** Otherwise Xcode also compiles arm64 for nothing (`ARCHS = arm64 x86_64` in Release).
- **The iOS runtime must be the universal variant.** The arm64 one has no x86_64 slices. `runtime` asks for `-architectureVariant universal`.
- **Download the runtime first, then add it.** `xcodebuild -downloadPlatform iOS` on its own installs as it downloads, and once hung at 99% after the download had finished. `runtime` downloads with `-exportPath` and adds the `.dmg` with `simctl runtime add`.
- **T3's device hub ships its native parts for Apple silicon only.** After each hub update, the Device panel's stream fails until `t3-hub` has run. `doctor` shows which hubs are still arm64.
  - The Intel build also flushes every H.264 frame: a VM has only VideoToolbox's software encoder, which held frames back 0.3–0.45 s until serve-sim gave up and fell back to MJPEG.
- **After a simulator reboots while the hub is streaming it, taps in the panel stop working** (buttons still work). Restart the hub (kill its pid from `~/.t3/device/hosts/*/hub.json`); T3 starts it again within seconds. A clean shutdown and boot, which is what `mac-sim` does, doesn't trigger it.
- **A slimmed simulator has no wallpaper, widgets or Photos.** Keep `full` stock for widgets, Live Activities and the Dynamic Island. `simslim on <udid> --except widgets,photos` is a middle ground.
- **CocoaPods' `pod` runs the first `ruby` on PATH.** Portable Ruby must come before `/usr/bin`, whose Ruby 2.6 is too old. The `~/.zshenv` block does that.

## Third-party software it installs

| What | License | From |
|---|---|---|
| [Node.js](https://nodejs.org) | MIT | nodejs.org's official installer |
| [Ruby](https://www.ruby-lang.org), as [Homebrew's portable Ruby](https://github.com/Homebrew/homebrew-portable-ruby) | Ruby License / BSD-2-Clause | GitHub release |
| [CocoaPods](https://cocoapods.org) | MIT | RubyGems |
| [Go](https://go.dev) | BSD-3-Clause | go.dev's official installer |
| [simslim](https://github.com/mobai-app/simslim), by MobAI | MIT | `go install` |
| [expo-device-hub](https://github.com/expo/expo-device-hub) and its serve-sim, by Expo; `t3-hub` rebuilds it for Intel | MIT | T3 Code installs it, `t3-hub` downloads its source from GitHub |
| Xcode and the iOS Simulator runtime | Apple's licence | You download them from Apple; nothing here redistributes them |
