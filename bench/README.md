# Benchmarks

The tools behind the numbers in [docs/performance.md](../docs/performance.md), for measuring your
own GPU, or a change, before and after. They run inside macOS; build them there once:

```sh
tar -C bench -cf - . | ssh macbox 'mkdir -p ~/.macbox/bench && tar -C ~/.macbox/bench -xf -'
ssh macbox 'cd ~/.macbox/bench && ./build.sh'
```

| | |
|---|---|
| `simfps <udid> <seconds> [label]` | counts the frames a simulator's screen produces, straight from CoreSimulator's framebuffer (no encoder in the way); one JSON line with fps and frame intervals |
| `GlassBench.app` | the iOS load: a table scrolling by itself under Liquid Glass bars and a floating glass toolbar |
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
