# Contributing to macbox

Using macbox on hardware or in a setup we haven't tested? Found a workaround, optimized a
shader path, built an integration, or have an idea to make it better? **Please share it.**
You don't need a finished patch to be helpful.

## Ideas, requests and experiments

[Open an issue](https://github.com/TUNA-NOPE/macbox/issues/new/choose) for a feature
request, question, bug, or hardware report. Ideas we especially want to hear about include:

- AMD and NVIDIA GPU compatibility and driver setup.
- Optional VFIO / GPU passthrough support (not currently built into macbox).
- Alternative VM, display, streaming, and input configurations.
- Measurable performance or reliability improvements.
- Xcode, iOS Simulator, Expo, and coding-agent workflows.

If you made a fork that works with a dedicated GPU or passthrough, tell us how. A link to a
branch, patch, or proof of concept is useful even if you haven't packaged it into a PR yet.
For larger changes, it's worth discussing the design in an issue first.

## Share hardware results

Use the [hardware report template](https://github.com/TUNA-NOPE/macbox/issues/new/choose),
including as much as you know:

- Host CPU, GPU(s), RAM, and whether the GPU is shared with Linux or passed through.
- Linux distribution, kernel, Mesa or vendor driver, Docker/Podman, and macbox version/commit.
- Guest macOS/Xcode/iOS Simulator versions, if relevant.
- What works, what fails, and how to reproduce it (commands, config changes, logs).
- If claiming a performance improvement, the before/after numbers, workload, resolution and
  measurement method.

An incomplete report is still welcome. Please remove tokens, keys, personal information,
and serial numbers from logs or screenshots before posting them.

## Pull requests

[Fork macbox](https://github.com/TUNA-NOPE/macbox/fork), make a focused change on a branch,
and [open a pull request](https://github.com/TUNA-NOPE/macbox/pulls). Please explain the
problem, how your change addresses it, and what you actually tested. If you couldn't test
on a particular GPU or host, say so: untested support shouldn't be presented as verified.

Keep the default Reims vGPU workflow working. Hardware-specific alternatives should be
optional and documented, not silently change existing installations. Small fixes, docs,
tests and experimental prototypes are all welcome, but merging depends on review and
maintainability.

macbox's own code and documentation use the
[PolyForm Noncommercial License](LICENSE). Changes to upstream components under
[`patches/`](patches/README.md) retain those components' separate licenses.
Please only submit code and assets you have permission to contribute, and do not include
Apple software or proprietary binaries in a PR.

Thanks for making macbox useful beyond its original test machine.
