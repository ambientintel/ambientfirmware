# TI AM62x Firmware Project — SK-AM62-LP

## Hardware target
- **Board:** TI SK-AM62-LP (low-power AM62x starter kit)
- **SoC:** AM625 — quad Cortex-A53 @ 1.4 GHz + Cortex-M4F + Cortex-R5F
- **Memory:** LPDDR4
- **Debug console:** onboard FT4232 USB-UART bridge via micro-USB (J17 on board)
- **JTAG:** onboard XDS110 via separate micro-USB (J15)

## Reference docs
- `workspace/docs/BOOT_DAY_RUNBOOK.md` — First power-on procedure for SK-AM62-LP. Covers SD card prep, serial console setup, expected output at each boot stage, and troubleshooting.
- `workspace/device-tree/README.md` — Custom device tree build flow.

## Host build environment
- **Host OS:** macOS (Apple Silicon)
- **Build container:** Ubuntu 22.04 x86_64 under Docker Desktop (QEMU emulation, Rosetta OFF)
- **Workspace bind mount:** `~/ti-am62x/workspace` (Mac) ↔ `/workspace` (container)
- **Enter container:** `~/ti-am62x/enter.sh`
- **Git workflow:** edits happen in the container, commits and pushes happen in GitHub Desktop on the Mac (the bind mount makes container edits visible to the host).

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
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
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

## Custom device tree workflow
Out-of-tree DTS lives at `workspace/device-tree/k3-am62-lp-sk-ambient.dts`. It `#include`s the stock `k3-am62-lp-sk.dts` and overrides only `compatible` and `model`. Ambient-specific peripherals (sensor nodes, custom pinmux) get added below the root node as new content lands.

**Naming convention:** TI uses `am62-lp-sk` (SoC family + LP variant), not `am625-sk-lp`. The earlier wrong name produced a non-existent include path. New ambient board files must follow TI's convention to keep includes resolvable.

**Build flow:** `workspace/device-tree/Makefile` is build glue, not a kernel Makefile. It copies the DTS into `$(KERNEL_SRC)/arch/arm64/boot/dts/ti/`, registers a new line in the kernel's DT Makefile via `awk` exact-line insertion (anchored on the stock `k3-am62-lp-sk.dtb` entry), then invokes `make dtbs` in the kernel tree. Idempotent — safe to re-run. Validates the anchor line exists in the kernel Makefile up front, so future SDK format changes fail loudly rather than silently no-op.

```bash
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
cd /workspace/device-tree
make build KERNEL_SRC=$KERNEL_SRC
# produces $KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb
```

Stock `k3-am62-lp-sk.dtb` remains the boot default. Ambient DTB gets selected via `fdtfile` env var or `extlinux.conf` once we're ready to switch.

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
- [x] Docker Ubuntu 22.04 x86_64 container set up (QEMU emulation, Rosetta OFF)
- [x] TI Processor SDK Linux 11.02.08.02 installed
- [x] Cross-toolchain verified (aarch64-oe-linux-gcc 13.4)
- [x] Kernel + DTB build succeeded (Image=22MB, k3-am62-lp-sk.dtb=65KB)
- [x] U-Boot compiled (tiboot3.bin, tispl.bin, u-boot.img)
- [x] Git repo pushed to ambientintel/ambientfirmware
- [x] Custom DTB build flow validated end-to-end (k3-am62-lp-sk-ambient.dtb)
- [ ] Hardware received (SK-AM62-LP on order)
- [ ] First boot with prebuilt SD card image
- [ ] First boot with custom kernel
- [ ] TFTP/NFS dev loop set up
- [ ] Rootfs decision (Buildroot vs trimmed Yocto vs tisdk default)
- [ ] Define project goals

## Lessons learned

### Rosetta bss_size bug — disable Rosetta in Docker Desktop
Docker Desktop's Rosetta x86_64 emulation has a bug where `.bss` section sizes are miscalculated during linking, producing silently corrupt binaries (U-Boot SPL was the symptom). Fix: open Docker Desktop → Settings → General → uncheck "Use Rosetta for x86_64/amd64 emulation on Apple Silicon". Use QEMU emulation only.

### `linux-devkit/environment-setup` pollutes CPATH for kernel/U-Boot builds
Sourcing `linux-devkit/environment-setup` sets `CC`, `CFLAGS`, and `CPATH` to aarch64 sysroot paths. This breaks `HOSTCC` (the host compiler used for `scripts/`, `tools/`, etc.) and causes confusing build failures. Never source it for kernel or U-Boot builds. Use `/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh` instead — it sets only `PATH`, `ARCH`, and `CROSS_COMPILE`.

### U-Boot 2025.01 requires extra host packages
The TI U-Boot 2025.01 tree needs several host tools not present in a minimal Ubuntu 22.04 container:
```
apt-get install -y swig libgnutls28-dev python3-yaml yamllint \
    libssl-dev python3-dev python3-setuptools
```
Symptom without these: cryptic Python import errors or missing `gnutls` linker failures mid-build.

### SDK Makefile defaults to `MAKE_JOBS=1` — always override
The top-level SDK `Makefile` / `Rules.make` sets `MAKE_JOBS ?= 1`. Under QEMU this makes an already slow build ~8× slower than necessary. Always pass an explicit job count:
```bash
make MAKE_JOBS=$(nproc) ...
# or equivalently for direct kernel/U-Boot invocations:
make -j$(nproc) ...
```

### TI device tree naming — `am62-lp-sk`, not `am625-sk-lp`
TI's upstream convention puts the SoC *family* (`am62`) and the variant tag (`lp`) in the prefix, with the board class (`sk`) at the end: `k3-am62-lp-sk.dts`. The intuitive-but-wrong order `k3-am625-sk-lp.dts` does not exist in the kernel tree. Any new derived DTS must `#include` the real upstream filename or the C preprocessor fails before DTC runs.

### `make -n` does not propagate to recursive sub-makes
The dry-run flag stops at the first `make -C ...` invocation. For two-stage builds (workspace Makefile that invokes a kernel Makefile), `make -n` will print the outer commands but the sub-make actually runs. Don't trust `-n` to be a true dry run when recursion is involved — verify with explicit before/after state checks instead.

### Anchoring `sed` insertions into the kernel DT Makefile
The kernel's `arch/arm64/boot/dts/ti/Makefile` has many lines containing `k3-am62-lp-sk.dtb` as a substring (e.g., in `*-dtbs := k3-am62-lp-sk.dtb \` continuation blocks). A loose `sed '/k3-am62-lp-sk\.dtb/a ...'` will match all of them and insert duplicates on every run. Use exact-line matching (`awk '$0 == anchor'` or `grep -Fxq`) for both insertion and existence checks. Also: `sed -i.bak` overwrites the backup on every run, so the `.bak` is *not* a safe pristine-state restore — it's only the previous run's state, which may itself have been broken.

## Project goal
_TBD — to be filled in as direction solidifies._
