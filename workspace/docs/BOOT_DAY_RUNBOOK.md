# SK-AM62-LP Boot-Day Runbook

First power-on procedure for the TI SK-AM62-LP evaluation board with firmware
built from `ambientintel/ambientfirm`.

**Target:** TI SK-AM62-LP (AM625 SoC, low-power variant)
**Host:** Apple Silicon Mac, Docker container (Ubuntu 22.04 x86_64 under QEMU)
**SDK:** TI Processor SDK Linux AM62x 11.02.08.02
**Artifacts produced by build:** `tiboot3.bin`, `tispl.bin`, `u-boot.img`, kernel image, DTBs

---

## 0. Before you touch the board — pre-flight checklist

Run through this **before** the board arrives. Every item here can be done dry.

- [ ] Identify an SD card. 8 GB minimum, Class 10 or better. A known-good card matters; flaky SD media is the #1 cause of mysterious boot failures.
- [ ] Know which host port you'll use for the SD card reader. On a Mac, a USB-C card reader will enumerate as `/dev/disk<N>`. You'll pass this through to Docker or, simpler, burn the SD card from macOS directly.
- [ ] Have a **micro-USB-B** cable ready for the serial console. J17 (FT4232 UART) is micro-USB-B. J18 (XDS110 JTAG) is also micro-USB-B. Power is USB-C into J13 or J15 — these are separate connectors.
- [ ] Install `tio` on the Mac: `brew install tio`. Preferred over `screen` (handles reconnects, no PTY issues).
- [ ] Identify the boot-mode switch bank. **SW1 is a push button** (RST+INT), not a boot mode switch. Boot mode is set by DIP switch banks **SW3** and **SW4**. Reference: SPRUJ51A Fig 2-5.
- [ ] Print or pin this runbook somewhere you can see it without scrolling while you're doing the first boot.

---

## 1. Verify build artifacts

From inside the Docker container:

```bash
cd ~/ti-am62x/workspace
ls -la deploy/   # or wherever your build drops artifacts
```

You should see, at minimum:

| File | Role | Approx size |
|---|---|---|
| `tiboot3.bin` | R5 SPL + signed TIFS firmware, loaded by ROM from SD sector 0 offset | ~300–500 KB |
| `tispl.bin` | FIT image with A53 SPL, ATF (BL31), OP-TEE (BL32), DM firmware | ~1–2 MB |
| `u-boot.img` | U-Boot proper, loaded by A53 SPL | ~1 MB |
| `Image` or `zImage` | Linux kernel | ~15–30 MB |
| `k3-am62-lp-sk.dtb` | Device tree for this board | ~50–100 KB |

If any of these are missing or zero bytes, **stop and rebuild** — do not proceed. A missing `tispl.bin` in particular will look like a dead board (ROM loads tiboot3, tiboot3 fails to find tispl, silence on UART).

Quick sanity check:
```bash
file deploy/tiboot3.bin        # should say "data"
file deploy/tispl.bin          # should say "FIT image"
file deploy/u-boot.img         # should say "u-boot legacy image"
```

---

## 2. Prepare the SD card

**Use the official LP WIC image.** Do not use macOS `fdisk` to manually partition — macOS fdisk produces unreliable partition tables that the AM62x ROM silently rejects, causing complete boot silence.

### 2a. Download the LP WIC image

Download the LP-specific image (no TI account required):
```
https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-PvdSyIiioq/12.00.00.07.04/tisdk-default-image-am62xx-lp-evm-12.00.00.07.04.rootfs.wic.xz
```

Via curl (saves as short alias used by the flash commands below):
```bash
curl -L -o ~/Downloads/tisdk-lp-evm-12.wic.xz \
  "https://dr-download.ti.com/software-development/software-development-kit-sdk/MD-PvdSyIiioq/12.00.00.07.04/tisdk-default-image-am62xx-lp-evm-12.00.00.07.04.rootfs.wic.xz"
```

Browser download saves the full filename (`tisdk-default-image-am62xx-lp-evm-12.00.00.07.04.rootfs.wic.xz`) — adjust path in flash commands below if you use the browser.

### 2b. Flash with xz|dd (recommended)

