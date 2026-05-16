# SK-AM62-LP First Boot — Complete Tutorial

End-to-end guide from hardware unboxing to logged-in Linux shell. Covers
every step that was actually executed to achieve first boot on 2026-05-15,
including every failure encountered and why it happened.

**Board:** TI SK-AM62-LP, PROC124E2 (HS-FS device)  
**Host:** Apple Silicon Mac (macOS 15), Docker Desktop 4.x  
**SDK used for first boot:** TI Processor SDK Linux AM62x 12.00.00.07.04 (WIC image)  
**SDK used for development builds:** TI Processor SDK Linux AM62x 11.02.08.02  

---

## Prerequisites

### Hardware

| Item | Notes |
|---|---|
| SK-AM62-LP board | Any board revision is fine. The board is an HS-FS device — ensure your SD card has `tiboot3-am62x-hs-fs-evm.bin`, not the generic `tiboot3.bin` symlink. Wrong variant = complete silence, which looks identical to a dead board. |
| micro-USB-B cable × 2 | One for J17 (UART console), one for J18 (JTAG) if needed |
| USB-C cable + charger | 5–15V, **3A minimum**. Apple 20W USB-C confirmed working. |
| microSD card | 8 GB minimum, Class 10 or better. Cheap cards cause mysterious intermittent failures. |
| USB-A or USB-C SD card reader | macOS will enumerate it as `/dev/disk<N>` |

### Software (macOS)

```bash
brew install tio          # serial console — much better than screen
brew install xz           # for the WIC decompression pipeline (usually pre-installed)
```

### Docker Desktop

- Install Docker Desktop for Mac
- **Critical:** Open Docker Desktop → Settings → General → **uncheck "Use Rosetta for x86/amd64 emulation on Apple Silicon"**
- The TI SDK installer hits a Rosetta `.bss` section size overflow bug that produces silently corrupt binaries. Use QEMU emulation only.

---

## Step 1: Clone the repo and set up the workspace symlink

```bash
git clone https://github.com/ambientintel/ambientfirm.git ~/ambientfirmware
ln -s ~/ambientfirmware/workspace ~/ti-am62x/workspace
```

The container bind-mounts `~/ti-am62x/workspace`. The symlink lets container
edits land directly in the tracked repo tree without modifying `enter.sh`.

Verify:
```bash
ls ~/ti-am62x/workspace   # should show the workspace contents
```

---

## Step 2: Build the Docker container

```bash
cd ~/ambientfirmware
docker build --platform linux/amd64 -t ti-am62x-dev .
```

On Apple Silicon this runs under QEMU x86_64 emulation. Build takes 2–5 min.

---

## Step 3: Install the TI Processor SDK

The SDK is 14 GB and not committed to the repo.

1. Download **TI Processor SDK Linux AM62x 11.02.08.02** from `software.ti.com`
   (requires free TI account). Use the `.run` installer.
2. Place the installer at `~/ti-am62x/workspace/sdk/` on the Mac.
3. Enter the container and run it:

```bash
./enter.sh
cd /workspace/sdk
./ti-processor-sdk-linux-am62xx-evm-11.02.08.02-Linux-x86-Install.run
# Accept the license, install to /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/
```

SDK root inside the container: `/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/`

Key subdirectories:

| Path (relative to SDK root) | Contents |
|---|---|
| `board-support/ti-linux-kernel-6.12.57+git-ti/` | Kernel source |
| `board-support/u-boot-*/` | U-Boot source |
| `board-support/prebuilt-images/am62xx-lp-evm/` | TI prebuilt LP binaries |
| `linux-devkit/.../aarch64-oe-linux/` | A53 cross-compiler |
| `kernel-env.sh` | Safe env helper for kernel/U-Boot builds |

---

## Step 4: Install extra build dependencies

U-Boot 2025.01 needs packages not in a stock Ubuntu 22.04 container:

```bash
# Inside the container
sudo apt-get install -y \
  swig python3-dev python3-setuptools \
  libgnutls28-dev uuid-dev libftdi-dev \
  libusb-1.0-0-dev libcap-dev libpython3-dev \
  pkg-config python3-yaml python3-pyelftools \
  python3-jsonschema python3-lxml
sudo pip3 install yamllint
```

Missing `swig` causes cryptic Python import errors mid-U-Boot build.

---

## Step 5: Set up the build environment

**Every new shell, before any kernel or U-Boot work:**

