# Benchmarks

The tools behind the numbers in [docs/performance.md](../../docs/performance.md), for measuring your
own GPU, or a change, before and after. They run inside macOS; build them there once:

```sh
tar -C bench -cf - . | ssh macbox 'mkdir -p ~/.macbox/bench && tar -C ~/.macbox/bench -xf -'
ssh macbox 'cd ~/.macbox/bench && ./build.sh'
```

| | |
|---|---|
| `simfps <udid> <seconds> [label] [--strip]` | counts the frames a simulator's screen produces, straight from CoreSimulator's framebuffer (no encoder in the way); one JSON line with fps and frame intervals. `--strip` also reads GlassBench's frame counter from each new picture (its synced reads slow the 2 kHz poll, so count frames without it) |
| `GlassBench.app` | the iOS load: a table scrolling by itself under Liquid Glass bars and a floating glass toolbar. It draws a **frame strip** at the top left: a 16-bit counter that advances every display-link tick, as 18 squares of 20 pt from (21, 120) pt (white and black references, then bits 0-15), large enough to survive H.264, so any viewer can tell unique frames from repeats and count the ones lost on the way. Its own tick intervals go to `Documents/pace.json` in its container every 5 s. `-nostrip` leaves the strip out |
| `GenieBench.app` | the desktop load: a window that minimizes and restores, for counting the Genie animation's frames |
| `scroll-local.html` | a page for Safari that scrolls itself under a blurred floating bar, with no network |

A run on the iOS Simulator, from the host:

```sh
# a simulator of its own for the bench, so the pool is left alone (1x: the macbox 1x device type)
U=$(ssh macbox 'xcrun simctl create "macbox bench 1x" dev.macbox.CoreSimulator.SimDeviceType.iPhone-17-Pro-1x')
ssh macbox "xcrun simctl boot $U && xcrun simctl install $U ~/.macbox/bench/GlassBench.app && xcrun simctl launch $U dev.macbox.glassbench"
sleep 10    # warm-up
ssh macbox "~/.macbox/bench/simfps $U 15 glass-1x"
ssh macbox "xcrun simctl delete $U"
```

Measure with nothing else animating (`mac-sim status`), Simulator.app closed, two runs or more
after a warm-up. GPU time per frame on the host: QEMU's `drm-engine-render` in
`/proc/<qemu pid>/fdinfo/*` (`docker top macbox` gives the pid), divided by the frames.
