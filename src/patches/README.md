# Patches

`macbox build` applies these on top of the commits [src/versions.env](../versions.env) pins
(`src/container/build-reims.sh`). `macbox build --upstream` applies none of them.

Together they are the build that has run day to day since 2026-11-09 on an Intel Arrow Lake iGPU
(Core Ultra 7 265, Mesa 26.2.4 ANV), "production I". Each series rebuilds that build's sources
exactly: metal2vulkan 7fee47f5, QEMU 3999026c68, and Reims 8dea1e59 without its local build wiring
(the path of the metal2vulkan checkout, the `vendor/qemu` pointer) and without core dumps that had
been committed by accident. Patches up to metal2vulkan 0034, Reims 0025 and QEMU 0009 are the
earlier "cohwl" build (2026-11-05). None of it is upstream yet.

Most of the new code sits behind a switch and does nothing until it is set. What macbox turns on
is in [docs/performance.md](../../docs/performance.md#gpu-tuning-switches).

## metal2vulkan (on `development` at 0db5825a), 100 patches

| Patches | What they do |
|---|---|
| 0001 env-gated Arrow Lake-S facts | `M2V_ARL_FACTS=<list>` makes this GPU a measured identity: metal2vulkan then uses the faster paths its tables allow for each named driver fact. The list `macbox` sets (only on an Arrow Lake GPU) was checked fact by fact with metal2vulkan's GPU lanes: no lane fails with it that doesn't fail without it. Unset, nothing changes. |
| 0002 the release's pixel format table without a device | an accessor the Reims port needed |
| 0003 live switches (`M2V_LIVE`) | `name=value` lines in a file, re-read at most once a second, override driver facts (`facts_off=`, `facts_on=`) and a few runtime choices without a restart. For A/B measurements in one boot. |
| 0004 `host_rt_in_place` | a texture that lies over guest-RAM pages (the macOS desktop's framebuffer, the iOS Simulator's display surface) is rendered straight into those pages as a linear image, after a device check per memory kind, instead of being copied into a GPU image and back around every render pass. Those copies were 51% (simulator) and 67% (desktop) of all GPU time. Live switch `host_rt_in_place=1`. |
| 0005 ordering two imports of the same pages | a full memory barrier between two imports of the same guest pages, and a remapped memory whose imports follow their address keeps them: fixes a stale read 0004 exposed |
| 0006, 0007 pass timer | a diagnostic, off unless `M2V_PASS_TIMES` is set: GPU time per render pass and an image census |
| 0008 `tile_stored_only`, `tile_narrow_barriers` | live switches for two tile-memory experiments; off |
| 0009–0012 `surface_lazy` | a large surface's optimal image is kept beside its pages, and its bytes are brought up to date only when something reads them, instead of after every pass |
| 0013–0024, 0027–0034 Coherent (`surface_coherent`) | trap-coherent surfaces: QEMU write-protects or poisons a surface's guest pages (src/patches/qemu), so the GPU's image can stay ahead of the pages and the guest CPU's first touch of a page syncs exactly that page. This removes the remaining copies between guest RAM and the GPU. The later patches fix ordering cases the lanes found: copies back and in around held batches, writes that reach a held batch past later command buffers, and counters for each fallback. |
| 0025, 0026 flat32 | a flat dispatch whose grid fits counts in 32 bits (64 bits past 2^32 threads). The simulator's 1206x2622 masked-blit kernel went from 4.85 to 1.13 ms. Always on. |
| 0035–0039, 0041, 0049 grouped completion | batches complete in groups (live `group_batches`, up to 64; `group_deadline_us`), a held group goes when a host waits on a shared event or Coherent waits to settle, and `group_keep=0` / `group_events=0` port a fix that ended fence timeouts under several simulators. On with Coherent |
| 0040 flat variant | the flat dispatch stays SIMD16 and counts a 1-D workgroup from its id. Always on |
| 0042–0044 render lowering lanes | lowering render calls on a worker thread and on lanes per queue; off unless Reims sets `REIMS_VGPU_RENDER_LOWERING=worker`, which it refuses while the census runs |
| 0045, 0046 recycled images | host-copied textures' images that the host writes too are recycled |
| 0050, 0051, 0058–0061, 0069, 0070, 0093 surface fixes | `surface_lazy_max_texels`, `surface_twin_reader_first`, `surface_usage_shadow_image`, `surface_coherent_own_back`, `surface_lazy_open_ids`, `surface_twin_make_once` (a race between two textures over one surface: 91 → 100 fps over 12 boots). 0093: a command buffer dropped without a commit takes the standings its encoders left with it, so `surface_lazy_open_ids` never reads them as committed. All but `surface_usage_shadow_image` on with Coherent |
| 0094 a refused arm is a read | QEMU's census keeps held pages read-only (QEMU 0007), so a page it refuses to arm was being read and holds no write. metal2vulkan took it as the guest's, from before that change, and the next held batch copied its older bytes in over a draw still running (`overwrite_risk`, the write-loss gate). It is now only synced and counted (`refused_reads`). Found when a Device panel capture, reading the simulator's screen every frame, tripped the gate in production on 2026-11-13 |
| 0095 an attachment the device makes no image of | A color attachment without RenderTarget usage renders through a stand-in in its own Vulkan format; ANV renders no compressed format (BC, ETC2, EAC, ASTC, PVRTC carriers) and no RGB9E5, so the image query failed, was read as limits of 0, and the pass was refused ("MaxImageDimension2D available 0"), which Reims aborts on: QEMU died this way in production on 2026-11-14, after a 1024x1024 ASTC texture. Formats the device renders through an integer word (RGB9E5, R8/RG8 sRGB, packed 16-bit) now get a stand-in in that word's format. A compressed color attachment gets no encoder (nil, which Reims skips) and an `m2v-compressed-attachment:` line naming the pass; the nil comes after every color's own checks and then the command buffer's state (an open encoder or a commit still refuse it, as any pass), and before any image is made; the pass's other attachments are then neither drawn nor stored. An unsupported combination is refused `Format` naming the Metal pixel format, as Reims reads it, not a size, and an `m2v-unmade-image:` line gives the whole combination. An all-format sweep on ANV: 171 such refusals before, 0 after |
| 0096–0099 held groups and read traps | All off. 0096 `group_wake=1`: with `group_keep=1`, the scheduler's sleep ends at a kept group's deadline, not at the next completion. 0097 `surface_coherent_trap_wait=1`: a CPU read that traps on a Coherent surface waits until no running GPU write covers that surface, then syncs. Without it, a read can take finished frames' pages beside a frame still being drawn, and tear at a page boundary. A unit test shows both: frames [1,2] without it, [2,2] with it. In production it never waited once in 6,222 census reports, and screenshots still tore with it (1 in 90), so it stays off ([performance.md](../../docs/performance.md#tried-no-gain)). 0098 and 0099 (diagnostics): `group_hold_log_us=N` writes one `m2v long-hold:` line for each group held N µs or more. The line gives the scheduler's passes and wakings meanwhile, and the holding pass's CPU time, run-queue wait, sleeps, preemptions, and its wait for the `VkQueue` lock and use under it |
| 0100 `uses_sorted` | `Submission::uses_sorted` and `CommandBuffer::uses_sorted`: a submission's check against a sorted list of objects, done by binary search instead of a scan for each resource. Reims 0034 uses it. |
| 0085 `inline_lazy`, 0092 `inline_checks` | a lazy surface's first pass instance recorded inline; a batch's submission checks run in the scheduler's pass. On with Coherent |
| 0062, 0068, 0076, 0077, 0080, 0081, 0083, 0084, 0086, 0090 experiments | `xr_unused_bits_off`, `surface_coherent_writer_wins`, `M2V_FLAT_TILE`, `shared_ccs`, `host_mutable`, `batch_end_light`, `view_render_direct`, `precise_barriers`, `checks_first`: live switches, all off. Most are in [docs/performance.md](../../docs/performance.md#tried-no-gain) |
| 0047, 0048, 0052–0057, 0063–0067, 0071–0075, 0078, 0079, 0082, 0086–0089, 0091 diagnostics | the pass timer's units and censuses, logs of views, twins, barriers and the scheduler, counters of why shadows copy back, and `M2V_PENDING_AUDIT` (command buffers begun while their submission is pending). Off unless their variable is set |

## Reims vGPU (on 7198fe6), 35 patches

| Patches | What they do |
|---|---|
| 0001, 0002 `REIMS_VGPU_NON_APPLE_GPU` | an experiment, off unless set: the guest sees an Intel/AMD Mac's GPU instead of an Apple GPU family. No speed gain was measured, so macbox never sets it. **Never include `fbread`:** WindowServer's command buffers then fail and macOS resets the GPU. |
| 0003 port to metal2vulkan development 0db5825a | Reims's Vulkan platform on metal2vulkan's newer runtime. Upstream made the same move later (Reims c8ec271a). |
| 0004, 0005 `REIMS_VGPU_VBLANK`, `REIMS_VGPU_VBLANK_HZ` | re-raise an idle display's present interrupt once a refresh period; off. macOS turned out never to enable that interrupt bit, so macbox doesn't set it. |
| 0006–0008, 0016, 0018, 0020, 0021, 0024 census | the touch census: how often the guest CPU touches large IOSurfaces, its report script, boot-test guests and a content check. Off unless `REIMS_VGPU_CENSUS` names a directory. |
| 0009 the presented texture | tells metal2vulkan which texture the display presents (for `surface_lazy`) |
| 0010 tick experiments | logs the guest's enabled interrupt bits |
| 0011, 0014, 0019, 0022, 0023 Coherent hooks | the library's side of trap-coherent surfaces: tracks, syncs and host reads and writes, between metal2vulkan and QEMU's census |
| 0012 `REIMS_VGPU_PAGED_BUFFER_CACHE` | keeps paged textures' buffers; off (no reuse was measured) |
| 0013 `REIMS_VGPU_PRIVATE_SKIP_PAGE_UP` | skips a new Private texture's first page-up, which nothing can read; macbox sets it |
| 0015, 0017 NVMe boot tests | coherent pages through NVMe DMA, in the census's boot tests |
| 0025 upstream f6b7e927, video acceleration off | upstream's own commit, cherry-picked: `reims-ctl set --video-acceleration=false` leaves out the VideoToolbox and M2 scaler devices. macbox sets it, so the VM's devices are the ones it was measured with. |
| 0026 `REIMS_VGPU_PIPELINE_EXEC` | a FIFO's execs pipelined, up to 8 in flight; on with Coherent while the named file exists |
| 0027 `REIMS_VGPU_GROUPED=1` | grouped completion (metal2vulkan 0035 onwards); on with Coherent |
| 0028 `REIMS_VGPU_IRQ_MODERATE` | one interrupt raise outstanding at a time, a held one goes after 2 ms; on with Coherent while the named file exists |
| 0029 render lowering and multi-queue tests | `REIMS_VGPU_RENDER_LOWERING` (off) and regression tests for several queues |
| 0030 `REIMS_VGPU_PAGED_BUFFER_BY_PAGES` | finds kept paged buffers by their guest pages; off |
| 0031–0033 staged page-ups | `REIMS_VGPU_STAGED_PAGE_UP`, `REIMS_VGPU_STAGED_ZERO`: a new texture's first page-up copies its pages into a staging buffer (one copy per run) when no live view covers them, and pages of zeros write nothing. Before, each page run took its own mapping: 55k a second and a storm of TLB shootdowns; the simulator went from 89 to 101 fps. On with Coherent |
| 0034, 0035 the detach check | Every submission is checked, on metal2vulkan's scheduler thread, against the objects detached now. That list is now made once per change (a detach, an attach or a release), sorted, and asked by binary search (metal2vulkan 0100). Before, it was made again for every check and scanned: 18–24% of that thread's time. On by default. Live `detached_sorted=0` brings back the check as before, for an A/B in one boot. Measured: 1 simulator +3.5%, 3 simulators +5.3% ([performance.md](../../docs/performance.md#several-simulators-at-once-and-the-desktop-under-load)). |

## QEMU (`vendor/qemu` at bd95509, github.com/steelbrain/qemu-reims-vgpu), 14 patches

| Patches | What they do |
|---|---|
| 0001–0003, 0006–0009 the census | memslots move to a second mapping of guest RAM that only KVM uses, and userfaultfd markers there report the guest CPU's touches of tracked pages (`UFFD_USER_MODE_ONLY`: no capability or `/dev/userfaultfd` needed). QEMU's own loads, stores and DMA reach it too. Off unless `REIMS_VGPU_CENSUS` is set. |
| 0004, 0005 coherent pages | with `REIMS_VGPU_COHERENT=1` the same markers serve metal2vulkan's trap-coherent surfaces. A run that doesn't end well leaves `coherent.running` in the census directory, and every later start boots without coherent pages until it's removed (`macbox coherent reset`), so a fault there costs one crash, not a crash loop. |
| 0010–0013 KVM shortcuts for the GPU device | `x-irqfd` (interrupts through a KVM irqfd), `x-halt-poll-ns`, `x-ioeventfd` (doorbells through KVM ioeventfds): device properties, all off unless set |
| 0014 the video devices | upstream's own 4895365e5b (on `steelbrain/reims-vgpu`, after bd95509), unchanged: `apple-videotoolbox-pci` (106b:1a03) and `apple-m2scaler-pci` (106b:1a0b), the transports of Reims's VideoToolbox and scaler devices. Without it the build can't attach them. Drop it when `QEMU_REF` moves past 4895365e5b. The devices stay detached unless `MACBOX_VIDEO=on` |

## Licenses

Reims vGPU and metal2vulkan are `GPL-2.0-or-later OR LGPL-3.0-or-later`; these patches are offered
under the same terms. QEMU and its patches are GPL-2.0-or-later.

## Sending them upstream

Upstream's `development` branches have moved on since these bases (submission, sync and memory
tracking in metal2vulkan; a graphics device of Reims's own). The series are being rebased onto
them before anything is offered. flat32 (0025, 0026) is the first candidate: it applies to current
metal2vulkan and needs only a semantics version bump.
