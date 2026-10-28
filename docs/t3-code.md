# T3 Code's Device panel

[T3 Code](https://github.com/pingdotgg/t3code) shows simulators and emulators in its Device panel:
live video, taps, typing, rotation, and tools agents call (`device_open`, `device_screenshot`,
`device_list`). Android emulators on the host show up by themselves. iOS needs a Mac, which T3
reaches over SSH. macbox's VM is that Mac.

## Register it

```sh
./macbox t3 register        # adds the device host (MACBOX_T3_HOST_ID, default "macbox")
./macbox t3 status
```

It adds this to `deviceHosts` in T3's settings (`MACBOX_T3_SETTINGS`, default
`~/.t3/userdata/settings.json`, copied to `settings.json.bak-macbox-<time>` first):

```json
{ "kind": "ssh", "id": "macbox", "label": "macbox (macbox)", "target": "macbox" }
```

T3 reloads the file itself. `target` is an SSH alias, resolved with the `~/.ssh/config` of the user
T3's server runs as. `macbox init` wrote that alias for the user who ran it. If T3 runs as another
user, give that user the same `Host macbox` block and key.

## The device hub, for Intel

The first time the panel opens the host, T3 installs its device hub (`expo-device-hub`, which
includes `serve-sim`) into `~/.t3/device/tools/expo-device-hub@<version>/` on the Mac, and runs it
there over SSH. The hub's native parts are built for Apple silicon only, so on this Mac the stream
fails until they are rebuilt:

```sh
./macbox t3 fix-hub           # every installed hub version still on arm64
./macbox t3 fix-hub 0.19.0    # one version
```

It downloads the hub's source at the same version, builds each native part for x86-64 with Xcode,
swaps them in, and stops the old hub (T3 starts it again within seconds). Three changes from the
upstream build make it work in the VM:

1. Every `build.sh` builds x86_64 instead of arm64.
2. Local jump thunks for CoreDeviceShim's async function pointers, which x86-64 Mach-O can't express
   the way arm64 does.
3. A flush after each frame in `H264Encoder.swift` (`VTCompressionSessionCompleteFrames`). The VM's
   only H.264 encoder is VideoToolbox's software one, which held frames back 0.3 to 0.45 s, so the
   panel timed out on them and fell back to MJPEG.

**Run it again after T3 updates its hub.** `macbox next` doesn't notice an update; the symptom is a
panel that shows the device but no picture.

## The stream

The panel plays H.264 (WebCodecs) and falls back to MJPEG only if decoding fails. Its defaults are
6 Mbit/s at 60 fps, more than the VM's software encoder keeps up with. The LaunchAgent
`dev.macbox.sim-stream-settings` (`macbox provision` installs it) sets each new session to
1.2 Mbit/s and 30 fps, unless someone already changed it in the panel. Measured on a page
scrolling at 60 fps: 24 frames/s at the defaults, 28 at these settings, with half the data.

From a tap to the first new frame on the stream: a median of 66 ms inside the Mac.

## Agents and the panel

- `mac-sim t3` prints `hostId=macbox deviceId=<udid>` for `device_open`, so the user watches
  the agent's simulator live.
- On iOS, agents keep driving with `mac-sim ad ...`. The `agent-device` command `device_open`
  returns would start a second agent-device session on the same simulator, and the two refuse each
  other (`DEVICE_IN_USE`).
- `device_screenshot` is fine for a glance; `mac-sim shot` gives lossless pixels.
- A simulator that is shut down shows "Stopped" in the panel with a Start button; `device_open` boots
  it too.

## Known behaviour

- T3's relay ends a panel stream about every 125 s while nobody touches the screen, and the panel
  reconnects: a short pause every two minutes. That's T3's side.
- After a simulator reboots while the hub streams it, taps stop reaching it until the hub restarts
  (the hub keeps the input connection of the earlier boot). `mac-sim` shuts down and boots cleanly,
  which keeps taps working. If taps die anyway: `ssh macbox 'pkill -f expo-device-hub'`; T3 starts
  it again.
- Restarting CoreSimulatorService shuts down every booted simulator. Don't.
