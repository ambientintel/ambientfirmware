# Session 2026-05-14/15 — First boot attempt with SK-AM62-LP hardware

> **Correction (2026-05-16):** The board was NOT defective. The SD card had wrong
> files — the TI SDK 11 prebuilt `tiboot3.bin` symlink is not the HS-FS variant
> required by this device, and the macOS-partitioned card may have had a ROM-
> incompatible partition table. The AM62x ROM produces zero UART output for any
> boot failure, so "chip cold + all UARTs silent" is indistinguishable from a dead
> board without this context. First boot succeeded the following day using the
> correct WIC image (SDK 12.x, `tiboot3-am62x-hs-fs-evm.bin` included).
> Do not RMA the board. Original session notes preserved below for reference.

First time with the SK-AM62-LP board on hand. Goal was first power-on with the
prebuilt SD card image per `BOOT_DAY_RUNBOOK.md`. Got the SD card and rootfs
built, but the AM62 chip never started. SD card had wrong files (wrong tiboot3
variant; macOS partition table likely also rejected by ROM).

## What got built and works

**Rootfs image (reusable):**

- `~/ti-am62x/workspace/rootfs.img` — 9GB ext4 image, fully populated with TI
  default rootfs.
- Build path: blank file via `dd`, formatted with `mke2fs -t ext4` inside
  Docker, loop-mounted, then `tar -xpf` of
  `tisdk-default-image-am62xx-lp-evm.rootfs.tar.xz` (7.3GB uncompressed — first
  4GB and 6GB attempts both ran out of space).
- Important: Docker container needs `--privileged` for loop mount. `enter.sh`
  doesn't include this flag — invoke `docker run` directly when doing rootfs
  work, or fix the script.

**Tooling on the Mac:**

- `brew install tio e2fsprogs` — `tio` is much better than `screen` for serial,
  `e2fsprogs` gives `mke2fs` for ext4 formatting on macOS.

**SD card layout (currently in the board):**

- 64GB microSD, MBR via `diskutil partitionDisk /dev/disk17 MBR 'MS-DOS FAT32' BOOT 256MB 'MS-DOS FAT32' ROOTFS R`.
- p1 (BOOT, 256MB FAT32): tiboot3.bin, tispl.bin, u-boot.img, Image,
  k3-am62-lp-sk.dtb, uEnv.txt — copied from the SDK's `prebuilt-images/am62xx-lp-evm/`.
- p2 (ROOTFS, 63GB): ext4 — `sudo dd if=$HOME/ti-am62x/workspace/rootfs.img of=/dev/rdisk17s2 bs=1m conv=fsync` (~6 min over USB).

**macOS gotcha:** `dd` does not expand `~` — use `$HOME` instead.

## Hardware identification

The SK-AM62-LP has these switches/buttons (silkscreen labels):

- **SW3 and SW4**: 8-position DIP switches — these are the **boot mode**
  switches. Match the "uSD Boot (MMC1) – 25 MHz PLL" diagram in TI's SPRUJ51A
  user guide §2.19.2.
- **SW1, SW2, SW5, SW6**: blue tactile push buttons. SW1 = power
  (toggles 2 of the 4 LEDs), SW2 = reset. SW5/SW6 likely user buttons.
- **Debug bridge**: TM4C12 (Tiva-C) USB-UART, exposes 4 channels as
  `/dev/tty.usbserial-10261240094{0,1,2,3}`.

Note: earlier session notes assumed FT4232 debug bridge — this board uses Tiva-C
instead. Channel mapping to AM62 UARTs is not documented in the runbook and
should be confirmed against the SK-AM62-LP user guide before next attempt.

## What's blocking — AM62 does not start

After full SD prep and boot mode set to SD per the TI diagram:

- 4 LEDs lit when USB-C power applied (ld5, ld6, ld8, ld10).
- SW1 toggles ld6 and ld10 (or similar pair) on/off.
- AM62 chip stays **cool** in either LED state. Chip is not executing.
- All 4 serial channels silent at 115200, 9600, and 921600 baud, with and
  without SD card, before and after pressing SW1/SW2/SW5/SW6.
- Replaced `tiboot3.bin` with the explicit `tiboot3-am62x-hs-fs-evm.bin`, no
  change. Then tried `tiboot3-am62x-gp-evm.bin`, still no change.

The chip staying cool is the key data point — if the ROM were running and just
failing to find a bootable SD, we'd still see some UART output and the chip
would be warm.

## Diagnosis — session 2026-05-15

All variables eliminated over two sessions:

| Test | Result |
|------|--------|
| Lenovo 65W USB-C brick | Cold, silent |
| iPhone 5W USB-A brick | Cold, silent |
| 5V/2.1A USB-A adapter | Cold, silent |
| Apple 20W USB-C (direct USB-C to USB-C, J13) | Cold, silent |
| All 4 Tiva-C UART channels (115200/9600/921600) | Silent |
| SD card absent | No change |
| Boot mode switches | Verified correct per SPRUJ51A §2.19.2 |
| LD8 | Lit — PD contract confirmed |