This is the confirmed-working method. balenaEtcher works on most machines but has been observed to fail on this file with "writer process ended unexpectedly" — use dd if that happens.

```bash
# Verify diskN is your SD card before running — this writes the whole disk
diskutil list
diskutil unmountDisk /dev/diskN
xz -d --stdout ~/Downloads/tisdk-lp-evm-12.wic.xz | sudo dd of=/dev/rdiskN bs=8m
```

Progress can be checked with `Ctrl-T` (macOS sends SIGINFO to dd). Expect ~5–10 minutes for a 32 GB card.

### 2b-alt. Flash with balenaEtcher

1. Install: `brew install --cask balenaetcher` (use **arm64** build on Apple Silicon)
2. Open balenaEtcher → Flash from file → select the `.wic.xz` (no need to decompress)
3. Select the SD card target
4. Flash
5. If Etcher shows "writer process ended unexpectedly" — use the `xz|dd` method above instead

### 2c. Replace boot files with SDK 11.02.08.02 prebuilts (optional)

The WIC image above ships with SDK 12.x binaries. For work that must stay on SDK 11.02.08.02, after flashing mount the FAT BOOT partition and replace:

```bash
PREBUILT=~/ti-am62x/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/prebuilt-images/am62xx-lp-evm

# HS-FS variant explicitly — board PROC124E2 is HS-FS, not plain HS or GP
cp $PREBUILT/tiboot3-am62x-hs-fs-evm.bin  /Volumes/BOOT/tiboot3.bin
cp $PREBUILT/tispl.bin                     /Volumes/BOOT/
cp $PREBUILT/u-boot.img                    /Volumes/BOOT/
cp $PREBUILT/Image                         /Volumes/BOOT/
cp $PREBUILT/k3-am62-lp-sk.dtb            /Volumes/BOOT/
cp $PREBUILT/uEnv.txt                      /Volumes/BOOT/
sync
diskutil unmountDisk /dev/diskN
```

**tiboot3 variant matters.** The prebuilt directory contains three variants:
- `tiboot3-am62x-gp-evm.bin` — GP devices only
- `tiboot3-am62x-hs-evm.bin` — HS devices only
- `tiboot3-am62x-hs-fs-evm.bin` — **use this for PROC124E2 (HS-FS)**

Using the wrong variant causes the ROM to silently reject the binary — no error, no output, board appears dead.

---

## 3. Hardware setup

1. **Set boot mode switches SW3 + SW4 for uSD boot (25 MHz PLL).** SW1 is the RST+INT push button — ignore it. Set the DIP switches as follows (SPRUJ51A Fig 2-5):

   | | sw1 | sw2 | sw3 | sw4 | sw5 | sw6 | sw7 | sw8 |
   |---|---|---|---|---|---|---|---|---|
   | **SW3** (bits 0–7) | ON | ON | OFF | OFF | OFF | OFF | ON | OFF |
   | **SW4** (bits 8–15) | OFF | ON | OFF | OFF | OFF | OFF | OFF | OFF |

   Source: SPRUJ51A Fig 2-5. SW1 is a push button (RST+INT) — do not touch.

2. **Insert the SD card** into the microSD slot.
3. **Connect a micro-USB-B cable to J17** (labeled "FTDI Micro-USB" on the board). This is the FT4232 UART console. J18 is XDS110 JTAG — **not the console**. Both connectors are micro-USB-B and look identical. J17 is the one closer to the SD card slot. Plugging into J18 by mistake produces complete silence on tio — no errors, no output, board appears dead.
4. **Do NOT connect power yet.**

---

## 4. Open the serial console

On the Mac, with the micro-USB-B cable connected to J17 (FTDI):

```bash
ls /dev/tty.usbserial-*
# J17 (FT4232) enumerates as FOUR ports — one per UART channel:
#   /dev/tty.usbserial-102612400940  — SOC_UART0  ← Linux console, use this
#   /dev/tty.usbserial-102612400941  — SOC_UART1
#   /dev/tty.usbserial-102612400942  — WKUP_UART0
#   /dev/tty.usbserial-102612400943  — MCU_UART0
# These are the confirmed port names for this board+cable on this Mac.
```

Open the Linux console port:

```bash
tio /dev/tty.usbserial-102612400940 -b 115200
```

