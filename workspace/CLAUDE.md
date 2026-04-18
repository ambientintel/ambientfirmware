# TI AM62x + IWR6843AOP Firmware Project

## Project scope

Custom PCB integrating TI AM62x (A53 SoC) + TI IWR6843AOP (60 GHz mmWave radar with antenna-on-package). SK-AM62-LP is the development platform; IWR6843AOP has been prototyped against Mistral's pre-built module on a Raspberry Pi. Custom board design is underway with the TI-published IWR6843AOPEVM Altium files as the starting point for the radar section.

## Hardware target

**Dev board:** TI SK-AM62-LP (low-power AM62x starter kit)
- SoC: AM625 — quad Cortex-A53 @ 1.4 GHz + Cortex-M4F + Cortex-R5F
- Memory: LPDDR4
- Debug console: onboard FT4232 USB-UART bridge via micro-USB (J17 on board)
- JTAG: onboard XDS110 via separate micro-USB (J15)

**Radar prototyping:** IWR6843AOP via Mistral pre-built module on Raspberry Pi (early testing only; production uses raw silicon on custom board).

**Custom board:** integrates AM625 + IWR6843AOP. See "Custom board architecture" below.

## Reference docs

- `workspace/docs/BOOT_DAY_RUNBOOK.md` — First power-on procedure for SK-AM62-LP. Covers SD card prep, serial console setup, expected output at each boot stage, and troubleshooting.
- `workspace/device-tree/README.md` — Custom device tree build flow.

## Host build environment

- Host OS: macOS (Apple Silicon)
- Build container: Ubuntu 22.04 x86_64 under Docker Desktop (QEMU emulation, Rosetta OFF)
- Workspace bind mount: `~/ti-am62x/workspace` (Mac) ↔ `/workspace` (container)
- Enter container: `~/ti-am62x/enter.sh`
- Git workflow: edits happen in the container, commits and pushes happen in GitHub Desktop on the Mac (the bind mount makes container edits visible to the host).

## SDK

- Version: TI Processor SDK Linux AM62x 11.02.08.02 (2026 LTS)
- SDK root: `/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/` (in container)
- On Mac: `~/ti-am62x/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/`
- Kernel: `board-support/ti-linux-kernel-6.12.57+git-ti/`
- U-Boot: `board-support/u-boot-*/`
- Prebuilt images: `board-support/prebuilt-images/am62xx-evm/`
- Cross toolchain (A53): `aarch64-oe-linux-gcc 13.4` in `linux-devkit/sysroots/x86_64-arago-linux/usr/bin/aarch64-oe-linux/`
- R5F toolchain: `k3r5-devkit/`

## Build conventions

### Kernel and U-Boot

Do NOT source `linux-devkit/environment-setup` — it pollutes CPATH/CC/CFLAGS with aarch64 paths and breaks HOSTCC. Instead, source the project helper:

```
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
```

This sets `PATH`, `ARCH=arm64`, `CROSS_COMPILE=aarch64-oe-linux-` without contaminating HOSTCC.

Standard kernel build:

```
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

Out-of-tree DTS lives at `workspace/device-tree/k3-am62-lp-sk-ambient.dts`. It `#includes` the stock `k3-am62-lp-sk.dts` and overrides only `compatible` and `model`. Ambient-specific peripherals (sensor nodes, custom pinmux) get added below the root node as new content lands.

Naming convention: TI uses `am62-lp-sk` (SoC family + LP variant), not `am625-sk-lp`. The earlier wrong name produced a non-existent include path. New ambient board files must follow TI's convention to keep includes resolvable.

Build flow: `workspace/device-tree/Makefile` is build glue, not a kernel Makefile. It copies the DTS into `$(KERNEL_SRC)/arch/arm64/boot/dts/ti/`, registers a new line in the kernel's DT Makefile via awk exact-line insertion (anchored on the stock `k3-am62-lp-sk.dtb` entry), then invokes `make dtbs` in the kernel tree. Idempotent — safe to re-run. Validates the anchor line exists in the kernel Makefile up front, so future SDK format changes fail loudly rather than silently no-op.

