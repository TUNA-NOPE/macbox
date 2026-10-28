# Agents

macbox is built so that coding agents (Claude Code, Codex, and agents inside T3 Code) can run and
check iOS apps on their own, the way a developer would on a Mac: build, open, tap, look, record,
measure.

## Install

```sh
./macbox agents install
```

| What | Where |
|---|---|
| `mac-sim`, `mac-sim-remote`, `sim-fps`, `android-sim`, `android-gpu-desktop`, `phone-build`, `macbox` | links in `~/.local/bin` |
| the `simulators` and `phone-builds` skills | links in `~/.claude/skills` and `~/.agents/skills` |
| the "Simulators" section of the instructions ([agents/simulators-snippet.md](../agents/simulators-snippet.md)) | between `<!-- macbox:simulators -->` markers in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` (each backed up as `.bak-macbox`) |
| `mac-sim-idle.timer` | a user unit, enabled: idle pool simulators shut down after 20 minutes |

Optional: a Claude Code hook that reminds the agent of the skill whenever a prompt mentions a
simulator ([agents/README.md](../agents/README.md)). `./macbox agents uninstall` removes the links
and the timer (it leaves the instructions).

## What an agent does with it

From an app's checkout (a git root):

```sh
mac-sim up              # claim a simulator from the pool and boot it
mac-sim run             # copy the checkout to the Mac, build, install, open; Metro here
mac-sim snapshot        # the screen as an accessibility tree, refs like @e12
mac-sim ad press @e12   # tap (any agent-device command)
mac-sim shot /tmp/a.png # a lossless screenshot, copied here
mac-sim record /tmp/a.mp4 10 & ...; wait; sim-fps /tmp/a.mp4   # record a flow, then measure it
mac-sim down            # give it back
```

The [simulators skill](../skills/simulators/SKILL.md) is the rulebook: which simulator for what, how
to show it to the user in T3 Code's Device panel, and the loop to run after every UI change. Run
it, screenshot it and look, record the whole flow, and check with `sim-fps` that every stretch of
motion held 60 fps with no dropped frames. Then inspect the frames. Measure motion on a 1x
simulator: on a modest GPU, 3x can't reach 60 in heavy scenes, and that's the machine, not the app.

Each checkout gets its own simulator, so several agents in parallel worktrees don't wait for each
other. With the default pool that's two slim simulators, plus `full`, `sharp` and `small`.
`mac-sim status` shows who holds what.

## Setting macbox up with an agent

An agent can do the whole setup, including the parts inside macOS's GUI. It looks at the VM's
screen with `macbox screenshot`, and clicks and types with `macbox click`, `type` and `key`.
[AGENTS.md](../AGENTS.md) at the repo's root is written for that agent.

## Android

`android-sim` is the same shape for Android emulators running on the host itself:

```sh
android-sim setup       # once: the system image (sdkmanager) and the pool's AVDs
android-sim up && android-sim run && android-sim shot /tmp/a.png && android-sim down
```

It needs the Android SDK (`ANDROID_HOME`, default `~/Android/Sdk`, with cmdline-tools), a JDK 17 for
builds, `/dev/kvm`, and agent-device. For GPU rendering, `android-gpu-desktop` runs a hidden sway
with Xwayland on the GPU for the emulators (`sims/systemd/android-gpu-desktop.service`); without it
they render in software. Settings are in the same config file:

| Setting | Default |
|---|---|
| `ANDROID_HOME`, `ANDROID_AVD_HOME`, `GRADLE_USER_HOME` | `~/Android/Sdk`, `~/.android/avd`, `~/.gradle` |
| `ANDROID_SIM_POOL` | `macbox-pixel-1 macbox-pixel-2 macbox-pixel-3` |
| `ANDROID_SIM_IMAGE`, `ANDROID_SIM_SCREEN` | see `android-sim` |
| `ANDROID_SIM_GPU` | `auto` (`host` with android-gpu-desktop, else software) |

## Phone builds

The `phone-builds` skill and `phone-build` cover builds for a real device: an `.ipa` for an iPhone,
TestFlight, an `.apk`. It uses Expo's EAS while the month's free cloud builds last, then builds
locally: Android on the host, iOS in the macOS VM. iOS device builds need a paid Apple Developer
Program membership. See [skills/phone-builds/SKILL.md](../skills/phone-builds/SKILL.md).