```bash
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
export KERNEL_SRC=/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/ti-linux-kernel-6.12.57+git-ti

# Verify the toolchain
aarch64-oe-linux-gcc --version
# → aarch64-oe-linux-gcc (GCC) 13.4.0
```

**Do NOT** source `linux-devkit/environment-setup` for kernel or U-Boot builds.
It sets `CC`, `CFLAGS`, and `CPATH` to the aarch64 sysroot, which breaks
`HOSTCC` and produces confusing build failures. Use `kernel-env.sh` only.

---

## Step 6: Build U-Boot

```bash
cd /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/
make MAKE_JOBS=$(nproc) u-boot
```

The SDK Makefile defaults to `MAKE_JOBS=1`. Under QEMU this is ~8× slower than necessary. Always override with `$(nproc)`.

Expect ~60–90 minutes. Output artifacts:

| Artifact | Role |
|---|---|
| `board-support/u-boot-build/r5/tiboot3.bin` | R5 SPL + TIFS firmware. ROM loads this from SD. |
| `board-support/u-boot-build/a53/tispl.bin` | A53 SPL + ATF (BL31) + OP-TEE (BL32) + DM firmware. |
| `board-support/u-boot-build/a53/u-boot.img` | U-Boot proper. |

Sanity check:
```bash
file board-support/u-boot-build/r5/tiboot3.bin   # → data
file board-support/u-boot-build/a53/tispl.bin     # → FIT image
file board-support/u-boot-build/a53/u-boot.img    # → u-boot legacy image
```

---

## Step 7: Build the kernel and DTBs

```bash
cd $KERNEL_SRC
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- ti_arm64_prune.config
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- -j$(nproc) Image dtbs
```

Expect ~45–60 minutes. Output:

| Artifact | Size |
|---|---|
| `arch/arm64/boot/Image` | ~22 MB |
| `arch/arm64/boot/dts/ti/k3-am62-lp-sk.dtb` | ~65 KB |

**Naming gotcha:** TI's file is `k3-am62-lp-sk.dts` — not `k3-am625-sk-lp.dts`.
The wrong name fails at `#include` with a non-obvious error.

---

## Step 8: Build the ambient device tree (optional for first boot)

The ambient DTS lives at `workspace/device-tree/` and extends the stock SK-LP
DTS with sensor nodes. Skip for first boot — use the stock `k3-am62-lp-sk.dtb`.

When you're ready:

```bash
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
cd /workspace/device-tree
make build KERNEL_SRC=$KERNEL_SRC
# output: $KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb
```

---

## Step 9: Prepare the SD card

### 9a. Download the LP WIC image

The WIC image is a complete disk image (MBR + FAT32 boot + ext4 rootfs) with
the correct HS-FS `tiboot3` variant preloaded. **Use this for first boot.**
Do not use macOS `fdisk` to manually partition — the AM62x ROM silently rejects
the partition tables that macOS fdisk produces.

Exact file:
```
tisdk-default-image-am62xx-lp-evm-12.00.00.07.04.rootfs.wic.xz
```

Download URL (no TI account required):
```
https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-PvdSyIiioq/12.00.00.07.04/tisdk-default-image-am62xx-lp-evm-12.00.00.07.04.rootfs.wic.xz
```

Via curl (saves as short alias):
```bash
curl -L -o ~/Downloads/tisdk-lp-evm-12.wic.xz \
  "https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-PvdSyIiioq/12.00.00.07.04/tisdk-default-image-am62xx-lp-evm-12.00.00.07.04.rootfs.wic.xz"
```

If you download in the browser, the filename is the full one above — adjust
the path in step 9b accordingly.

### 9b. Flash with xz|dd

This is the confirmed-working method. balenaEtcher was attempted and failed
twice with "writer process ended unexpectedly" on this file — use dd.

```bash
# Verify diskN is your SD card — CRITICAL, wrong disk number destroys data
diskutil list

diskutil unmountDisk /dev/diskN
xz -d --stdout ~/Downloads/tisdk-lp-evm-12.wic.xz | sudo dd of=/dev/rdiskN bs=8m
# Press Ctrl-T to check progress. Expect ~5–10 min for a 32 GB card.
```

### 9c. Replace boot files with your custom kernel (optional)

The WIC image ships SDK 12.x binaries. To boot your SDK 11.x custom build,
after flashing mount the FAT BOOT partition and replace:

