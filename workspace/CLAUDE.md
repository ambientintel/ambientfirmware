# TI AM62x Firmware Project — SK-AM62-LP

## Hardware target
- **Board:** TI SK-AM62-LP (low-power AM62x starter kit)
- **SoC:** AM625 — quad Cortex-A53 @ 1.4 GHz + Cortex-M4F + Cortex-R5F
- **Memory:** LPDDR4
- **Debug console:** onboard FT4232 USB-UART bridge via micro-USB (J17 on board)
- **JTAG:** onboard XDS110 via separate micro-USB (J15)

## Host build environment
- **Host OS:** macOS (Apple Silicon)
- **Build container:** Ubuntu 22.04 x86_64 under Docker Desktop (QEMU emulation, Rosetta OFF)
- **Workspace bind mount:** `~/ti-am62x/workspace` (Mac) ↔ `/workspace` (container)
- **Enter container:** `~/ti-am62x/enter.sh`

## SDK
- **Version:** TI Processor SDK Linux AM62x 11.02.08.02 (2026 LTS)
- **SDK root:** `/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/` (in container)
- **On Mac:** `~/ti-am62x/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/`
- **Kernel:** `board-support/ti-linux-kernel-6.12.57+git-ti/`
- **U-Boot:** `board-support/u-boot-*/`
- **Prebuilt images:** `board-support/prebuilt-images/am62xx-evm/`
- **Cross toolchain (A53):** `aarch64-oe-linux-gcc 13.4` in `linux-devkit/sysroots/x86_64-arago-linux/usr/bin/aarch64-oe-linux/`
- **R5F toolchain:** `k3r5-devkit/`

## Build conventions

### Kernel and U-Boot
Do **NOT** source `linux-devkit/environment-setup` — it pollutes CPATH/CC/CFLAGS with aarch64 paths and breaks HOSTCC.
Instead, source the project helper:
```bash
source /workspace/sdk/kernel-env.sh
```
This sets `PATH`, `ARCH=arm64`, `CROSS_COMPILE=aarch64-oe-linux-` without contaminating HOSTCC.

Standard kernel build:
```bash
cd /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/ti-linux-kernel-*/
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- ti_arm64_prune.config
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- -j$(nproc) Image dtbs
```

### Userspace applications
DO source `linux-devkit/environment-setup` — this is what it's designed for.

### Never mix
Open separate shells for kernel builds vs userspace builds.

## Key device tree files for SK-AM62-LP
- Base SoC: `arch/arm64/boot/dts/ti/k3-am625.dtsi` (or equivalent)
- Board: `arch/arm64/boot/dts/ti/k3-am62-lp-sk.dts`
- Overlays:
  - `k3-am62-lp-sk-nand.dtso` — NAND flash
  - `k3-am62x-sk-lpm-standby.dtso` — low-power standby mode
  - `k3-am62-lp-sk-lincolntech-lcd185-panel.dtso` — LCD panel
  - `k3-am62-lp-sk-microtips-mf101hie-panel.dtso` — LCD panel

## Conventions / don'ts
- Don't modify `linux-devkit/` — that's the sysroot, treat as read-only
- Kernel changes: create patches in a dedicated `patches/` dir rather than committing directly to the TI kernel tree
- Device tree overlays preferred over modifying base .dts files
- Don't commit build artifacts (`*.o`, `.tmp_versions`, `arch/arm64/boot/Image`, etc.)

## Build performance notes
- Docker under QEMU emulation is 3–5× slower than native x86
- Full kernel build: ~45–90 min (completed successfully once)
- Yocto full build: not yet attempted; estimate 12–20+ hours; will likely use cloud VM

## Current status
- [x] Docker Ubuntu 22.04 x86_64 container set up
- [x] TI Processor SDK Linux 11.02.08.02 installed
- [x] Cross-toolchain verified (aarch64-oe-linux-gcc 13.4)
- [x] Kernel + DTB build succeeded (Image=22MB, k3-am62-lp-sk.dtb=65KB)
- [ ] Hardware received (ordering in progress)
- [ ] Prebuilt SD card image flashed and booted
- [ ] Custom kernel flashed and booted
- [ ] U-Boot custom build
- [ ] Full Yocto build

## Project goal
_TBD — to be filled in as direction solidifies._
