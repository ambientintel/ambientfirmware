# TI AM62x SDK 11.02.08.02 Build Environment — Setup Notes

## Environment
- Host: Apple Silicon Mac (M-series), macOS
- Docker Desktop with Rosetta **disabled** (QEMU emulation for x86_64)
- Container: Ubuntu 22.04 x86_64

## Rosetta bug
The SDK installer binary hits `rosetta error: bss_size overflow`.
Workaround: disable "Use Rosetta for x86/amd64 emulation" in Docker Desktop → General.

## Required packages beyond stock Ubuntu 22.04
These were not in the original Dockerfile and had to be added one-by-one during U-Boot build.

### apt packages
    sudo apt install -y \
        swig \
        python3-dev \
        python3-setuptools \
        libgnutls28-dev \
        uuid-dev \
        libftdi-dev \
        libusb-1.0-0-dev \
        libcap-dev \
        libpython3-dev \
        pkg-config \
        python3-yaml \
        python3-pyelftools \
        python3-jsonschema \
        python3-lxml

### pip packages (not available via apt in Ubuntu 22.04)
    sudo pip3 install yamllint

## Environment setup
Do NOT source `linux-devkit/environment-setup` for kernel/U-Boot builds — it pollutes CPATH and breaks HOSTCC.

Use this helper instead:

    source /workspace/sdk/kernel-env.sh

## Build commands verified working
- Kernel: `make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- -j$(nproc) Image dtbs`
- U-Boot: `make MAKE_JOBS=$(nproc) u-boot` (from SDK root)

## Artifacts produced
- Kernel: `board-support/ti-linux-kernel-6.12.57+git-ti/arch/arm64/boot/Image`
- DTB: `board-support/ti-linux-kernel-*/arch/arm64/boot/dts/ti/k3-am62-lp-sk.dtb`
- R5 SPL: `board-support/u-boot-build/r5/tiboot3.bin`
- A53 SPL: `board-support/u-boot-build/a53/tispl.bin`
- U-Boot: `board-support/u-boot-build/a53/u-boot.img`

## Build times (QEMU on M-series Mac)
- Kernel + DTB: ~45–60 min
- U-Boot (both passes): ~60–90 min
- Yocto (not attempted): estimated 12–20+ hours — plan for cloud Linux VM instead
