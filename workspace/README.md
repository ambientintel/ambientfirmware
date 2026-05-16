# TI AM62x + IWR6843AOP Firmware

Custom PCB integrating TI AM62x (A53 SoC, via Octavo OSD62x-PM SiP) and TI IWR6843AOP (60 GHz mmWave radar, antenna-on-package). Target application: fall detection in commercial senior-living facilities (memory care, assisted living, independent living). Device lifetime is 5–7 years; OTA, audit, and signing requirements are real.

Application layer lives in a separate repo: github.com/ambientintel/ambientapp (Python 3.11, systemd, Mender-managed deployment).

---

## Hardware targets

### Dev board — TI SK-AM62-LP

TI low-power AM62x starter kit. Primary bring-up and software validation platform.

- SoC: AM625 — quad Cortex-A53 @ 1.4 GHz, Cortex-M4F, Cortex-R5F
- Memory: LPDDR4
- Debug console: onboard FT4232 USB-UART bridge, micro-USB J17
- JTAG: onboard XDS110, micro-USB J18
- Radar for early integration: IWR6843AOP via Mistral pre-built module on Raspberry Pi (USB-serial bridge). Production uses raw silicon.

### Custom board

Two-island design. Both islands on one PCB.

**Radar island** — copy-paste from TI's published IWR6843AOPEVM Altium files. Do not re-route or substitute passives inside this block. Analog rail ripple spec is <100 µV RMS; passive values are not fungible.

Components (frozen, from TI EVM):
- IWR6843AOP
- LP87745 PMIC
- 40 MHz crystal + load caps
- QSPI flash footprint — **DNI** (host-fed boot mode; populate only for standalone radar debug)
- VPP eFuse circuit, NRESET/SOP/WARM_RESET circuitry, power sequencing

**AM62 island** — Octavo OSD62x-PM SiP + support components. This is our design work.

The OSD62x-PM (OSD6254-1G-IPM) integrates AM6254 + 1 GB DDR4 + passives in a 9×14 mm 500-ball 0.5 mm pitch BGA. It eliminates discrete LPDDR4 routing. PMIC, oscillators, boot flash, and decoupling are still on the carrier board.

Components:
- Octavo OSD62x-PM (AM6254 + 1 GB DDR4)
- TPS65219 PMIC — use AM62 pre-programmed NVM OPN per Octavo power app note
- OSPI/QSPI boot flash
- 16 GB eMMC
- 25 MHz crystal for MCU_OSC0, 32.768 kHz crystal for WKUP_LFOSC0
- Reset supervisor (TPS3839 class) + SYSBOOT strap resistors
- Wi-Fi + BLE combo module (pre-certified; Murata 1YN or CYW43xx class — final selection pending TI SDK driver check)
- 20-pin cTI JTAG header (external XDS110; no onboard emulator)
- Debug UART header (MAIN_UART0, 4-pin 2.54 mm)

Stripped from SK-AM62-LP reference: dual GbE PHYs, HDMI, audio codec, M.2, USB-C PD, EXP/MCU/PRU connectors, LVDS display, CSI camera, IO expanders (TCA6424 × 2), onboard XDS110.

**Power isolation:** separate PMICs, no shared rails. AM62 DDR refresh and switching regulators generate noise in radar-sensitive bands. Grounds joined at a single point near the radar.

**Boot model:** host-fed. AM62 pushes radar firmware binary over SPI at boot using TI's SBL protocol. Radar QSPI footprint is DNI on production boards.

**Interface boundary (radar ↔ AM62):** UART at 921600 baud (primary data stream), SPI (firmware transfer + reserved high-BW runtime path), NRESET / SOP[2:0] / NERROR_OUT. All signals 3.3V — LP87745 IO rail must stay at 3.3V or level shifters are required on every crossing net. Full net table: `../docs/interfaces-am62-radar.md`.

**Fab process:** 8-layer FR-4 High Tg, ENIG, controlled impedance per TI EVM spec. Likely 10-layer with microvias once OSD62x-PM escape routing is evaluated (0.5 mm pitch, 500 balls). Confirm final stackup against Octavo OSD62x-PM Layout Guide before sending to fab.

**RF note:** IWR6843AOP is antenna-on-package. No millimeter-wave signal anywhere on the PCB. "RF layout" on this board means clean power rails, the 40 MHz crystal circuit, ground pour under the package, and respecting the 3D antenna keepout volume above the package. It is mixed-signal layout, not microwave PCB engineering.

---

## Repo layout

Paths below are relative to `workspace/` (this directory), which is bind-mounted at `/workspace` inside the build container.