```bash
PREBUILT=~/ti-am62x/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/prebuilt-images/am62xx-lp-evm

# HS-FS variant explicitly — PROC124E2 is HS-FS, not GP or plain HS
cp $PREBUILT/tiboot3-am62x-hs-fs-evm.bin /Volumes/BOOT/tiboot3.bin
cp $PREBUILT/tispl.bin                    /Volumes/BOOT/
cp $PREBUILT/u-boot.img                   /Volumes/BOOT/
cp $PREBUILT/Image                        /Volumes/BOOT/
cp $PREBUILT/k3-am62-lp-sk.dtb           /Volumes/BOOT/
cp $PREBUILT/uEnv.txt                     /Volumes/BOOT/
sync
diskutil unmountDisk /dev/diskN
```

**tiboot3 variant matters:** Always use `tiboot3-am62x-hs-fs-evm.bin` explicitly.
The plain `tiboot3.bin` symlink in the prebuilt directory may point to the HS
(not HS-FS) variant. Wrong variant = ROM silently rejects it = zero serial output.

---

## Step 10: Set the boot mode switches

The LP board has two 8-position DIP switch banks on the top of the board:

| Bank | sw1 | sw2 | sw3 | sw4 | sw5 | sw6 | sw7 | sw8 |
|---|---|---|---|---|---|---|---|---|
| **SW3** | ON | ON | OFF | OFF | OFF | OFF | ON | OFF |
| **SW4** | OFF | ON | OFF | OFF | OFF | OFF | OFF | OFF |

Source: SPRUJ51A Fig 2-5, "uSD Boot (MMC1) — 25 MHz PLL"

**Critical:** SW1 on the board is a blue tactile **push button** (RST+INT) — not
a DIP switch. Do not confuse the push button banks (SW1, SW2, SW5, SW6) with
the DIP switch banks (SW3, SW4).

SW4 has exactly **one switch ON** (sw2 only). This is correct per Table 2-32:
"MMC Port 1 — this bit must be set to 1."

---

## Step 11: Connect cables

1. **Insert the SD card** into the microSD slot.
2. **Connect micro-USB-B to J17** — this is the FT4232 UART bridge, labeled
   "FTDI Micro-USB" on the board silkscreen. This is the serial console.
   - J18 is the XDS110 JTAG port (also micro-USB-B) — not the console.
3. **Do not connect power yet.**

---

## Step 12: Open the serial console

On the Mac, the FT4232 on J17 enumerates as **four** UART ports:

```bash
ls /dev/tty.usbserial-*
# → /dev/tty.usbserial-XXXXXXXXXXXX40  ← SOC_UART0 — Linux console, use this
#   /dev/tty.usbserial-XXXXXXXXXXXX41  ← SOC_UART1
#   /dev/tty.usbserial-XXXXXXXXXXXX42  ← WKUP_UART0
#   /dev/tty.usbserial-XXXXXXXXXXXX43  ← MCU_UART0
# The 12-digit prefix varies per cable and USB hub.
```

Open the console port (ends in 40):

```bash
tio /dev/tty.usbserial-XXXXXXXXXXXX40 -b 115200
```

Settings: **115200 8N1, no flow control.** Once open you will see nothing — the
board has no power yet. That is correct.

If the port ending in 40 is not present, take the lowest-numbered port from
`ls /dev/tty.usbserial-*`.

---

## Step 13: Power on

Connect a USB-C cable to **J13** (or J15). Use a 5–15V, 3A minimum source.
Apple 20W USB-C adapter confirmed working.

Expected output on the serial console, in order:

### Stage 1 — ROM → tiboot3 (within ~1 second)
```
U-Boot SPL 2024.xx-ti-...
SYSFW ABI: 3.1 (firmware rev 0x...)
SPL initial stack usage: NNN bytes
Trying to boot from MMC2
```

**If nothing:** ROM could not load tiboot3. See Troubleshooting below.

### Stage 2 — tiboot3 → tispl (DDR training)
```
Loading Environment from MMC... OK
Loading fit image from MMC
```

### Stage 3 — A53 SPL → U-Boot
```
U-Boot 2024.xx-ti-...
CPU: AM62X SR1.0 HS-FS
Model: Texas Instruments AM625 SK LP
...
Hit any key to stop autoboot:  3
```

Let autoboot proceed (or press any key to get a U-Boot prompt).

### Stage 4 — Kernel boot
```
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x410fd034]
[    0.000000] Linux version 6.x.x-ti-...
```

### Stage 5 — Login prompt
```
Welcome to TI SDK ...
am62xx-evm login:
```

Login: `root`, no password.

---

## Step 14: Verify the boot