```
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
cd /workspace/device-tree
make build KERNEL_SRC=$KERNEL_SRC
# produces $KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb
```

Stock `k3-am62-lp-sk.dtb` remains the boot default. Ambient DTB gets selected via `fdtfile` env var or `extlinux.conf` once we're ready to switch.

## Conventions / don'ts

- Don't modify `linux-devkit/` — that's the sysroot, treat as read-only
- Kernel changes: create patches in a dedicated `patches/` dir rather than committing directly to the TI kernel tree
- Device tree overlays preferred over modifying base `.dts` files
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
- [x] IWR6843AOP prototyped on Raspberry Pi via Mistral module
- [x] Path A committed for custom board (raw silicon, TI Altium source)
- [ ] SK-AM62-LP hardware received (on order)
- [ ] First boot with prebuilt SD card image
- [ ] First boot with custom kernel
- [ ] TFTP/NFS dev loop set up
- [ ] Radar boot mode decision (see Open decisions)
- [ ] AM62 vs AM62A decision (see Open decisions)
- [ ] Connectivity / runtime / OTA decisions (see Open decisions)
- [ ] Rootfs decision (deferred until BOM stabilizes)

---

## Custom board architecture

### Path decision: Path A — raw silicon, TI Altium files as source

Path A uses TI's published Altium files for the IWR6843AOPEVM as the starting point for the radar section of our custom board. Path B (Mistral pre-built module soldered as a component) was considered and rejected — Path A gives volume cost optimization and full control.

### Key insight: Path A is lower-risk than it sounds

The IWR6843AOP is antenna-on-package. All 60 GHz RF is inside the chip. There is no millimeter-wave signal anywhere on our PCB. "RF layout" for this board collapses to: clean power rails, the 40 MHz crystal circuit, ground pour under the package, and respecting the 3D antenna keepout volume above the package. This is careful mixed-signal layout, not microwave PCB engineering.

This framing matters because an earlier design conversation overstated the RF risk. Future sessions should not reintroduce that framing.

### Two chip islands

**Radar island (copy-paste from TI Altium, frozen):**
- IWR6843AOP
- LP87745 PMIC (TI-specified, tight ripple requirements)
- 40 MHz crystal + load caps
- QSPI flash (pending boot-mode decision)
- VPP eFuse circuit
- NRESET / SOP / WARM_RESET circuitry
- Power sequencing
- Ground pour geometry and controlled-impedance traces per EVM fab notes

Do not re-route inside this block. Do not substitute passive values. The RF rail ripple specs are tight (sub-100 µV RMS at some frequencies to hit -105 dBc spurs); small changes have real consequences.

**AM62 island (our design work):**
- AM62x SoC (chip variant pending — see Open decisions)
- LPDDR4 (16-bit, 16Gb, matching SK-AM62-LP reference)
- eMMC (size TBD, 8–32 GB range)
- OSPI boot flash
- TPS65219 PMIC
- Reset / boot mode circuitry
- 25 MHz main crystal + 32.768 kHz RTC
- 20-pin cTI JTAG header (external XDS110 probe, no onboard emulator)
- Debug UART header

**Stripped from SK-AM62-LP reference:** dual gigabit PHYs, HDMI, audio codec + mic/headphone, M.2, USB-C PD, all EXP/MCU/PRU connectors, WLAN/BT, LVDS display, CSI camera, IO expanders (TCA6424 × 2), onboard XDS110 emulator.

**Power isolation:** separate PMICs for radar and AM62 with no shared rails, even where voltages match. AM62 DDR refresh, A53 clock transitions, and switching regulators generate noise in exactly the bands the radar cares about. Grounds joined at a single point near the radar.

### Interface boundary (radar ↔ AM62)