```
workspace/                              ← bind-mounted at /workspace in container
├── README.md                           ← this file
├── CLAUDE.md                           ← full project reference: conventions, lessons, open decisions
├── SETUP-NOTES.md                      ← container setup history
├── device-tree/
│   ├── Makefile                        ← out-of-tree DTB build glue (idempotent)
│   ├── README.md                       ← device tree build flow details
│   └── k3-am62-lp-sk-ambient.dts      ← ambient board overlay (includes SK-AM62-LP base)
├── docs/
│   ├── BOOT_DAY_RUNBOOK.md            ← first power-on procedure for SK-AM62-LP
│   └── DEVICETREE.md
└── sdk/                                ← gitignored; install separately
    └── ti-processor-sdk-linux-am62xx-evm/
        ├── board-support/
        │   ├── ti-linux-kernel-6.12.57+git-ti/
        │   ├── u-boot-*/
        │   └── prebuilt-images/am62xx-lp-evm/
        ├── linux-devkit/               ← cross sysroot — treat as read-only
        ├── k3r5-devkit/                ← R5F toolchain
        └── kernel-env.sh              ← use this for kernel/U-Boot builds (see below)
```

Repo root (`../` from here):

```
ti-am62x/
├── Dockerfile                          ← Ubuntu 22.04 x86_64 build container
├── enter.sh                            ← launch / attach to container
├── docs/
│   ├── adr/ADR-0002-am62-soc-choice.md
│   ├── interfaces-am62-radar.md        ← authoritative AM62↔radar net spec
│   └── session-findings-2026-04-18.md ← locked decisions: BOM, runtime, rootfs, OTA
└── workspace/                          ← this directory
```

---

## Build environment setup

Host: macOS Apple Silicon. Build container: Ubuntu 22.04 x86_64 under Docker Desktop with QEMU emulation.

**First: disable Rosetta.** Docker Desktop → Settings → General → uncheck "Use Rosetta for x86_64/amd64 emulation on Apple Silicon." Rosetta has a `.bss` size calculation bug that produces silently corrupt binaries. U-Boot SPL is the visible symptom — it links cleanly but fails at runtime. QEMU emulation only.

### Enter the container

From the Mac:

```sh
~/ti-am62x/enter.sh
```

`workspace/` is bind-mounted at `/workspace`. Edits in the container are immediately visible on the Mac and to GitHub Desktop.

### One-time container package installs

U-Boot 2025.01 requires packages missing from a minimal Ubuntu 22.04 image:

```sh
apt-get install -y swig libgnutls28-dev python3-yaml yamllint \
    libssl-dev python3-dev python3-setuptools
```

Without these: cryptic Python import errors or missing gnutls linker failures mid-build.

### SDK install

SDK is not in the repo (too large). Install TI Processor SDK Linux AM62x 11.02.08.02 into `workspace/sdk/`. The SDK installer is a self-extracting `.run` file from ti.com.

---

## Key build commands

All commands run inside the container at `/workspace` unless noted.

### Environment setup for kernel / U-Boot builds

```sh
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
```

This sets `PATH`, `ARCH=arm64`, and `CROSS_COMPILE=aarch64-oe-linux-` only. Do **not** source `linux-devkit/environment-setup` for kernel or U-Boot builds — it sets `CC`, `CFLAGS`, and `CPATH` to aarch64 sysroot paths and breaks `HOSTCC`, causing confusing failures in `scripts/` and `tools/`.

For userspace application cross-compilation, **do** source `linux-devkit/environment-setup` — that is what it is for. Never mix the two in the same shell.

### Kernel

```sh
cd /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/ti-linux-kernel-*/

make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- ti_arm64_prune.config
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- -j$(nproc) Image dtbs
```

Full build: 45–90 min under QEMU on Apple Silicon. The SDK top-level Makefile defaults to `MAKE_JOBS=1` — always override with `-j$(nproc)` or `MAKE_JOBS=$(nproc)` or the build takes ~8× longer than necessary.

Output: `arch/arm64/boot/Image` (~22 MB), `arch/arm64/boot/dts/ti/k3-am62-lp-sk.dtb` (~65 KB).

### U-Boot

```sh
# source kernel-env.sh first, not linux-devkit/environment-setup
cd /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/u-boot-*/
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- am62x_evm_a53_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- -j$(nproc)
```

Produces `tiboot3.bin`, `tispl.bin`, `u-boot.img`.

### Custom device tree (ambient board overlay)

```sh
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
cd /workspace/device-tree
make build KERNEL_SRC=$KERNEL_SRC
```

