# macbox: one image builds Reims vGPU's QEMU and runs the macOS VM with its display stack.
# Ubuntu 26.10 for Mesa 26.2 (the Vulkan drivers Reims runs on) and Python 3.14.
FROM ubuntu:26.10
ENV DEBIAN_FRONTEND=noninteractive
# Build: Reims vGPU (Rust, SDL3 from source, jemalloc), its option ROM (clang, lld) and QEMU.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates pkg-config python3 python3-venv python3-dev ninja-build \
    flex bison bzip2 cmake clang lld binutils libglib2.0-dev libpixman-1-dev libslirp-dev \
    zlib1g-dev libfdt-dev libpipewire-0.3-dev libpulse-dev libasound2-dev libvulkan1 \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxss-dev \
    libxtst-dev libxkbcommon-dev libwayland-dev libwayland-bin libdecor-0-dev \
    libegl-dev libgl-dev libdrm-dev libgbm-dev libdbus-1-dev libudev-dev libgtk-3-dev \
    mesa-vulkan-drivers vulkan-tools xz-utils unzip file iproute2 procps socat \
    openssh-client tini \
 && rm -rf /var/lib/apt/lists/*
# Run: passt (the VM's network), a private headless sway for the VM's window, the browser stream
# (Selkies in a venv; noVNC over wayvnc as the fallback), and VA-API drivers for its encoder
# (Intel: iHD; AMD: Mesa's).
RUN apt-get update && apt-get install -y --no-install-recommends \
    passt sway wayvnc novnc websockify libva-drm2 vainfo intel-media-va-driver mesa-va-drivers \
 && rm -rf /var/lib/apt/lists/*
COPY sway.conf /etc/macbox/sway.conf