Small net list crossing the island boundary. Short, isolated runs across the ground stitch.

| Net | Direction | Purpose |
|-----|-----------|---------|
| UART TX/RX | bidirectional | Primary command + data link (~921.6 kbaud) |
| SPI (CLK, MOSI, MISO, CS) | bidirectional | Higher-bandwidth path, reserved for future |
| SPI_HOST_INTR | radar → AM62 | "I have data" interrupt, GPIO on AM62 |
| NRESET | AM62 → radar | AM62 holds radar in reset until needed |
| SOP[2:0] | AM62 → radar | Boot mode strapping, or pulled to fixed values if committed |
| NERROR_OUT | radar → AM62 | Open-drain, GPIO on AM62 with pull-up |

UART is primary for now. Wire SPI + SPI_HOST_INTR at the schematic level regardless — cheap insurance against a future bandwidth decision.

### Fab process targets

From IWR6843AOPEVM fab notes, carried forward unchanged for the radar section and confirmed compatible with AM62 + LPDDR4 on the AM62 section:

- 8 layers, FR-4 High Tg, 64 mil ±10% thickness
- ENIG surface finish
- 18 mil min via, 3.5 mil min trace/clearance
- UL94-V0, ANSI IPC-A-600F Class 2 (Class 3 optional)
- Controlled impedance: 50 Ω microstrip, 100 Ω edge-coupled diff (LVDS/RGMII/USB), 90 Ω diff (USB), 120 Ω diff (CAN-FD), 50 Ω stripline
- Bare-board electrical test required

**Open:** consider 10 layers for dedicated DDR routing + power integrity. Cost delta usually small, worth pricing.

**Mechanical:** AoP antenna keepout is absolute and 3-dimensional — applies to PCB, enclosure, and any material in front of the radar. Whatever sits in front of the AoP becomes part of the antenna.

---

## Open decisions

Listed in priority order. Each blocks work downstream.

### 1. Radar boot mode

**Autonomous QSPI** (TI default): radar boots from its own flash, AM62 talks to it post-boot. Two OTA targets to manage.

**Host-fed from AM62 over SPI:** radar omits QSPI flash, AM62 pushes image on reset release. Single source of truth for radar firmware. Radar can't start until AM62 has booted far enough to feed it.

Decision affects the radar island BOM (QSPI present or not) and the OTA architecture. Lean toward host-fed for deployed product, but needs to be locked before schematic capture on the radar island completes.

### 2. AM62 vs AM62A

Plain AM62x: A53-only. No NPU, no DSP.
AM62A: adds C7x DSP + MMA accelerator. Same SDK family, mostly pin-compatible footprint.

Relevant because "heavy ML inference on radar features" was the original workload answer. But the radar's own C674x DSP (600 MHz) + R4F (200 MHz) + HWA can host meaningful classifiers, which would push inference back onto the radar and reduce AM62 ML load to near zero.

Decision interacts with #3 and can't really be made until we know where inference runs. Plan: prototype ML workload on SK-AM62-LP first, revisit before committing to the custom board's SoC choice.

### 3. BOM — three unanswered questions

**Connectivity:** wired Ethernet / Wi-Fi / BLE / cellular mix. Drives schematic, antenna count, certification scope.

**App runtime:** native binary / Python / containers / Node. Drives rootfs and filesystem size.

**OTA strategy:** A/B partitions / delta updates / container pull / full image. Drives partition layout, bootloader config, update infrastructure.

Implicit fourth question: fleet management (how many devices, SSH vs agent, observability).

### 4. Rootfs (Buildroot / trimmed Yocto / tisdk default)

Deferred. Honest framing: with ML target, model shape, and update strategy all open, picking a minimal production rootfs now would actively get in the way of the research the rootfs is supposed to support.

**Plan:** research rootfs now (tisdk default or close), production rootfs decided after BOM stabilizes. Two artifacts, deliberate handoff between them.

## Radar workload shape (as of this writing)