If the port isn't found, run `ls /dev/tty.usbserial-*` — the prefix `1026124009` is tied to this FT4232 chip and should be stable across reboots.

Serial settings: **115200 8N1, no flow control.**

Once open: you should see nothing (the board isn't powered yet). That's the correct state.

---

## 5. Power on and watch the boot chain

Connect a USB-C cable to J13 or J15 (5–15V, 3A minimum — use a USB-C PD adapter or laptop port). Expected boot sequence, in order:

### Stage 1 — ROM → tiboot3 (R5 SPL)
You should see within ~1 second:
```
U-Boot SPL 2024.xx-ti-... (date) +0000
SYSFW ABI: 3.1 (firmware rev 0xNNNN '23.0.x--v09....')
SPL initial stack usage: NNN bytes
Trying to boot from MMC2
```
**If you see nothing here:** ROM didn't find or couldn't read `tiboot3.bin`. See Troubleshooting §A.

### Stage 2 — tiboot3 loads tispl.bin
```
Loading Environment from MMC... OK
...
Loading fit image from MMC
```
**If it hangs here:** DDR training likely failed, or `tispl.bin` is missing/corrupt. See Troubleshooting §B.

### Stage 3 — A53 SPL hands off to U-Boot
After DDR init you'll see a second U-Boot banner — this time on the A53:
```
U-Boot 2024.xx-ti-... (date) +0000
CPU: AM62X SR1.0 HS-FS
Model: Texas Instruments AM625 SK LP
...
Hit any key to stop autoboot:  3
```
**If it hangs here:** `u-boot.img` is missing or OP-TEE/ATF handoff failed. See Troubleshooting §C.

### Stage 4 — U-Boot autoboots kernel
Let autoboot proceed (or hit a key to get a U-Boot prompt if you want to poke around). You should see:
```
Booting kernel from legacy image at 82000000 ...
Starting kernel ...

[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x410fd034]
[    0.000000] Linux version 6.x.x-ti-...
...
```
**If kernel panics or hangs:** See Troubleshooting §D.

### Stage 5 — Rootfs mounts, systemd starts
```
[    N.NNNNNN] EXT4-fs (mmcblk1p2): mounted filesystem ...
Welcome to TI SDK ...
am62xx-evm login:
```
**Default login:** `root` (no password, for the stock TI rootfs).

---

## 6. Success criteria

First boot is "working" when **all** of these are true:
- [ ] Login prompt appears on UART0.
- [ ] `uname -a` shows your built kernel version.
- [ ] `cat /proc/device-tree/model` returns `Ambient Intel AM62x-LP` (ambient DTB) or `Texas Instruments AM62x LP SK` (stock DTB).
- [ ] `dmesg | grep -i error` returns nothing alarming (a few benign warnings about unsupported peripherals are normal).
- [ ] `ls /sys/class/net` shows at least `lo` and `eth0`.

Capture the full boot log on first success:
```bash
# From the host, before connecting:
tio /dev/tty.usbserial-XXXXXXXXXXXX40 -b 115200 --log-file first-boot.log
```
Commit `first-boot.log` to the repo as a reference for future regressions.

---

## 7. Troubleshooting

### §A. Silence on UART (no tiboot3 banner)

| Symptom | Likely cause | Fix |
|---|---|---|
| Nothing at all on serial | **Cable in J18 instead of J17** | J17 = FTDI UART (console). J18 = XDS110 JTAG. Both are micro-USB-B. Move cable to J17. |
| Nothing at all on serial | Wrong UART port | Use port ending in `40` (SOC_UART0) |
| Nothing at all on serial | macOS fdisk SD card | Re-flash with `xz\|dd` + LP WIC image (§2b) |
| Nothing at all on serial | Wrong tiboot3 variant | Use `tiboot3-am62x-hs-fs-evm.bin` for PROC124E2 |
| Nothing at all on serial | Boot mode switches wrong | Verify SW3/SW4 against SPRUJ51A Fig 2-5 |
| Nothing at all on serial | Power not applied | Check power LED on board |
| Garbage on serial | Wrong baud rate | Confirm 115200 8N1 |
| `tiboot3` banner then nothing | `tispl.bin` missing from FAT | Re-copy and `sync` |

**Note:** The AM62x ROM produces **zero UART output itself**. First output comes from `tiboot3` (R5 SPL). If the ROM cannot load `tiboot3.bin` — bad SD card, wrong tiboot3 variant, wrong boot mode — the result is complete silence. Do not assume the board is dead.

**Recovery path:** AM62x supports UART boot as fallback. If SD boot never works, switch to UART boot mode via SW3/SW4 and use the SDK's UART-boot scripts to push `tiboot3.bin` over the console. This confirms whether the board hardware is alive independent of SD card issues.

### §B. Hang between "Trying to boot from MMC2" and second banner

Almost always DDR-related. Things to check:
- `tispl.bin` was built with the **LP variant** DDR config, not the plain SK. The LP board has different DDR timings. In the SDK, this means the k3-am62-lp-sk-ddr config was selected during U-Boot build. Rebuild if you're not sure.
- Rebuild with `DEBUG=1` on SPL to get more verbose DDR training output.

### §C. A53 U-Boot banner never appears

The R5 SPL loaded tispl.bin but something inside it failed. Usually one of:
- ATF (BL31) didn't start. Check tispl.bin was built with ATF included.
- OP-TEE (BL32) crashed on init. Less common on a plain dev board; more common if you've modified OP-TEE.
- DM (device manager) firmware missing. The R5 needs a valid DM binary — the SDK bundles this.

Rebuild the full boot chain cleanly and try again before digging deeper.

### §D. Kernel boot failures

| Symptom | Likely cause | Fix |
|---|---|---|
| "Bad Linux ARM64 Image magic!" | DTB copied as kernel or vice versa | Check files on FAT partition |
| Kernel loads, hangs at "Starting kernel..." | Wrong DTB | Confirm `k3-am62-lp-sk.dtb` (not plain `sk`) |
| Panic: VFS: Unable to mount root fs | rootfs partition wrong / missing | Check `root=/dev/mmcblk1p2` in bootargs; verify partition exists and is ext4 |
| Boots but no login prompt | Console on wrong UART | Check `console=ttyS2,115200n8` in bootargs (AM62x main UART0 = ttyS2 in Linux) |

The `mmcblk1` vs `mmcblk0` thing catches people — eMMC enumerates before SD. On SK boards with no eMMC populated, SD may be `mmcblk0`. Check `ls /dev/mmcblk*` from a U-Boot shell (`mmc list`) if unsure.

### §E. Wrong or stock DTB despite grub.cfg devicetree directive

| Symptom | Likely cause | Fix |
|---|---|---|
| `cat /proc/device-tree/model` shows stock TI string | DTB file not present on BOOT FAT partition | Copy the DTB to the BOOT partition root; verify path matches grub.cfg exactly |
| `devicetree /name.dtb` in grub.cfg; stock model persists | GRUB silently fell back — file not found | `ls /run/media/boot-mmcblk1p1/` to confirm the file exists |
| Changed `fdtfile` in uEnv.txt; no effect | `fdtfile` only applies to U-Boot distro boot, not GRUB EFI path | Use grub.cfg `devicetree` directive instead |

**How ambient DTB boot works on this board:** `EFI/BOOT/grub.cfg` must contain `devicetree /k3-am62-lp-sk-ambient.dtb` AND the file must exist at the root of the FAT BOOT partition. GRUB passes it to the kernel. U-Boot's `fdtfile` variable in `uEnv.txt` is irrelevant in this boot path.

### §F. "It booted once, now it won't"

- Card may have corrupted on power-off. Re-burn.
- Did U-Boot save an environment to the card? `env default -a; env save` from U-Boot prompt clears it.
- Did you `sync` before unmounting the card? Always `sync`.

---

## 8. Quick-reference card (tape to monitor)

```
SERIAL:  J17 (FTDI Micro-USB), 115200 8N1, /dev/tty.usbserial-*40 (SOC_UART0)
JTAG:    J18 (XDS110 Micro-USB)
POWER:   USB-C into J13 or J15 (5-15V, 3A min)
BOOTMODE: SW3=ON ON OFF OFF OFF OFF ON OFF (sw1,2,7 ON)
          SW4=OFF ON OFF OFF OFF OFF OFF OFF (sw2 ON only)
          Source: SPRUJ51A Fig 2-5
LOGIN:   root / (no password)
UART:    Linux console = ttyS2
ROOTFS:  /dev/mmcblk1p2 (SD), p1 is FAT boot
TIBOOT3: use tiboot3-am62x-hs-fs-evm.bin for PROC124E2 (HS-FS device)
BOOT CHAIN: ROM → tiboot3.bin → tispl.bin → u-boot.img → Image + dtb → rootfs
```

---

## 9. After first successful boot

Immediate next steps, in order of value:
1. **Commit `first-boot.log`** to the repo. You'll want this baseline.
2. **Record the exact boot timing** (`dmesg` timestamps). Regressions in boot time are a great early warning.
3. **Verify USB, Ethernet, GPIO LED.** Anything that's easy to poke from the shell — poke it. Each thing that works now is one thing you don't have to debug later.
4. **Snapshot the working SD card image.** `sudo dd if=/dev/diskN of=golden-sd.img bs=1m` then compress. When you break something later, you can get back to "known good" in 5 minutes.

---

---

## 10. JTAG Debug Loop (Step 14)

Connects the onboard XDS110 (J18) to OpenOCD for hardware breakpoints and register access, even before the OS boots.

### Hardware

J17 (UART) and J18 (JTAG) are independent. Connect only what the task requires.

**Stage 1 — JTAG verification only (minimum cables)**

J17 is **not needed** to run OpenOCD and confirm A53 detection.

| Cable | Connector | Purpose |
|-------|-----------|---------|
| USB-C | J13 | Power |
| micro-USB-B | J18 | XDS110 JTAG |

Power the board first (USB-C into J13), then plug J18. J18 enumerates as a Texas Instruments USB device — **no `/dev/tty` entry appears** for J18. Both J17 and J18 are micro-USB-B and look identical.

**Stage 2 — JTAG + console (kernel debug)**

Add J17 when you need serial output alongside JTAG: panic traces, printk, interactive U-Boot.

| Cable | Connector | Purpose |
|-------|-----------|---------|
| USB-C | J13 | Power |
| micro-USB-B | J17 | FT4232 UART → 4× `/dev/tty.usbserial-*` |
| micro-USB-B | J18 | XDS110 JTAG |

```bash
# Terminal A — console
tio /dev/tty.usbserial-102612400940 -b 115200

# Terminal B — JTAG
openocd -f workspace/jtag/am625-xds110.cfg
```

### Install OpenOCD (Mac, once)

```bash
brew install openocd   # → 0.12.0
```

### Start OpenOCD

```bash
# From the ambientfirmware/ repo root:
openocd -f workspace/jtag/am625-xds110.cfg
```

Expected output:
```
Info : XDS110: connected
Info : XDS110: firmware version ...
Info : [am625.cpu.a53.0] Cortex-A53 r0p4 processor detected
...
Info : Listening on port 3333 for gdb connections
```

### Quick verification (no GDB)

```bash
# Second terminal while OpenOCD is running:
nc localhost 4444

# In the OpenOCD console:
targets                         # list targets and state
am625.cpu.a53.0 halt            # halt core 0
am625.cpu.a53.0 reg pc          # read PC
mdw 0x88000000 4                # DTB magic check: first word = 0xedfe0dd0
am625.cpu.a53.0 resume
```

### GDB (kernel debug, from Docker container)

Port 3334 = `am625.cpu.a53.0` (first A53 — kernel debug target).
Container reaches Mac host at `host.docker.internal`.

```bash
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
aarch64-oe-linux-gdb vmlinux -x /workspace/jtag/gdb-kernel.init
```

### Critical notes

- Interface: `interface/xds110.cfg` — **not** `interface/ti_xds110.cfg` (old name, doesn't exist in 0.12.0)
- Target: `ti_k3.cfg` with `set SOC am625` — **not** `ti_am625.cfg` (AM625 is K3 family)
- Port 3333 = sysctrl (M3), **3334 = a53.0** (kernel debug), 3338 = main0_r5.0 (R5F)
- See `workspace/jtag/README.md` for full port map and debug use cases

---

*This runbook is a living document. Every surprise on first boot should either be resolved by following it, or result in an edit to it.*
