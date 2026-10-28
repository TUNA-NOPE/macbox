# iOS: mac-sim

macbox runs a macOS VM on this machine (Xcode and the iOS Simulator, on the host's GPU through Reims vGPU), reachable as `ssh macbox` (the alias is `MACBOX_SSH_HOST` in `~/.config/macbox/macbox.env`). `mac-sim` gives your checkout one of its simulators, builds your app there, and drives it with `agent-device`. The verification loop is in the main [SKILL.md](../SKILL.md); this file has the details.

## Which simulator

The pool (`MACBOX_POOL`, made by `macbox-guest pool create`; the newest iPhone Pro, except `small`):

| Name | Kind | Pixels | Use it for |
|---|---|---|---|
| `slim-1`, `slim-2` | slim (default) | 1x (402x874 on an iPhone 17 Pro) | most work: the fastest to animate, light |
| `full` | full | 1x | widgets, Live Activities, the Dynamic Island, push notifications, the wallpaper and home screen |
| `sharp` | slim | 3x (a real iPhone's pixels) | detailed screenshots and design review; slower to animate |
| `small` | slim, the small iPhone ("e" model) | 3x | layouts on a small phone; also slower to animate |

- **Slim** has about 170 background iOS services off (simslim): about 0.6 GB of memory instead of about 2, and no widgets, wallpaper, Live Activities or push. **Full** runs everything.
- `mac-sim up` takes a slim one; `mac-sim up --full`, `--sharp` or `--small` asks for the others. Your checkout keeps one simulator; asking for another kind swaps it.
- **The full simulator is also the user's own** (they open it in T3 Code's Device panel). Share it politely: don't erase it or change its settings. `mac-sim down` leaves it running; like the others, it's shut down after 20 idle minutes (see Rules).
- Resolutions are fixed. Changing one means restarting CoreSimulatorService, which shuts down every simulator on the Mac, so pick the simulator instead.
- On the Mac the simulators are named `<device> (<MACBOX_SIM_PREFIX> <name>)`, e.g. `iPhone 17 Pro (macbox slim 1)`. `mac-sim` finds them by that name; `mac-sim status` lists any that are missing.

## Commands

Run them from inside the app's checkout:

```bash
mac-sim up [--full|--sharp|--small]   # claim this checkout's simulator and boot it
mac-sim run                   # build the app on the Mac (Debug), install, open it; Metro runs here
mac-sim snapshot              # accessibility tree (refs like @e12); `mac-sim snapshot -i` interactive only
mac-sim ad press @e12         # any agent-device command: press, fill, scroll, gesture, back, home, open, alert...
mac-sim shot /tmp/x.png       # lossless screenshot at the simulator's resolution, copied here
mac-sim record /tmp/a.mp4 5   # 5 s of H.264 video, copied here
mac-sim open <url>            # a link or deep link (myapp://..., https://..., exp://...)
mac-sim install <path/To.app> # install a simulator .app (a path here or on the Mac)
mac-sim udid                  # this checkout's simulator
mac-sim t3                    # hostId=... deviceId=..., for T3 Code's device_open
mac-sim mac '<command>'       # a shell command on the Mac; $UDID is your simulator
mac-sim logs                  # last build, Metro and tunnel output
mac-sim status                # every simulator: kind, up or off, who uses it
mac-sim down                  # stop Metro, free the simulator (shuts it down unless it's full)
mac-sim clean                 # delete this checkout's copy and build on the Mac (frees 1-2 GB)
```

`MAC_SIM_DEVICE=<name or UDID>` picks a pool simulator explicitly.

## Running your app

- **`mac-sim run`** copies the checkout to the Mac (without `node_modules`, `.git` and generated `ios/`/`android/`), installs dependencies there with the project's package manager, runs `expo prebuild` and `pod install` when the app config or dependencies changed, and builds with `xcodebuild` for this simulator. Uncommitted changes are included; nothing needs to be pushed.
- Metro runs here from your checkout, and the app reaches it through an SSH tunnel, so **saving a JS/TS file updates the app (Fast Refresh)**. Run `mac-sim run` again after native changes (a new native dependency, config plugins, `app.json`).
- The first build of a project takes about 2 to 15 minutes (a blank Expo app: about 2 minutes); later runs reuse the Mac's copy, `node_modules`, Pods and DerivedData.
- `MODE=go mac-sim run`: the app in Expo Go instead (the version matching the project's SDK is installed for you). Only for apps without custom native code. iOS asks "Open in Expo Go?" for the link; `mac-sim` accepts it. The first time, Expo Go shows a developer-menu card: `mac-sim ad press 'label="Continue"'`.
- `MODE=release mac-sim run`: a Release build with the JavaScript inside and no Metro, what users get.
- The app's own dependencies must be installed here too (`npm install`/`bun install`), because Metro runs here.
- In a monorepo with several Expo apps, run from inside the app's folder or set `APP_DIR`.
- A project with its own `ios/` folder in git (bare React Native) is built as it is, with `pod install` but no prebuild.
- A library that still imports React Native's old headers fails against the prebuilt React Native core (`'RCTBridge.h' file not found`). `RN_FROM_SOURCE=1 mac-sim run` builds React Native from source instead (slower). That build can crash some Swift compilers in `expo-modules-core`; then the library needs an update. Meanwhile use `MODE=go` if the app runs in Expo Go.
- Settings the app reads from a gitignored `.env` are copied too.
- The VM is an Intel Mac: everything is compiled for the x86_64 simulator only (`ONLY_ACTIVE_ARCH=YES`).
- **Never run `npx expo run:ios` on the Mac.** It opens Simulator.app, which doubles the GPU work for every simulator. `mac-sim` closes Simulator.app when it boots a simulator.

## In T3 Code: show it to the user

- Call `device_open` with the `hostId` and `deviceId` that `mac-sim t3` prints. The user then sees every tap live in the Device panel. `device_open` boots a simulator that is off; in the panel's own list an off one has a Start button.
- **Keep driving it with `mac-sim ad ...`.** Don't also use the `agent-device` command that `device_open` returns for the same simulator: two agent-device sessions on one simulator refuse each other (`DEVICE_IN_USE`). The idle shutdown also counts only `mac-sim` commands.
- The panel's stream costs CPU. Call `device_close` (without `shutdown`) when the user no longer needs to watch, and `mac-sim down` when the task is done.

## Looking closely: frame rate, quality, animations

You run on the same machine as the Mac, so the stream in T3 doesn't matter to you: you read the screen with `snapshot` and `shot`, which are exact.
- **Screenshots** are lossless PNGs at the simulator's pixels: 1x on slim and full (sharp enough to read every text and check layout), 3x on `sharp`.
- **Animations:** `mac-sim record a.mp4 5`, then `sim-fps a.mp4`, then look at single frames:
  ```bash
  mkdir -p /tmp/frames && ffmpeg -loglevel error -i /tmp/a.mp4 -fps_mode passthrough /tmp/frames/%04d.png
  ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 /tmp/a.mp4   # each frame's time
  ```
  The simulator writes a frame only when the screen changes. The Mac's GPU is shared: with several simulators animating at once each gets a share. Record on a 1x simulator when you need smooth motion and take still screenshots on `sharp`.
- `agent-device` also has `screenshot`, `record` and `perf`; pass them through `mac-sim ad`, but `mac-sim shot`/`record` copy the file here for you.

## Rules

- **Close it when the task is done: `mac-sim down`.** A claim nobody uses for 3 hours (`MAC_SIM_IDLE_HOURS`) is freed by the next `mac-sim` command, and its simulator shut down.
- **Idle simulators are shut down, the full one too.** Every 5 minutes a user timer (`mac-sim-idle.timer`) shuts down a pool simulator that was booted at least 20 minutes ago (`MAC_SIM_IDLE_MINUTES`) and, for 20 minutes, had no `mac-sim` command, no viewer (T3's Device panel while it's visible, a hub's WebRTC viewer, Simulator.app) and no app coming to the foreground. The claim stays, and so do Metro and the tunnel:
  - The next `mac-sim` command (`up`, `run`, `snapshot`, `ad`, `shot`, `open`...) boots it again and says it had been shut down. Apps that were open are closed: `mac-sim run` again. `mac-sim mac`, `udid` and `t3` don't boot it; `mac-sim up` first.
  - A build or recording in progress counts as use. Waiting more than 20 minutes between commands without anyone watching doesn't.
  - Shutdowns and their reasons are in `~/.local/state/macbox/mac-sim/idle.log`; `mac-sim status` shows `off (shut down idle at …)`. Simulators outside the pool are never touched.
- **Snapshots are the truth.** Refs (`@eN`) change with the screen; take a new snapshot before each tap.
- Don't restart CoreSimulatorService, don't run `simslim`, and don't erase or delete pool simulators: other agents and the user use them.

## When something fails

- `the Mac doesn't answer over SSH`: the VM is down. `macbox status`; `macbox up` starts it (about 2 minutes). If it won't start, tell the user.
- `not on the Mac: ...`: a pool simulator is missing. `macbox-guest pool create` on the Mac makes it (tell the user if you may not).
- `every slim simulator is in use`: wait, ask the user, or use another kind if it suits the task (`--sharp`).
- The build failed: `mac-sim logs`; the full Xcode log is on the Mac in `~/.mac-sim/src/<checkout>/<app>/.mac-sim/xcodebuild.log` (`mac-sim mac 'tail -100 …'`). Errors there are usually the app's own.
- The app shows a red "No bundle URL" or can't connect to Metro: `mac-sim run` again (it restarts Metro and the tunnel).
- `DEVICE_IN_USE` from agent-device: another session holds the simulator (often T3's `agent-device` from `device_open`). Close that one, or `mac-sim ad close` and retry.
- Taps in T3's Device panel do nothing after the simulator was rebooted outside `mac-sim`: T3's device hub keeps a stale connection. Tell the user; restarting the hub fixes it (T3 starts it again by itself).

## Files

- The command is `sims/bin/mac-sim` in the macbox checkout (linked as `~/.local/bin/mac-sim` by `macbox agents install`). `sims/bin/mac-sim-remote` is its Mac side, copied to the Mac's `~/.local/lib/mac-sim/` when it changes; it installs a pinned `agent-device` there on first use (`mac-sim setup` does it ahead of time).
- Claims, logs, the shared SSH connection, the pool's UDIDs (`pool.cache`) and each simulator's `last-used`/`last-viewed` marks are in `~/.local/state/macbox/mac-sim/`.
- Metro and its tunnel run as transient user units `macbox-sim-metro-<name>` and `macbox-sim-tunnel-<name>`, Metro on port 8101 + 2 × the simulator's place in the pool (`MAC_SIM_METRO_BASE`).
- The idle check is `mac-sim idle [--dry-run] [name...]`, run by `~/.config/systemd/user/mac-sim-idle.{timer,service}`.
- On the Mac each checkout's copy and build are in `~/.mac-sim/src/<checkout>-<hash>/`, agent-device sessions in `~/.mac-sim/mac-sim-<simulator>/`, Expo Go downloads in `~/Library/Caches/mac-sim/`.