```bash
uname -a
# → Linux am62xx-lp-evm 6.18.13-ti-00778-... aarch64 GNU/Linux  (SDK 12 WIC)
# → Linux am62xx-lp-evm 6.12.57-ti-...       aarch64 GNU/Linux  (SDK 11 custom)

cat /proc/device-tree/model
# → Texas Instruments AM62x LP SK

ls /sys/class/net
# → eth0  eth1  lo  mcu_mcan0  mcu_mcan1

dmesg | grep -i error
# Only benign: RTC erratum i2327, PowerVR GPU firmware missing (irrelevant)
```

Capture the full boot log before any future changes:

```bash
# Re-connect with logging before next power cycle
tio /dev/tty.usbserial-XXXXXXXXXXXX40 -b 115200 --log-file first-boot.log
```

Commit `first-boot.log` to the repo as a regression baseline.

---

## Step 15: Snapshot the SD card

Before changing anything, snapshot the working SD card:

```bash
# On the Mac — verify diskN is the SD card
diskutil unmountDisk /dev/diskN
sudo dd if=/dev/rdiskN of=~/ti-am62x/workspace/golden-sd.img bs=8m
# Compress to save space
xz -9 ~/ti-am62x/workspace/golden-sd.img
```

The `.img.xz` is your recovery point. Re-flash it if you break something.

---

## Troubleshooting

### Zero serial output (no tiboot3 banner)

The AM62x ROM produces **zero UART output itself**. The first output comes from
`tiboot3` (R5 SPL). Silence = ROM could not load `tiboot3.bin`.

| Symptom | Cause | Fix |
|---|---|---|
| Nothing at all | Wrong UART port | Use port ending in `40` (SOC_UART0) |
| Nothing at all | macOS fdisk SD card | Re-flash with `xz\|dd` + WIC image |
| Nothing at all | Wrong tiboot3 variant | Must be `tiboot3-am62x-hs-fs-evm.bin` |
| Nothing at all | Boot mode switches wrong | Verify SW3/SW4 against SPRUJ51A Fig 2-5 |
| Nothing at all | Wrong tiboot3 variant or bad SD partition | Most likely cause — see note below |
| Garbage on serial | Wrong baud rate | Confirm 115200 8N1 |

**"Nothing at all" almost always means wrong SD card contents, not a dead board.**
The AM62x ROM never prints anything — the first UART output comes from `tiboot3`.
So wrong tiboot3 variant, macOS-partitioned SD card, or any SD card error looks
identical to a completely dead board. Before concluding hardware failure, re-flash
the SD card using `xz|dd` with the WIC image (§3) which contains the correct
HS-FS tiboot3 variant and a ROM-compatible partition table.

**Recovery via UART boot:** If SD boot never works but the chip is warm, switch
to UART boot mode (SW3/SW4 per SPRUJ51A) and use the SDK's UART-boot scripts
to push `tiboot3.bin` over the serial port. This tests the board independently
of the SD card.

### balenaEtcher fails with "writer process ended unexpectedly"

This occurred twice during the 2026-05-15 session with the LP WIC image. The
file was intact (verified with `ls -lh`). Switch to the `xz|dd` pipeline
(step 9b). This is the confirmed-working method.

### "It booted once, now it won't"

- Always `sync` before unmounting the SD card. Power-off without sync corrupts it.
- U-Boot may have saved a bad environment. At the U-Boot prompt: `env default -a; env save`
- Re-burn the golden-sd.img snapshot from step 15.

### Kernel panic: VFS unable to mount root

- Check `root=` bootarg. On SD-only boards (no eMMC), SD is `mmcblk0`, not `mmcblk1`.
- Verify from U-Boot: `mmc list`

### No login prompt after kernel boots

Linux console on AM62x is `ttyS2`. The bootarg must include:
`console=ttyS2,115200n8`

---

## What comes next

| Task | Where documented |
|---|---|
| Boot with custom kernel (SDK 11.x) | Step 9c above; step 10 in `/firmware` page |
| TFTP/NFS dev loop | Step 11 in `/firmware` page |
| Ambient DTB (`k3-am62-lp-sk-ambient.dtb`) | `workspace/device-tree/README.md`, `DEVICETREE.md` |
| JTAG / CCS debug setup | Step 8 in `/firmware` page |
| OTA with Mender | Steps 13–15 in `/firmware` page |

---

*Verified: SK-AM62-LP PROC124E2 (HS-FS), Apple Silicon Mac, 2026-05-15.*
