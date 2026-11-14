# Performance

## Where the time goes

On every GPU measured so far, the GPU is the limit. With the build macbox makes now, one 3x iOS
Simulator reaches its screen's 120 Hz on an Arrow Lake iGPU at about 7.7 ms of GPU time per frame,
and with two or three simulators the GPU runs 80 to 93% busy at its top clock (1950 MHz) while
QEMU's CPU threads have room to spare. So the frame rate follows two things: how many pixels are
drawn (1x, 2x, 3x; the desktop's resolution), and how much work the translation adds per frame
(Metal → Vulkan).

Before macbox's patches, most of that added work was copies: macOS's framebuffer and the
simulator's display surface lie in guest RAM, and metal2vulkan copied each into a GPU image and back
around every render pass. Those shadow copies were 51% of all GPU time with the simulator and 67%
with the desktop. Patch 0004 renders those textures in place, and Coherent (patches 0009 onwards,
with QEMU's census) removes most of the copies left ([src/patches/README.md](../src/patches/README.md)).
What is left of a 3x simulator frame, measured with the pass timer on 2026-11-09:

| GPU time per 3x frame (~7.7–8.2 ms) | ms | |
|---|---|---|
| the simulator's own render passes on its screen | ~3.2 | the real rendering |
| iOS's own full-screen compute pass (a masked copy of the screen) | ~1.5 | the real rendering, near the memory bandwidth |
| copies for draws that read the pass they draw into (Liquid Glass backdrops) | ~0.76 | translation: Vulkan can't read an attachment where Metal can |
| between command buffers: barriers, pipeline drains, ~200 command buffers | ~2.4 | translation, and the open work |

Copying a frame back to guest RAM, the cost Coherent was built to remove, is down to bookkeeping: in
a 90-minute census of the desktop at 3440x1440, 0.2% of what eager copies back would have cost
(about 5 µs a frame), and 2% for the simulators' screens.

## Measurements

The reference host: Intel Core Ultra 7 265 (Arrow Lake iGPU), 128 GB DDR5 at 4400 MT/s, Mesa 26.2.4,
a NVMe disk; the VM had 8 vCPUs and 12 GB, macOS 26.7.1, iOS 26.5.

### iOS Simulator at 3x, step by step

GlassBench (a table scrolling under Liquid Glass bars and a floating glass toolbar) on an iPhone 17
Pro at 3x (1206x2622), frames per second counted at the simulator's own screen:

| Build | fps | GPU |
|---|---|---|
| Reims 2ce3209 as upstream shipped it (2026-10-26) | 17.2 | |
| macbox, 2026-10-28 (in place rendering, 0004) | 38.5 / 39.5 | 25.0 ms/frame |
| macbox cohwl, Coherent off (flat32), 2026-11-05 | 50.6 (p95 21.4 ms, p99 25.8 ms) | 97% busy |
| macbox cohwl, Coherent on, 2026-11-05 | 70.0 (p95 17.7 ms, p99 22.0 ms) | 70% busy |
| **macbox now** (Coherent and the switches below, 2026-11-10) | **120** (118.7–120.9 over runs) | 7.7 ms/frame |

The iPhone 17 Pro's screen runs at up to 120 Hz, so 120 is the most a single simulator can
show; GlassBench's own content animates at 60 Hz, and the simulator redraws on top of it. The
cohwl rows are one A/B in one window; the last row comes from the soak, A/B and lab runs of 2026-11-09
and -10 (fresh headless boots, Simulator.app closed). flat32 also has an A/B of its own against the
build before it: 41.6 → 48–50 fps.

### Several simulators at once, and the desktop under load

The build macbox makes now, 3x iPhone 17 Pro simulators all running GlassBench, the macOS desktop at
3440x1440 (2026-11-09, soak with simulators booted and shut down in cycles, 0 GPU hangs):

| Load | Each simulator, fps | GPU |
|---|---|---|
| 1 simulator | 114–121 | 7.7 ms/frame |
| 1 simulator while a window is dragged on the desktop | 99–102 | |
| 2 simulators | 51–54 each (~105 frames/s in total) | 80–85% busy, ~8 ms/frame |
| 3 simulators | 31–32 each (~95 in total) | 93% busy |

| Desktop: dragging a window (display-link ticks per second, p99 interval) | |
|---|---|
| alone | 240/s, p99 10 ms |
| with 1 simulator running | 126–128/s, p99 22–26 ms |
| with 2 simulators running | 96–102/s, p99 32–38 ms |

Two or more simulators share the GPU: about 105 simulator frames a second in total on this iGPU,
whatever their number. All guest work reaches the GPU in one order, so the desktop's frames wait
behind the simulators' earlier work; that, not the desktop's own cost, is its latency under load.
These runs placed the VM's vCPUs on the CPU's performance cores and QEMU's other threads on all
cores (`MACBOX_CPUSET` pins all of QEMU instead).

**The scheduler thread (2026-11-14).** metal2vulkan submits all the guest's GPU work from one thread.
A profile of that thread in production (a ptrace sampler that stops only that thread, unwound
offline) showed where its time goes:
- 36–50%: `vkQueueSubmit`. ANV on i915 puts every `VkDeviceMemory` of the device into every execbuf.
  QEMU holds ~7,000, nearly all of them guest buffers imported one by one. On this host that costs
  0.27 µs per object for each submit with nothing else running, 2.1 ms at 8,000 objects. 89% of it is
  kernel time.
- 18–24%: Reims's check of each submission against the detached objects. It made a list for every
  check and scanned it.

Reims 0034 and metal2vulkan 0100 make that list once per change, sorted, and ask it by binary search.
In one boot, interleaved, 6 runs of 20 s per arm, GlassBench at 3x:

| | fps | scheduler thread CPU (user/sys, % of a core) | groups held ≥ 5 ms |
|---|---|---|---|
| 1 simulator, the check as before (`detached_sorted=0`) | 114.3 ± 0.8 | 27.1 / 16.9 | 0 |
| 1 simulator, 0034 + 0100 | **118.4 ± 0.3** (+3.5%) | 22.1 / 19.3 | 2 (5.3 ms) |
| 3 simulators, as before | 95.3 ± 1.6 in total | 23.6 / 12.8 | 19 (p90 10.8 ms) |
| 3 simulators, 0034 + 0100 | **100.3 ± 2.1** (+5.3%) | 19.4 / 13.8 | 11 (p90 8.5 ms) |

Screenshots: 0 tears in 30 per arm. Coherent's gates ok, no GPU hang.

### Earlier measurements, the 2026-10-28 build

| | Reims 2ce3209 (2026-10-26) | Reims 7198fe6 | 7198fe6 + facts + colour writes | macbox, 2026-10-28 |
|---|---|---|---|---|
| 1x (402x874) | 53.5 | 57.0 | 63.7 | 95.8 / 92.5 (GPU 8.0 ms/frame) |
| 2x (804x1748) | 33.5 | 37.6 | 38.8 | 67.8 / 60.5 (14.1–14.9 ms) |
| 3x (1206x2622) | 17.2 | 19.2 | 21.9 | 38.5 / 39.5 (25.0 ms) |
| Safari at 3x, blurred floating bar | n/a | 39.5 | 44.5 | 66.4 / 64.2 |

1x and 2x haven't been measured again since.

### The macOS desktop, 2026-11-05

| 3440x1440 desktop (cohwl) | Coherent off | Coherent on |
|---|---|---|
| dragging a 600x400 window (presents per second) | 105–107 | 129–130 |
| Safari scrolling a local page (presents per second) | 75–79 | 110 |
| Genie minimize of a 2400x1100 window (frames per animation; ~12 upstream) | 19.5 (the 10-28 build) | 29.5 / 30.5 |

The first two rows are the cohwl A/B above. The Genie number with Coherent comes from a smoke
check, not a matched A/B. A 0.5 s animation at 60 Hz would be 30 frames.

### Disk

Inside macOS, emulated SATA → NVMe: a warm 4K random read 0.54 → 0.36 ms, an app's process start
250–430 → 140–250 ms. Moving the VM's disk from a ZFS SATA SSD to an XFS NVMe halved the cold read
latency again.

How they were measured:
- `simfps` (in `src/guest/bench`, if present) counts the frames a simulator's screen produces through
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
  The default `MACBOX_DISK_CACHE=none`: with `writeback`, macOS's NVMe driver panicked under heavy
  swap (an `IONVMeController` flush timeout), and `none` passed the same 11 GB test.
  `unsafe` is faster still, at the risk spelled out in the config.

## GPU tuning switches

With the macbox build (`MACBOX_GPU_TUNING=auto`, the default), `macbox up` sets:

| | |
|---|---|
| `M2V_LIVE=$MACBOX_HOME/run/live.conf` | metal2vulkan's live switches (patch 0003). The file holds `host_rt_in_place=1` |
| `M2V_ARL_FACTS=<11 facts>` | only on an Arrow Lake GPU (PCI ids 7d67, 7dd1, 7d41, 7d51, 7d45) |
| `REIMS_VGPU_PRIVATE_SKIP_PAGE_UP=1` | skips a new Private texture's first page-up (Reims patch 0013) |
| Coherent and the switches below | with `MACBOX_COHERENT=auto` (the default) on an Arrow Lake GPU |

`host_rt_in_place` is read when a texture is made: change it in `live.conf`, then remake the
surfaces (change the resolution, or restart the VM). `MACBOX_GPU_TUNING=off` turns all of it off.

On another GPU, in place rendering still runs its device check per memory kind and falls back where
the check fails; it has only been measured on Arrow Lake. Measure your own GPU before and after:
the facts list is specific to Arrow Lake and is never set elsewhere.

### Coherent and the switches measured with it (on by default on Arrow Lake)

`MACBOX_COHERENT=auto` (the default) turns this on with an Arrow Lake iGPU, the GPU it runs on day
to day; `on` turns it on with any GPU, `off` turns it off. A change applies at the next
`macbox down && macbox up`. With it, macbox sets:

| | |
|---|---|
| `REIMS_VGPU_CENSUS=$MACBOX_HOME/run/coherent`, `REIMS_VGPU_COHERENT=1` | QEMU's census traps the guest CPU's touches of the surfaces metal2vulkan keeps on the GPU (a report a minute) |
| `surface_lazy`, `surface_lazy_scoped`, `surface_coherent` | the simulator's and the desktop's surfaces stay on the GPU; a page syncs only when the guest's CPU touches it |
| `surface_lazy_max_texels=6000000`, `surface_twin_reader_first`, `surface_coherent_own_back`, `surface_lazy_open_ids`, `surface_twin_make_once` | fixes the lanes and the census found on top of it: which surfaces qualify, a race between two textures over one surface (`make_once`: 91 → 100 fps over 12 boots), and exact answers about committed command buffers |
| `inline_lazy`, `inline_checks` | a lazy surface's first pass instance is recorded inline; a batch's submission checks run in the scheduler's pass, so no chained batch waits a round for them |
| `REIMS_VGPU_GROUPED=1`, `group_batches=64`, `group_deadline_us=500`, `group_keep=0`, `group_events=0` | grouped completion: up to 64 batches complete together; keep and events off, which ended a class of fence timeouts under several simulators |
| `REIMS_VGPU_STAGED_PAGE_UP`, `REIMS_VGPU_STAGED_ZERO` | a new texture's first page-up copies guest pages into a staging buffer instead of mapping a view per page run (55k mappings a second and a storm of TLB shootdowns before: simulator 89 → 101 fps), and pages of zeros write nothing |
| `REIMS_VGPU_PIPELINE_EXEC`, `REIMS_VGPU_IRQ_MODERATE` | a FIFO's execs pipelined (8 in flight), and one interrupt outstanding at a time |
| `facts_on=SubmissionsWithoutSignalsMerge` | Arrow Lake only: submissions without signals merge |

The four `REIMS_VGPU_*` switches that name a file are on while the file exists
(`$MACBOX_HOME/run/switches/`), so each can be turned off without a restart. `live.conf` lines are
re-read every second; macbox rewrites its own lines at every start and leaves yours alone.

What to know before relying on it:
- **The crash guard.** If a coherent run crashes, `$MACBOX_HOME/run/coherent/coherent.running`
  stays behind and every later start boots without coherent pages. `macbox coherent status` says
  so; `macbox coherent reset` (VM stopped) allows the next try. A fault costs one crash, not a crash
  loop.
- **It needs** a kernel with `UFFD_USER_MODE_ONLY` (Linux 5.11 or later), which works with
  `vm.unprivileged_userfaultfd=0`. In the cohwl A/B QEMU used about 1.6 more CPU cores with it:
  the GPU waits less, the CPU traps more.
- **A rare GPU hang is still open.** Under repeated boots and shutdowns of three simulators, a
  command buffer is occasionally begun again while the GPU still runs it, and i915 resets the GPU.
  It is traced to command-buffer reuse in metal2vulkan's submission path, not to Coherent's pages,
  and is being hunted with an exact detector in Mesa.
- **Write-loss check.** The census counts `overwrite_risk`, a guest write a held GPU copy could
  overwrite. It was flagged once in an early test that killed Safari mid-frame; across 64
  production boots since 2026-11-08 (16,850 reports) it stayed at 0. On 2026-11-13 it flagged once
  more, with a Device panel stream open: the capture reads the simulator's screen with the CPU
  every frame, and a page it was reading as metal2vulkan armed it was taken for a guest write, so
  a late copy in could put the page's older bytes over a draw still running. The guest wrote
  nothing; the copy was the library's own. Patch 0094 fixes it (a refused arm is a read: synced and
  counted as `refused_reads`, never copied in), and a lane replays the case. On the first production
  boot with it (2026-11-14), streamed iPhone screens refused 11 arms, all counted as reads, and the
  write-loss gates stayed clean over 2,060 surface reports.

## Hardware video encoding (`MACBOX_VIDEO`)

Without Reims's video devices, macOS in the VM has only VideoToolbox's software H.264 encoder.
Streaming an iPhone 17 Pro simulator at its full 1206x2622 (T3 Code's Device panel) keeps
`VTEncoderXPCService` at about 610 MB and, while the screen scrolls, 75-100% of a core. With
`MACBOX_VIDEO=on` and the video kexts, VideoToolbox picks Reims's hardware encoder, which encodes on
the host's GPU through VA-API (Intel iHD on Arrow Lake: H.264 and HEVC; no AV1 encoder is exposed,
and macOS's VideoToolbox has none either). Measured on Tahoe on 2026-11-13, one boot, the same
simulator, A/B in two rounds:

| | Software encoder | Hardware encoder |
|---|---|---|
| `VTEncoderXPCService` memory | 613-620 MB | 9-18 MB |
| its CPU while scrolling | 73-75% of a core | ~0% |
| encode per frame | 82 ms (p50, scrolling) | 8-9 ms, of which ~7 on the host's GPU |
| host GPU video engine | | 4-10% |

Two things decide whether the hardware path is cheap. VideoToolbox converts anything but 4:2:0
NV12 (`420v`) with 64-byte row and plane alignment on the guest's GPU first, a Metal pass that
waits behind the simulators' own rendering (57 ms against 8 ms), so the frames given to it should
already be NV12 laid out that way. And the bitrate it reaches is close to the target; quality at
the same bitrate, measured on a recorded scroll at full size (SSIM): H.264 0.982 at 4 Mbit/s and
0.998 at 12 Mbit/s; HEVC 0.998 and 0.9996.

### Where a streamed frame's time goes

Measured on 2026-11-13 with the hardware encoder, an iPhone 17 Pro at 1206x2622:

| Stage | Time |
|---|---|
| reading the 12.7 MB framebuffer IOSurface (memcpy) | 5 ms cold, 1.4 ms warm |
| `IOSurfaceLock` before that read | 0.01 ms on a still screen; while the screen changes, until the GPU has finished the frame the simulator just announced (GlassBench ~10 ms, Safari scrolling 42-63 ms) |
| BGRA to NV12 with vImage, including that wait | 18 ms p50 (GlassBench) |
| hardware encode | 7.4 ms p50, 8.4 ms p95 |
| decode in the browser (WebCodecs) | 1.4-5 ms |

The lock's wait is not a copy back from the GPU: an idle simulator's surface locks at once while the GPU is
busy, and the wait follows the simulator's own frame rate. So the stream gets what the simulator draws: GlassBench
45-50 frames a second at `--fps 60` (439 of 456 frames new pictures), Safari's JS-driven pages about 20 (the
compositor redraws 50-70 times a second, mostly with the same pixels). Faster panels come from a faster
simulator, which is the GPU: with Coherent's surfaces off the render engine runs 86% busy with one GlassBench
simulator. Reading with `kIOSurfaceLockAvoidSync` returns stale or torn pictures, and overlapping several synced
reads gains nothing.

With Coherent's surfaces on (2026-11-14) the simulator outran the stream: GlassBench drew 87 frames a second
(p50 10.8 ms) and the stream carried 50-52. The capture's fps throttle measures each frame against the last one
it sent, so with frames 11.5 ms apart at `--fps 60` every other one fell inside the interval. Pacing on a grid
of the interval instead passes one frame per 16.7 ms slot, with a quarter interval's tolerance for jitter.
Measured through Simlock's gateway, the route T3 Code's panel streams from, with one other simulator running:

| | Throttle on the last frame | Throttle on a grid |
|---|---|---|
| GlassBench (simulator at 87 fps) | 50.5-52.0 fps, gaps p50/p95 19-20/25-27 ms | 58.6-58.8 fps, 17.4/26.2 ms |
| Safari scrolling (simulator at 64 fps) | 28.7 fps | 51.5 fps |
| tap to decoded frame, p50 (A/B, alternating, 30 taps each) | 64.9 and 64.2 ms | 60.5 and 61.4 ms |
| copy, encode, capture-to-wire (p50) | 9.5, 9.0, 9.0 ms | 9.2, 9.3, 9.6 ms |

The capture still copies every new frame before the throttle (about 90% of a core at 87 fps); copying only the
frames it sends would save most of that. The throttle is in Simlock's `SimlockCapture/Lifecycle.swift`
(`encodeLoop`), shared with serve-sim.

### Distinct app frames, not stream fps (2026-11-14)

A stream at 58-60 fps can still show fewer of the app's own frames. GlassBench draws a 16-bit counter strip
on every display-link tick (`src/bench/GlassBench`, `simfps --strip` reads it). Counting distinct counters through
T3 Code's Device Hub, one viewer, 240 Hz guest display, the grid above gave 46-53 of the app's 60 frames a second,
with p95 intervals of 29-34 ms. A per-frame trace of the capture placed the losses:

| Stage | Frames a second |
|---|---|
| the app's display link | 60 |
| the simulator's composites, alone / while captured | 115-120 / ~100 |
| composites the capture handles | ~84 (each costs a lock, 2.5-3.6 ms p50, and reading the surface) |
| distinct app frames in those copies | 54-55 |
| after the 60 fps grid | 46-49 |
| at the Device Hub's reader | the same: the Hub and the network lose none |

Every composite differs from the one before. Liquid Glass redraws the lower third of the screen on each one
while the app draws at 60, so the grid samples a 60 Hz picture through a ~100 Hz irregular source and aliases.
Two things that did not help: deduplicating whole frames, which never fires, and a 120 Hz guest display, where
the simulator composited ~70 a second in one sample (the stream then reached 54-57 distinct). Writing frames on
an even 16.7 ms grid after a fixed 30 ms delay centred the median interval but left the p95 and added latency.

What helped was choosing composites by what changed. The capture hashes the framebuffer in 16x32 tiles and copies
a composite only when the app's part of the screen changed: a tile changed that did not change on the composite
before, or half the intermittently changing tiles did. Tiles that change on every composite (the glass) are
ignored, but only while composites come faster than the app draws. With nothing scrolling, the simulator
composites at the app's 60, a small animation changes the same tiles every time, and an earlier version that
treated those as glass halved the stream. Measured through the Hub on the scheduler fix (metal2vulkan 0100),
interleaved against the grid alone:

| | Grid only | Grid and tile selection |
|---|---|---|
| scrolling (3 rounds): distinct app frames a second | 51.8-54.6 | 55.2-57.0 |
| scrolling: p95 / p99 interval | 27.5-28.6 / 39-61 ms | 24.7-26.5 / 35-44 ms |
| scrolling: repeated frames in 20 s | 95-138 | 11-17 |
| a small animation alone (2 rounds): distinct frames a second | 57.3-57.5 | 56.4-56.9 |
| the capture's CPU while scrolling, of one core | 105-134% | 82-93% |

The rest of the gap to 60 is composites that pass while the capture holds the surface: its lock (~5 ms p50) and
reading the rows it hashes, where each page the CPU touches comes back from the GPU.
It is an Atlas patch to Simlock's capture for now, not part of macbox.

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
| `surface_lazy` without trapping, or presenting every surface | a stale desktop |
| keeping paged textures' buffers (`REIMS_VGPU_PAGED_BUFFER_CACHE`) | no reuse in practice |
| grouping submissions (`submit_grouped`) | 0.2 ms a frame or less |
| a faster idle tick (`REIMS_VGPU_VBLANK_HZ` 240 vs 480) | no gain; macOS never enables the interrupt it re-raises |
| udmabuf imports, pooled staging buffers | no gain |
| a reaper for deleted textures | Safari 5–8 fps slower, and Genie breaks |
| executing the FIFO from its own thread (fifoexec) | a GPU hang on its first day; rolled back |
| merging adjacent page runs of a mapping | negligible: 49 merges in 629,632 pages of a real trace |
| chaining a submission's primary command buffers in ANV (one preamble, one end) | 13 → 2 µs per command buffer in a micro benchmark, 0–1% on a real frame: the barrier before already drains the GPU |
| precise barriers (no L3 flush between images) | within boot-to-boot noise: real frames leave little dirty |
| lossless compression (CCS) on the simulator's surfaces, in three forms | no GPU time saved; a lone simulator lost a third of its frames to host copies |
| several Vulkan queues (`ANV_QUEUE_OVERRIDE=gc=18`) | about 0% (+4% with three simulators): the GPU is already busy; one i915 context per queue (`gc=8`) was unstable |
| keeping groups of batches open (`group_keep=1`) | +6–7% with two simulators, but held groups stalled frames up to 200 ms |
| KVM halt polling off for the VM (gfx `x-halt-poll-ns=0`, QEMU 0011) | 3 simulators at 3x: +3.6% (96.0 → 99.5 fps, 0.8 fewer QEMU cores). One simulator: −3.3% (104.7 → 101.2), with more groups held 8 ms or longer. Halt polling stays on (2026-11-14) |
| a read trap waits for a write running over its surface (`surface_coherent_trap_wait=1`, 0097) | No faster: 1 simulator −0.5%, 3 simulators +1.4%. It never waited once in 6,222 census reports, and a screenshot taken with it on still tore (1 in 90). The tears come by another path. Off (2026-11-14) |
| holding a group open until its deadline (`group_keep=1 group_wake=1`, 0096) | 3 simulators at 3x: +0.4%, within noise (2026-11-14) |
| lowering a simulator's draws on a second thread | 90 → 72 fps: the first thread waits for it |
| a deeper FIFO pipeline (32 execs instead of 8) | slower: 109 → 97 fps, desktop p99 27 → 37 ms |

## Known limits

- **Animations start about 0.1 s late on an idle display.** macOS's display driver for this device
  sends no vblank while nothing is presenting, so the first frame of an animation waits a median
  114 ms for display timing (8 ms when something already animates).
  [steelbrain/reims-vgpu#141](https://github.com/steelbrain/reims-vgpu/issues/141).
- **The GPU is shared.** One 3x simulator reaches 120 Hz; two or three share about 105 frames a
  second on this iGPU, and the desktop's frames wait behind theirs.
- **x86-64 macOS ends with macOS 26.** iOS 27 simulators are arm64 only.
- **Recording** uses `simctl io recordVideo`, H.264 in software in the VM: about 50 fps with one
  simulator animating, 18 each with three. `sim-fps` counts what the simulator wrote, and it writes
  frames only when the screen changes.
