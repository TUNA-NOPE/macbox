# Verifying a screen: the checklist, frame by frame

A screen is finished when it survives this checklist in a running simulator, not when the code compiles. Budget as many loop iterations as it takes: the goal is "I can't find a flaw", not "looks fine". These principles come from the Appllama app-design skill's simulator loop, adapted to macbox's commands (`mac-sim`, `android-sim`, `sim-fps`).

## Looking at a recording

`sim-fps` gives the numbers. Your eyes give the rest, so look at the frames themselves:

```bash
sim-fps /tmp/flow.mp4                       # fps, longest gap and dropped frames per stretch of motion
mkdir -p /tmp/flow && ffmpeg -loglevel error -i /tmp/flow.mp4 -fps_mode passthrough /tmp/flow/%04d.png
ffprobe -v error -select_streams v -show_entries frame=best_effort_timestamp_time -of csv=p=0 /tmp/flow.mp4  # each frame's time
ffmpeg -loglevel error -ss 2.30 -i /tmp/flow.mp4 -frames:v 1 /tmp/at-2.30.png   # the frame at 2.30 s
ffmpeg -loglevel error -ss 2.0 -t 0.5 -i /tmp/flow.mp4 -vf "tile=6x5,scale=1800:-1" -frames:v 1 /tmp/sheet.png  # half a second as one contact sheet
```

- Watch it twice. First look at the frames in order for feel (the contact sheet is the quickest way). Then go frame by frame around every transition and every drop `sim-fps` reported.
- Simulators write a frame only when the screen changes, so a still screen makes no frames. `sim-fps` splits the recording at gaps longer than 250 ms. A gap like that inside an animation is a freeze; look at the frames on both sides to tell.
- `agent-device` can also report frame health from inside the app: `mac-sim ad perf frames --json`, `android-sim ad perf frames --json`. Use it as a second opinion when a recording looks wrong.

## Per-screen checklist

**Layout**
- [ ] Nothing is clipped by the Dynamic Island or the status bar. Scrolled content passes *under* it with the intended fade or blur, not a hard edge.
- [ ] The bottom CTA clears the home indicator (the safe-area inset is respected).
- [ ] Optical alignment: icons against text baselines. Centered things look centered; check them on a `--sharp` screenshot.
- [ ] The spacing rhythm is consistent: no rogue 13 px gaps in an 8 pt system.
- [ ] Long text: titles at twice their length truncate or wrap by design, not by accident.
- [ ] The empty, loading and error states are each verified by forcing them.

**Theming and type**
- [ ] Dark mode AND light mode screenshots taken and inspected: `mac-sim ad settings appearance dark|light`.
- [ ] At Dynamic Type XL nothing overlaps and no label is clipped.
- [ ] Contrast: secondary text is still readable in both themes.

**Motion (judged on the full-flow recording, never on stills)**
- [ ] `sim-fps` reports 60 fps and 0 dropped frames in every stretch of motion, on a 1x simulator, in a Release build.
- [ ] The entrance plays once, correctly, on first mount, and NOT again on back-navigation.
- [ ] Gestures follow the finger 1:1, the release springs with the finger's velocity, and cancelling mid-gesture settles cleanly.
- [ ] Frame by frame: no pop at the start or end of an animation, no double-render flash, and no one-frame white, wrong-theme or wrong-color frame during transitions.
- [ ] Every modal and sheet cycle is recorded (present, drag, dismiss, cancel) and is smooth in both directions.
- [ ] The keyboard is recorded appearing AND dismissing. The layout glides with it, the focused input stays visible, and nothing jump-cuts or reflows after it settles.
- [ ] With Reduce Motion on, spatial animations become cross-fades.

**Interaction**
- [ ] Every tappable is at least 44 pt, press states are visible, and there are haptics where native controls would have them.
- [ ] The keyboard has the right type and doesn't cover the focused input.
- [ ] The back gesture works everywhere it should: the iOS edge swipe and Android's back (`android-sim ad back`).
- [ ] Rapid double taps don't navigate or submit twice.

**State**
- [ ] Background the app mid-flow and come back: the state is intact.
- [ ] Kill and relaunch: persisted state is restored and ephemeral state is reset.
- [ ] Offline: actions queue or fail loudly, never silently.

## Device matrix (minimum)

| Profile | Here | Why |
|---|---|---|
| Latest iPhone Pro (Dynamic Island) | `mac-sim up` (slim, 1x) for motion; `--sharp` for pixel-exact stills; `--full` when the island, widgets or Live Activities matter | The primary design target |
| Small iPhone | `mac-sim up --small` (the "e" iPhone) | Layout compression and button reachability |
| Latest Pixel | `android-sim up` | Material behaviour, the back gesture, font metrics |

Run the full checklist on the primary target. On the others, check the layout, the safe areas and the hero flow.

If the flow is stable, script its happy path (taps, assertions, screenshots) as a small shell script of `mac-sim ad` / `android-sim ad` calls. Later changes are then re-verified for free.
