# Credits

macbox builds on these projects. It ships none of their binaries: `macbox build` fetches and
builds the sources, the image installs packages from Ubuntu, and the guest tools download from their
publishers. Thank you to everyone who made them.

## The GPU and the VM

| Project | What macbox uses it for | License |
|---|---|---|
| [Reims vGPU](https://github.com/steelbrain/reims-vgpu), by Anees Iqbal | Apple's paravirtual GPU for QEMU: macOS draws with Metal on the host's GPU. Also `reims-ctl`, which creates and runs the VM | GPL-2.0-or-later OR LGPL-3.0-or-later |
| [metal2vulkan](https://github.com/steelbrain/metal2vulkan), by Anees Iqbal | runs the guest's Metal work on Vulkan; macbox's patches are on it | GPL-2.0-or-later OR LGPL-3.0-or-later |
| [reims-util](https://github.com/steelbrain/reims-util), by Anees Iqbal | makes the VM's OpenCore image and downloads macOS's installer from Apple | GPL-2.0-or-later OR LGPL-3.0-or-later |
| [qemu-reims-vgpu](https://github.com/steelbrain/qemu-reims-vgpu) / [QEMU](https://www.qemu.org/) | the virtual machine | GPL-2.0 |
| [OpenCore](https://github.com/acidanthera/OpenCorePkg), by Acidanthera | boots macOS in the VM (inside the image reims-util makes) | BSD-3-Clause |
| [EDK II / OVMF](https://github.com/tianocore/edk2) | the VM's UEFI firmware | BSD-2-Clause-Patent |
| [Mesa](https://www.mesa3d.org/) (ANV, RADV) | the Vulkan drivers metal2vulkan runs on | MIT |
| [SDL3](https://github.com/libsdl-org/SDL) | the VM's window (built into Reims) | Zlib |
| [passt](https://passt.top/) | the VM's network inside the container | GPL-2.0-or-later |
| [Ubuntu](https://ubuntu.com/) | the container's base image | various |

## The screen

| Project | | License |
|---|---|---|
| [sway](https://github.com/swaywm/sway) and [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) | the private headless desktop the VM's window opens in | MIT |
| [Selkies](https://github.com/selkies-project/selkies) and [pixelflux](https://github.com/selkies-project/pixelflux) | the browser stream: capture, GPU encoding, congestion control | MPL-2.0 |
| [wayvnc](https://github.com/any1/wayvnc) and [neatvnc](https://github.com/any1/neatvnc) | VNC of the headless desktop (the noVNC fallback, measurements) | ISC |
| [noVNC](https://github.com/novnc/noVNC) and [websockify](https://github.com/novnc/websockify) | the fallback browser viewer | MPL-2.0, LGPL-3.0 |
| [Intel Media Driver](https://github.com/intel/media-driver), [libva](https://github.com/intel/libva) | VA-API video encoding | MIT |

## In macOS and around the simulators

| Project | | License |
|---|---|---|
| [agent-device](https://github.com/callstack/agent-device), by Callstack | drives the iOS Simulator (and Android) for agents: snapshots, taps, typing | MIT |
| [simslim](https://github.com/MobAI-App/simslim), by MobAI | turns off background services in the slim simulators | MIT |
| [expo-device-hub](https://github.com/expo/expo-device-hub) (serve-sim), by Expo | T3 Code's device hub; macbox rebuilds its native parts for Intel | MIT |
| [T3 Code](https://github.com/pingdotgg/t3code) | the coding app whose Device panel shows the simulators | MIT |
| [Expo](https://github.com/expo/expo), [EAS CLI](https://github.com/expo/eas-cli), [React Native](https://github.com/facebook/react-native) | the apps the tools build and run | MIT |
| [Node.js](https://nodejs.org/) | the guest's JavaScript runtime | MIT |
| [Homebrew portable-ruby](https://github.com/Homebrew/homebrew-portable-ruby), [CocoaPods](https://github.com/CocoaPods/CocoaPods) | iOS dependencies for React Native builds | BSD-2-Clause, MIT |
| [Go](https://go.dev/) | builds simslim | BSD-3-Clause |
| [FFmpeg](https://ffmpeg.org/) | `sim-fps` reads recordings with ffprobe | LGPL-2.1+/GPL |
| [Android Emulator and SDK](https://developer.android.com/studio) | the optional Android emulators | Android SDK License |

The simulator verification loop in the `simulators` skill (record every flow, hold 60 fps, look at
the frames) follows the principles of [Appllama](https://appllama.io)'s app design skill.

## Apple

macOS, Xcode and the iOS Simulator runtimes are Apple's, downloaded from Apple under Apple's
terms; macbox contains none of them. See the legal note in the [README](README.md#disclaimer).
