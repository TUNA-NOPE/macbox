# Android: android-sim

`android-sim` is macbox's optional Android part: a pool of Android emulators (`ANDROID_SIM_POOL`, by default `macbox-pixel-1`, `-2` and `-3`; 720x1600 at 280 dpi, the same layout width as a Pixel 9) running headless on this machine. With sway and Xwayland installed they render on the GPU through a hidden GPU desktop (`android-gpu-desktop.service`, display `:20`), which takes about 5 times less CPU than software rendering while the screen moves. `android-sim` gives your checkout one of them, builds your app locally, installs it and connects `agent-device` so you can read and drive the screen. The verification loop is in the main [SKILL.md](../SKILL.md); this file has the details.

## What it needs

- The Android SDK with its command-line tools (`ANDROID_HOME`, default `~/Android/Sdk`), a JDK 17 for builds, and read-write `/dev/kvm`.
- `agent-device` on PATH (`npm install -g agent-device`).
- Optional, for the GPU: `sway` and `Xwayland`, and read-write access to the render node (`MACBOX_RENDER_NODE`, default `/dev/dri/renderD128`). `ANDROID_SIM_GPU=auto` (default) falls back to software rendering without them; `host` insists on the GPU; `software` never tries it.
- `android-sim setup` installs the system image (`ANDROID_SIM_IMAGE`) and creates the pool's emulators once. If `sdkmanager` asks about licenses, the user accepts them in a terminal (`sdkmanager --licenses`).

## Commands

Run them from inside the app's checkout:

```bash
android-sim run               # start this checkout's emulator, build the app (debug), install and open it, keep Metro running
MODE=release android-sim run  # a Release build: the JavaScript inside, no Metro (measure 60 fps on this)
android-sim snapshot          # accessibility tree, text included (refs like @e12); `android-sim ad snapshot -i` for tappable elements only
android-sim ad press @e12     # any agent-device command: press, fill, gesture, back, open, logs...
android-sim shot /tmp/x.png   # screenshot
android-sim record /tmp/a.mp4 5   # 5 s of video (at most 180), copied here; measure it with sim-fps
android-sim serial            # this checkout's emulator, e.g. emulator-5572
android-sim logs              # this checkout's last build, Metro and emulator output
android-sim status            # every emulator: up or off, who uses it, app, Metro
android-sim down              # stop this checkout's Metro and emulator
```

`android-sim up` only starts the emulator. `eval "$(android-sim env)"` sets the Android SDK variables for your own Gradle or Expo commands.

## One emulator per checkout

- Each checkout (its git root) gets its own emulator from the pool and keeps it until `android-sim down`. Agents in different checkouts or worktrees work in parallel; nobody waits.
- Two agents in the same checkout share its emulator and Metro.
- Each emulator has its own Metro port (8081, 8083, 8085). The app on the device still reaches Metro at `localhost:8081`; `android-sim` forwards that to the right port.
- If all of them are in use, `android-sim` says so. Wait, or ask the user.
- `ANDROID_SIM_DEVICE=<avd or emulator-NNNN>` picks one explicitly.

## In T3 Code: show it to the user

The user watches emulators in T3 Code's Device panel. After `android-sim up` or `run`, open it there:

- Call `device_open` with `hostId: "local"` and the serial `android-sim` printed as `deviceId` (`android-sim serial` prints it again). The user then sees every tap and screen change live.
- Keep driving it with `android-sim ad ...`, or with the `agent-device` command `device_open` returns. Both work on the same device.
- The live stream costs CPU. When you no longer need the user to watch, call `device_close` (without `shutdown`), and `android-sim down` when the task is done.
- An emulator the user opened from the panel themselves (`status` shows it up with no user) is theirs. `android-sim` never takes it on its own, and `down --all` leaves it running. Use it only when the user asks, with `ANDROID_SIM_DEVICE`.

## Running your app

- `android-sim run` builds the files as they are now, including uncommitted changes; nothing needs to be pushed.
- Metro runs from your checkout, so after the app is open, saving a JS/TS file updates it through Fast Refresh. Run `android-sim run` again after native changes (a new native dependency, config plugins, `app.json` changes).
- The first build of a project downloads Gradle and its dependencies and takes 5 to 15 minutes; later builds are incremental.
- The app config needs `android.package` (for example `"android": { "package": "com.example.app" }`), which `expo prebuild` requires.
- The build generates an `android/` folder in the app. If the project doesn't ignore it, `android-sim` adds it to `.git/info/exclude` (local only). Don't commit it.
- In a monorepo with several Expo apps, run from inside the app's folder or set `APP_DIR`.
- Expo Go: install the version that matches the project's SDK (the APK URL is in `https://api.expo.dev/v2/versions/latest`, `sdkVersions.<N>.0.0.androidClientUrl`) with `adb -s <serial> install -r <apk>`.

## Rules

- **Close it when the task is done: `android-sim down`.** It's free, but each emulator uses about 3 to 4 GB of memory and some CPU, which other agents and services share. A forgotten emulator stops by itself after 6 hours (`MAX_HOURS`).
- **Snapshots are the truth.** Refs (`@eN`) change whenever the screen changes, so take a new snapshot before each tap. `agent-device help workflow` lists all commands; pass them through `android-sim ad`.

## When something fails

- `no access to /dev/kvm`: the emulator can't use hardware virtualization. Tell the user (this user needs to be in the `kvm` group, or the device opened to it).
- `the emulator '...' doesn't exist`: `android-sim setup` creates the pool.
- The build failed: `android-sim logs`. Errors there are the app's own (a missing `android.package`, a native dependency that needs setup).
- The app shows "Unable to load script" or a red error about Metro: run `android-sim run` again; it restarts Metro and reconnects the emulator to it.
- agent-device says there's no session: `android-sim ad open <package>`.
- "rendering in software": the GPU desktop isn't running or the render node isn't usable. `systemctl --user restart android-gpu-desktop`; check `systemctl --user status android-gpu-desktop` and that the render node is `rw` for this user; tell the user if not.

## Files

- The commands are `sims/bin/android-sim` and `sims/bin/android-gpu-desktop` in the macbox checkout (linked into `~/.local/bin` by `macbox agents install`), with the unit `android-gpu-desktop.service`.
- The SDK is in `ANDROID_HOME`, Gradle's cache in `GRADLE_USER_HOME` (default `~/.gradle`), the emulators in `ANDROID_AVD_HOME` (default `~/.android/avd`; elsewhere, `setup` leaves pointer files in `~/.android/avd/` so T3 Code finds them).
- Logs and state are in `~/.local/state/android-sim/<avd>/`, claims in `~/.local/state/android-sim/claims/`. Each emulator runs as the transient user unit `android-sim-emulator-<avd>` on its own port (5570, 5572, ...), away from the ports T3 Code takes from 5554 up.