**Boot mode switches confirmed correct (SPRUJ51A Table 2-18/2-19/2-32):**
- SW3: 1=ON, 2=ON, 3=OFF, 4=OFF, 5=OFF, 6=OFF, 7=ON, 8=OFF
- SW4: 1=OFF, 2=ON, 3=OFF, 4=OFF, 5=OFF, 6=OFF, 7=OFF, 8=OFF

SW4.2=ON is required (Table 2-32: "MMC Port 1 — this bit must be set to 1").
SW3 positions 1+2=ON for 25 MHz PLL, position 7=ON for MMC/SD primary boot.

**Power setup confirmed correct:**
- Apple 20W USB-C adapter, direct USB-C to USB-C cable, J13 (UFP/SINK port)
- LD8 illuminated = TPS65988 PD contract completed, main rails up
- Board input spec: 5V–15V, 3A min — Apple 20W provides 5V/3A ✓

**Key finding from SPRUJ51A §2.3:**
- J13 = UFP (SINK only, no data) — correct port for power
- J15 = DRP (can be DFP or UFP, has USB2.0 data) — used for USB boot
- Power chain: USB-C → TPS65988 PD controller → TPS630702 Buck-Boost → 5V/3.3V rails → TPS65219 PMIC → AM62 core
- FT4232 (J17) and XDS110 (J18) are powered from their own micro-USB connections, independent of J13

**Conclusion:** LD8 lit + chip cold = TPS65988 and main rails are up, but TPS65219
is not sequencing the AM62 core rails, or the AM62 SoC itself is dead. Board is
defective.

## Next session

1. **Post to TI E2E and request RMA.** Draft is ready (see below).
2. **Optional JTAG path:** connect J18 micro-USB to Mac, install CCS, attempt
   XDS110 connection. If JTAG sees the AM62, the defect is in power sequencing.
   If JTAG is also silent, the SoC is dead.

## TI E2E post draft

**Title:** SK-AM62-LP — AM62 SoC never starts, chip stays cold, all UARTs silent

Post to: e2e.ti.com → Processors → AM62x

---

I'm attempting first boot on a new SK-AM62-LP (PCB rev PROC124E1) and the AM62
SoC never executes. The chip stays at ambient temperature regardless of boot
configuration or power source, and all four UART channels are silent.

**Hardware**
- Board: SK-AM62-LP (PROC124E1)
- Power: Apple 20W USB-C adapter, direct USB-C to USB-C cable, J13. LD8
  illuminated confirming PD contract.
- SD card: 64GB microSD, MBR, p1 = 256MB FAT32 with prebuilt boot artifacts
  from TI Processor SDK Linux 11.02.08.02, p2 = ext4 rootfs from
  `tisdk-default-image-am62xx-lp-evm.rootfs.tar.xz`

**Boot mode switches** (per SPRUJ51A §2.19.2, Tables 2-18/2-19/2-32):
- SW3: 1=ON, 2=ON, 3=OFF, 4=OFF, 5=OFF, 6=OFF, 7=ON, 8=OFF
- SW4: 1=OFF, 2=ON, 3=OFF, 4=OFF, 5=OFF, 6=OFF, 7=OFF, 8=OFF

**Symptoms**
- 4 LEDs illuminate on power-on (LD5, LD6, LD8, LD10)
- AM62 SoC cold to the touch — not drawing current
- All four Tiva-C UART channels (`/dev/tty.usbserial-102612400940` through
  `...943`) silent at 115200, 9600, and 921600 baud
- Identical behavior with and without SD card
- Identical behavior across all power sources tested

**What I've ruled out**
- Power delivery: Apple 20W, 5V/3A PD via J13, LD8 lit
- UART channel: all four monitored, all silent
- Boot media: chip cold with SD absent — not a boot device issue
- Boot mode switches: verified against SPRUJ51A tables, correct for uSD/MMC1/25MHz

**Key observation:** A cold SoC indicates the AM62 is not executing at all — not
even the boot ROM. If the ROM were running, the chip would be warm and WKUP_UART0
would show output. This points to TPS65219 not sequencing the AM62 core rails, or
a defective SoC.

**Questions:**
1. Is there a known condition where TPS65219 fails to sequence despite LD8 being lit?
2. Are there known QC issues with this batch?
3. Can you advise on RMA/replacement options?

## Open items for the runbook

- `BOOT_DAY_RUNBOOK.md` assumes FT4232 with `tty.usbmodem*` device names. This
  board has Tiva-C with `tty.usbserial-*`. Update the device-name examples and
  channel-mapping notes.
- Runbook should mention that the rootfs tarball is 7.3GB uncompressed — a 4GB
  or 6GB image will silently overflow during `tar -xp`.
- Runbook should note the `--privileged` flag requirement for the Docker
  container when doing rootfs work.
- Runbook should call out that `dd` on macOS doesn't expand `~`.
- Boot mode switch section: clarify that on the LP variant the boot mode DIP
  switches are SW3/SW4 (matching the diagram), and SW1/SW2/SW5/SW6 are
  push buttons, not DIP switches.
