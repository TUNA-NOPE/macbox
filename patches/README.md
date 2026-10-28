# Patches

`macbox build` applies these on top of the commits [versions.env](../versions.env) pins
(`container/build-reims.sh`). `macbox build --upstream` applies none of them.

All of them were built, tested with metal2vulkan's GPU lanes and Reims's screenshots, and run day to
day on an Intel Arrow Lake iGPU (Core Ultra 7 265, Mesa 26.2.4 ANV). They are not upstream.

## metal2vulkan (on `development` at 0db5825a)

| Patch | What it does |
|---|---|
| 0001 env-gated Arrow Lake-S facts | `M2V_ARL_FACTS=<list>` makes this GPU a measured identity: metal2vulkan then uses the faster paths its tables allow for each named driver fact. The list `macbox` sets (only on an Arrow Lake GPU) was checked fact by fact with metal2vulkan's GPU lanes: no lane fails with it that doesn't fail without it. Unset, nothing changes. |
| 0002 the release's pixel format table without a device | an accessor the Reims port needed |
| 0003 live switches (`M2V_LIVE`) | `name=value` lines in a file, re-read at most once a second, override driver facts (`facts_off=`, `facts_on=`) and a few runtime choices without a restart. For A/B measurements in one boot. |
| 0004 `host_rt_in_place` | **the big one.** A texture that lies over guest-RAM pages (the macOS desktop's framebuffer, the iOS Simulator's display surface) is rendered straight into those pages as a linear image, after a device check per memory kind, instead of being copied into a GPU image and back around every render pass. Those copies were 51% (simulator) and 67% (desktop) of all GPU time. Live switch `host_rt_in_place=1` (macbox writes it into `$MACBOX_HOME/run/live.conf`). |
| 0005 ordering two imports of the same pages | a full memory barrier between two imports of the same guest pages, and a remapped memory whose imports follow their address keeps them: fixes a stale read 0004 exposed |

Measured on the simulator at 3x: 22.5 → 39 fps, GPU time per frame 44.4 → 24.9 ms; the desktop's
Genie animation 12 → 19.5 frames. Lanes with 0004 on: 301 of 323 match Metal; of the 22 others, 17
are ANV rounding a clear of a linear image by one code (0.1 → 0x19 where an optimal image gives
0x1a), 2 assert the old shadow copies, 3 fail the same way without the patch.

## Reims vGPU (on 7198fe6)

| Patch | What it does |
|---|---|
| 0001, 0002 `REIMS_VGPU_NON_APPLE_GPU` | an experiment, off unless set: the guest sees an Intel/AMD Mac's GPU instead of an Apple GPU family (parts: `families,tile,imageblocks,rog,xr10`). No speed gain was measured, so macbox never sets it. **Never include `fbread`:** WindowServer's command buffers then fail and macOS resets the GPU. |
| 0003 port to metal2vulkan development 0db5825a | Reims's Vulkan platform on metal2vulkan's newer runtime (72 commits after the one 7198fe6 names): 3x 20.3–21.8 → 22.5–23.0 fps before 0004. Upstream made the same move later (Reims c8ec271a). |
| 0004 upstream f6b7e927, video acceleration off | upstream's own commit, cherry-picked: `reims-ctl set --video-acceleration=false` leaves out the VideoToolbox and M2 scaler devices. macbox sets it, so the VM's devices are the ones it was measured with. |

## QEMU

`vendor/qemu` at bd95509 (github.com/steelbrain/qemu-reims-vgpu), the commit these builds used.

## Licenses

Reims vGPU and metal2vulkan are `GPL-2.0-or-later OR LGPL-3.0-or-later`; these patches are offered
under the same terms. QEMU is GPL-2.0.

## Sending them upstream

0004 and 0005 of metal2vulkan are the ones worth offering, together with 0003, which they use for
their switch. 0001 would need the facts moved into metal2vulkan's own tables for Arrow Lake.