Produces `$KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb`. The Makefile copies the DTS into the kernel tree, registers it in the kernel's DT Makefile via exact-line `awk` insertion (anchored on the stock `k3-am62-lp-sk.dtb` entry), then invokes `make dtbs`. Idempotent — safe to re-run.

The stock `k3-am62-lp-sk.dtb` remains the boot default. Switch to the ambient DTB via `fdtfile` env var or `extlinux.conf` when ready.

**Naming:** TI uses `k3-am62-lp-sk` (not `k3-am625-sk-lp`). The wrong order does not exist in the kernel tree; the C preprocessor fails before DTC runs if the `#include` path is wrong.

**Production DTB note:** The custom board uses OSD62x-PM, which has its own DDR config. The production DTB must pull the OSD62x-PM DDR device-tree configuration from Octavo (github.com/octavosystems/osd62-pm-ddr), not the SK-AM62-LP DDR settings.

---

## Current status

- [x] Docker Ubuntu 22.04 x86_64 container set up (QEMU emulation, Rosetta OFF)
- [x] TI Processor SDK Linux 11.02.08.02 installed
- [x] Cross-toolchain verified — aarch64-oe-linux-gcc 13.4
- [x] Kernel + DTB build succeeded (Image ~22 MB, k3-am62-lp-sk.dtb ~65 KB)
- [x] U-Boot compiled (tiboot3.bin, tispl.bin, u-boot.img)
- [x] Custom DTB build flow validated end-to-end (k3-am62-lp-sk-ambient.dtb)
- [x] IWR6843AOP prototyped on Raspberry Pi via Mistral module
- [x] Custom board path locked: Path A (raw silicon, TI IWR6843AOPEVM Altium as radar island base)
- [x] AM62 island SoC locked: Octavo OSD62x-PM — ADR-0002, 2026-04-18
- [x] BOM, runtime, rootfs, OTA decisions locked — session-findings-2026-04-18.md
- [x] AM62 ↔ radar interface spec written — docs/interfaces-am62-radar.md
- [ ] SK-AM62-LP hardware received (on order)
- [ ] First boot with prebuilt SD card image — see docs/BOOT_DAY_RUNBOOK.md
- [ ] First boot with custom kernel
- [ ] TFTP/NFS dev loop set up
- [ ] End-to-end smoke test: radar → UART → ambientapp parser → fall detector → LogPublisher
- [ ] Pin mux spreadsheet against OSD62x-PM ball map (requires Octavo OSD62x-PM to AM62x Pin Mapping app note)
- [ ] Concrete MAIN_UART / MAIN_SPI / GPIO pin assignments — add to docs/interfaces-am62-radar.md after EVM arrives
- [ ] Wi-Fi/BLE module final selection (TI SDK driver maturity check pending)
- [ ] Mender signing keypair generated and stored
- [ ] Radar firmware path decision (TI OOB vs mmWave SDK vs custom)
- [ ] Production Yocto image with Mender A/B integration
- [ ] Rootfs finalized (deferred until BOM stabilizes)

---

## Open decisions

In priority order. Each blocks work downstream.

**1. Wi-Fi/BLE module.** Murata 1YN (NXP IW416) vs CYW43xx class. Blocks schematic Wi-Fi integration. Requires TI SDK driver maturity check before selection. Does not block AM62/radar bring-up.

**2. Radar firmware path.** TI OOB demo / mmWave SDK / custom firmware. Defer until SK-AM62-LP is up and the current people-tracking firmware can be tested end-to-end through ambientapp. OOB is probably insufficient if radar handles inference.

**3. Radar inference scope.** The hardware bet is that IWR6843AOP's C674x DSP + HWA handles inference; AM62 A53 quad handles orchestration, networking, and OTA only. Needs validation against actual workload before the fall detector model is designed. If the decision flips to AM62A for ML, ADR-0002 is invalidated (OSD62x-PM is AM625-only).

---

## Key reference documents

| Path | Contents |
|---|---|
| `CLAUDE.md` | Full project reference: build conventions, device tree details, custom board architecture, lessons learned, all open decisions |
| `docs/BOOT_DAY_RUNBOOK.md` | First power-on procedure for SK-AM62-LP |
| `device-tree/README.md` | Custom DTB build flow details |
| `../docs/interfaces-am62-radar.md` | AM62 ↔ IWR6843AOP net-level interface spec |
| `../docs/session-findings-2026-04-18.md` | Locked decisions: BOM, Python 3.11 + systemd runtime, Yocto rootfs, Mender hosted A/B OTA |
| `../docs/adr/ADR-0002-am62-soc-choice.md` | AM62 SoC selection: Octavo OSD62x-PM over raw AM625 |
