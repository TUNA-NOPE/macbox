# Performance

## Where the time goes

On every GPU measured so far, the GPU is the limit. A 3x iOS Simulator keeps an Arrow Lake iGPU
96 to 98% busy at its full clock, while QEMU's CPU threads have room to spare. So the frame rate
follows two things: how many pixels are drawn (1x, 2x, 3x; the desktop's resolution), and how much
work the translation adds per frame (Metal → Vulkan).

Before macbox's patches, most of that added work was copies: macOS's framebuffer and the
simulator's display surface lie in guest RAM, and metal2vulkan copied each into a GPU image and back
around every render pass. Those shadow copies were 51% of all GPU time with the simulator and 67%
with the desktop. Patch 0004 renders those textures in place ([patches/README.md](../patches/README.md)).

## Measurements

The reference host: Intel Core Ultra 7 265 (Arrow Lake iGPU), 128 GB DDR5 at 4400 MT/s, Mesa 26.2.4,
a NVMe disk; the VM had 8 vCPUs and 12 GB, macOS 26.7.1, iOS 26.5, one simulator booted at a time.

iOS Simulator, GlassBench (a table scrolling under Liquid Glass bars and a floating glass toolbar),
frames per second counted at the simulator's own screen, no encoding; two runs each:

| | Reims 2ce3209 (2026-10-26) | Reims 7198fe6 | 7198fe6 + facts + colour writes | **macbox build** |
|---|---|---|---|---|
| 1x (402x874) | 53.5 | 57.0 | 63.7 | **95.8 / 92.5** (GPU 8.0 ms/frame) |
| 2x (804x1748) | 33.5 | 37.6 | 38.8 | **67.8 / 60.5** (14.1–14.9 ms) |
| 3x (1206x2622) | 17.2 | 19.2 | 21.9 | **38.5 / 39.5** (25.0 ms) |
| Safari at 3x, blurred floating bar | n/a | 39.5 | 44.5 | **66.4 / 64.2** |

macOS desktop at 3440x1440, a Genie minimize of a 2400x1100 window: about 12 frames per
animation before, 19.5 with the macbox build (a 0.5 s animation at 60 Hz would be 30).

Disk, inside macOS, emulated SATA → NVMe: a warm 4K random read 0.54 → 0.36 ms, an app's process
start 250–430 → 140–250 ms. Moving the VM's disk from a ZFS SATA SSD to an XFS NVMe halved the cold
read latency again.

How they were measured:
- `simfps` (in `guest/bench`, if present) counts the frames a simulator's screen produces through
  CoreSimulator's framebuffer, with no encoder in the way.
- GPU time per frame from QEMU's DRM fdinfo.
- Warm-up pass first; nothing else animating; Simulator.app closed.

## Settings that matter

- **The simulator's scale.** 1x simulators are 4 to 9 times cheaper than 3x. The pool's slim and
  full simulators are 1x: same layout in points, a quarter of the pixels of 2x. Use `sharp` (3x)
  for screenshots, not for frame-rate checks.
- **Simulator.app stays closed.** It opens a window per booted simulator and doubles the GPU's work.
  Nothing in macbox needs it: mac-sim and T3 Code read the simulator's screen directly.
- **One simulator animating at a time,** when you measure. Booted ones that sit still cost little;
  the idle timer shuts down the ones nobody uses.
- **The desktop's resolution and refresh.** A 1920x1080 desktop costs about half of 3440x1440.
  `MACBOX_REFRESH=60` asks macOS for fewer frames than the 100 or 120 Hz a monitor may offer.
- **Reduce Transparency** in macOS (`macbox-guest base --reduce-transparency`) cuts the desktop's
  blur work. It changes nothing inside the simulator.
- **CPU pinning** (`MACBOX_CPUSET`): on a hybrid CPU, keep QEMU on the performance cores.
- **The disk:** NVMe in the VM (`macbox disk nvme`) and the VM's disk on an SSD or NVMe on the host.
  `MACBOX_DISK_CACHE=unsafe` is faster still, at the risk spelled out in the config.

## GPU tuning switches

With the macbox build (`MACBOX_GPU_TUNING=auto`, the default), `macbox up` sets:

| | |
|---|---|
| `M2V_LIVE=$MACBOX_HOME/run/live.conf` | metal2vulkan's live switches (patch 0003). The file holds `host_rt_in_place=1` |
| `M2V_ARL_FACTS=<11 facts>` | only on an Arrow Lake GPU (PCI ids 7d67, 7dd1, 7d41, 7d51, 7d45) |

`host_rt_in_place` is read when a texture is made: change it in `live.conf`, then remake the
surfaces (change the resolution, or restart the VM). `MACBOX_GPU_TUNING=off` turns all of it off.

On another GPU, in place rendering still runs its device check per memory kind and falls back where
the check fails; it has only been measured on Arrow Lake. Measure your own GPU before and after:
the facts list is specific to Arrow Lake and is never set elsewhere.

## Tried, no gain

| | Result |
|---|---|
| answering the guest as an Intel/AMD Mac's GPU (`REIMS_VGPU_NON_APPLE_GPU`) | healthy, no faster; with `fbread` the desktop breaks |
| compressed heap textures (`heap_compressed=1`) | slower |
| Mesa 26.2.6 | the same; Mesa 26.3.0-rc2 hung the GPU |
| `ANV_QUEUE_OVERRIDE=gc=6` | worse |
| native simdgroups for partial threadgroups | faster kernels, no faster frames |
| 2 MiB hugepages or transparent hugepages for guest RAM | impossible: Reims maps guest RAM in 16 KiB views |
| another vCPU model (`kvm-pv-unhalt`, no IBRS) | within noise |
| QEMU's VNC | 2 to 3 frames a second: it reads every frame back from the GPU |

## Known limits

- **Animations start about 0.1 s late on an idle display.** macOS's display driver for this device
  sends no vblank while nothing is presenting, so the first frame of an animation waits a median
  114 ms for display timing (8 ms when something already animates).
  [steelbrain/reims-vgpu#141](https://github.com/steelbrain/reims-vgpu/issues/141).
- **3x is GPU-bound** at about 35 to 40 fps on this iGPU in heavy Liquid Glass scenes.
- **x86-64 macOS ends with macOS 26.** iOS 27 simulators are arm64 only.
- **Recording** uses `simctl io recordVideo`, H.264 in software in the VM: about 50 fps with one
  simulator animating, 18 each with three. `sim-fps` counts what the simulator wrote, and it writes
  frames only when the screen changes.
