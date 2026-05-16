# ambientfirmware

Containerized build environment and tracked working tree for TI AM62x Linux firmware
work (bootloader, kernel, device tree, eventual Yocto image). Targets the SK-AM62-LP
dev board; production target is a custom PCB around the Octavo OSD62x-PM SiP plus
a TI IWR6843AOP 60 GHz radar.

Scope is device-level only: bootloader, kernel, BSP, DTBs. No application code, no
subject data, no PII. Radar and sensor data handling live in other repos.

## What's in here

- `Dockerfile` — Ubuntu 22.04 x86_64 image with Yocto/bitbake/U-Boot/kernel build deps.
- `enter.sh` — wrapper that runs the container with the workspace bind-mounted.
- `workspace/` — tracked portion of the in-container `/workspace` tree:
  - `SETUP-NOTES.md` — Rosetta bug, extra apt/pip packages, verified build commands, build-time estimates.
  - `CLAUDE.md` — full project context (hardware target, SDK layout, build conventions, custom board architecture, open decisions). Read this before touching anything non-obvious.
  - `device-tree/` — out-of-tree DTS plus build glue that splices into the SDK kernel's DT Makefile.
  - `docs/` — `BOOT_DAY_RUNBOOK.md`, `DEVICETREE.md`, ADRs, session findings.

## What's *not* in here

- The TI Processor SDK (~14 GB). Re-download from TI into `workspace/sdk/`; gitignored.
- Build outputs (kernel `Image`, DTBs, U-Boot artifacts, `.o`, `build/`). See `.gitignore`.
- Firmware source for the A53 apps or radar. Different repos.

## Prerequisites

- Apple Silicon Mac (tested) or any Docker host that can run `linux/amd64` images. On Apple Silicon this runs under QEMU emulation and is 3–5× slower than native x86.
- Docker Desktop with **"Use Rosetta for x86/amd64 emulation" disabled** (General settings). The TI SDK installer hits `rosetta error: bss_size overflow` under Rosetta; QEMU works. See `workspace/SETUP-NOTES.md`.
- ~20 GB free disk: 14 GB for the TI SDK once downloaded, plus headroom for kernel/U-Boot/Yocto builds.

## First-time setup

1. Build the image:
   ```
   docker build --platform linux/amd64 -t ti-am62x-dev .
   ```
2. Fix the bind-mount path in `enter.sh` (see gotcha below), or create the symlink the current script expects.
3. Download the TI Processor SDK Linux AM62x 11.02.08.02 installer from TI and extract into `workspace/sdk/ti-processor-sdk-linux-am62xx-evm/` on the host (the gitignored location).
4. Enter the container (see next section) and follow `workspace/SETUP-NOTES.md` for the verified kernel and U-Boot build commands.

## Entering the container

```
./enter.sh
```

Drops you at `/workspace` as user `dev`. Inside the container, source the project's kernel env helper before kernel/U-Boot work — **not** the SDK's `linux-devkit/environment-setup`, which pollutes `CPATH` and breaks `HOSTCC`:

```
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
```

For userspace builds, `linux-devkit/environment-setup` is the correct thing to source. Keep the two kinds of builds in separate shells.

## Workspace layout

`enter.sh` bind-mounts `~/ti-am62x/workspace`. This repo lives at `~/ambientfirmware/`. A symlink makes everything work without editing scripts:

```
ln -s ~/ambientfirmware/workspace ~/ti-am62x/workspace
```

The 14 GB TI SDK and build outputs live at `~/ti-am62x/workspace/sdk/` (gitignored). The symlink means container edits are immediately visible in the tracked `workspace/` tree.

## Git workflow

Container-side edits are visible on the host via the bind mount. Commit and push from the host (GitHub Desktop, or `git` on the Mac) rather than inside the container, so SSH keys and identity stay on the host.

## Gotchas