- Firmware option: potentially TI OOB demo / mmWave SDK / custom — still evaluating
- Radar → AM62 link: UART initially (~921.6 kbaud)
- ML inference target: undecided, may run partially on radar
- Model shape: research-phase, unknown
- Model update strategy: undecided

---

## Lessons learned

### Rosetta bss_size bug — disable Rosetta in Docker Desktop

Docker Desktop's Rosetta x86_64 emulation has a bug where `.bss` section sizes are miscalculated during linking, producing silently corrupt binaries (U-Boot SPL was the symptom). Fix: open Docker Desktop → Settings → General → uncheck "Use Rosetta for x86_64/amd64 emulation on Apple Silicon". Use QEMU emulation only.

### linux-devkit/environment-setup pollutes CPATH for kernel/U-Boot builds

Sourcing `linux-devkit/environment-setup` sets CC, CFLAGS, and CPATH to aarch64 sysroot paths. This breaks HOSTCC (the host compiler used for `scripts/`, `tools/`, etc.) and causes confusing build failures. Never source it for kernel or U-Boot builds. Use `/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh` instead — it sets only PATH, ARCH, and CROSS_COMPILE.

### U-Boot 2025.01 requires extra host packages

The TI U-Boot 2025.01 tree needs several host tools not present in a minimal Ubuntu 22.04 container:

```
apt-get install -y swig libgnutls28-dev python3-yaml yamllint \
    libssl-dev python3-dev python3-setuptools
```

Symptom without these: cryptic Python import errors or missing gnutls linker failures mid-build.

### SDK Makefile defaults to MAKE_JOBS=1 — always override

The top-level SDK Makefile / Rules.make sets `MAKE_JOBS ?= 1`. Under QEMU this makes an already slow build ~8× slower than necessary. Always pass an explicit job count:

```
make MAKE_JOBS=$(nproc) ...
# or equivalently for direct kernel/U-Boot invocations:
make -j$(nproc) ...
```

### TI device tree naming — am62-lp-sk, not am625-sk-lp

TI's upstream convention puts the SoC family (`am62`) and the variant tag (`lp`) in the prefix, with the board class (`sk`) at the end: `k3-am62-lp-sk.dts`. The intuitive-but-wrong order `k3-am625-sk-lp.dts` does not exist in the kernel tree. Any new derived DTS must `#include` the real upstream filename or the C preprocessor fails before DTC runs.

### make -n does not propagate to recursive sub-makes

The dry-run flag stops at the first `make -C ...` invocation. For two-stage builds (workspace Makefile that invokes a kernel Makefile), `make -n` will print the outer commands but the sub-make actually runs. Don't trust `-n` to be a true dry run when recursion is involved — verify with explicit before/after state checks instead.

### Anchoring sed insertions into the kernel DT Makefile

The kernel's `arch/arm64/boot/dts/ti/Makefile` has many lines containing `k3-am62-lp-sk.dtb` as a substring (e.g., in `*-dtbs := k3-am62-lp-sk.dtb \` continuation blocks). A loose `sed '/k3-am62-lp-sk\.dtb/a ...'` will match all of them and insert duplicates on every run. Use exact-line matching (`awk '$0 == anchor'` or `grep -Fxq`) for both insertion and existence checks. Also: `sed -i.bak` overwrites the backup on every run, so the `.bak` is not a safe pristine-state restore — it's only the previous run's state, which may itself have been broken.

---

## Session conventions

- Concise, no re-explaining established context
- Push back on wrong framing rather than accommodating it
- Ask clarifying questions one at a time with 2–4 options
- No emojis, no headers in conversational responses, no restating the question before answering
- When chip or capability facts are needed, search TI docs rather than relying on memory

## Current state (2026-04-18 session)

All BOM, runtime, rootfs, and OTA decisions now locked.
See ../docs/session-findings-2026-04-18.md for the full decision record.
AM62↔radar interface defined in ../docs/interfaces-am62-radar.md.