- **Rosetta off.** See prerequisites. Non-negotiable until TI fixes the installer.
- **Don't source `linux-devkit/environment-setup` for kernel/U-Boot builds.** Breaks `HOSTCC`. Use `kernel-env.sh` per SETUP-NOTES.
- **TI DT naming.** Board is `am62-lp-sk`, not `am625-sk-lp`. Wrong name produces non-existent include paths. See `workspace/CLAUDE.md` → "Naming convention."
- **SD card prep on macOS.** Do not use macOS `fdisk` to manually partition. The ROM silently rejects the result. Use **balenaEtcher + the LP WIC image** (`tisdk-default-image-am62xx-lp-evm-*.rootfs.wic.xz`) from the TI SDK download page. See `workspace/docs/BOOT_DAY_RUNBOOK.md §2`.
- **tiboot3 variant for PROC124E2.** The board is HS-FS. Use `tiboot3-am62x-hs-fs-evm.bin` from `prebuilt-images/am62xx-lp-evm/`, not the plain `tiboot3.bin` symlink (may point to HS, not HS-FS). Wrong variant = complete silence on boot.
- **Yocto builds.** Not attempted locally. Estimated 12–20+ hours under QEMU; plan on a cloud x86 VM.
- **Two `.dtb` targets coming.** SK-AM62-LP dev DTB uses SK DDR settings; production DTB for the OSD62x-PM custom board needs Octavo's DDR configuration and is a separate artifact.

## First boot (2026-05-15)

First successful boot of the SK-AM62-LP, step by step:

**What was tried first and failed:**

1. Partitioned the SD card manually on macOS using `fdisk -e` and `newfs_msdos -F 32`. The AM62x ROM produced zero serial output. Root cause: macOS fdisk creates partition tables the ROM silently rejects (wrong type, missing bootable flag, or bad alignment). Do not use macOS fdisk for this board.

2. Flashed a WIC image using balenaEtcher. Flashing appeared to succeed but errored out twice ("writer process ended unexpectedly"). File was intact (verified with `ls -lh`). balenaEtcher failed on this file; unclear why.

**What worked:**

3. Flashed the SDK 12.00.00.07.04 LP WIC image using the `xz | dd` pipeline:
   ```
   diskutil unmountDisk /dev/disk19
   xz -d --stdout /Users/brianxbradley/Downloads/tisdk-default-image-am62xx-lp-evm-12.00.00.07.04.rootfs.wic.xz \
     | sudo dd of=/dev/rdisk19 bs=8m
   ```
   The WIC image is a complete disk image (MBR + FAT32 boot + ext4 rootfs) with the correct HS-FS tiboot3 variant already placed. No manual partitioning needed.

4. Boot switches: SW3 (bits 0–7): sw1, sw2, sw7 ON, rest OFF. SW4 (bits 8–15): sw2 ON only. (Source: SPRUJ51A Fig 2-5. SW1 is a push button, not a DIP switch — do not touch.)

5. Serial console: connect micro-USB-B to J17 (FT4232 UART bridge). J17 enumerates as four UART ports; use the one ending in `40` (SOC_UART0 = Linux console):
   ```
   tio /dev/tty.usbserial-XXXXXXXXXXXX40 -b 115200
   ```

6. Connected USB-C power to J13. Board booted to login prompt on first attempt.

**First boot results (kernel from WIC image, SDK 12.x):**
```
uname -a: Linux am62xx-lp-evm 6.18.13-ti-00778-gc21449208550-dirty aarch64
model:    Texas Instruments AM62x LP SK
net:      eth0 eth1 lo mcu_mcan0 mcu_mcan1
errors:   only benign (RTC erratum i2327, PowerVR GPU firmware missing)
```

**What's next:**
- Boot with custom kernel (SDK 11.x + our kernel build) by replacing the boot files on the WIC-flashed SD card
- Set up TFTP/NFS dev loop
- Build and boot the ambient DTB (`k3-am62-lp-sk-ambient.dtb`)

---

## Further reading

- `workspace/CLAUDE.md` — project scope, SDK layout, build conventions, board architecture, open decisions.
- `workspace/SETUP-NOTES.md` — environment setup, package lists, verified build commands, build times.
- `workspace/docs/BOOT_DAY_RUNBOOK.md` — first power-on procedure for SK-AM62-LP.
- `workspace/device-tree/README.md` — custom DT build flow.
- `docs/vendor/` — TI reference docs pinned to known revisions (SK-AM62-LP EVM user's guide, etc.).
