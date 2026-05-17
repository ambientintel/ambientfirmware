TI AM62x + IWR6843AOP Firmware Project
Project scope
Custom PCB integrating TI AM62x (A53 SoC, via Octavo OSD62x-PM SiP) + TI IWR6843AOP (60 GHz mmWave radar with antenna-on-package). SK-AM62-LP is the development platform; IWR6843AOP has been prototyped against Mistral's pre-built module on a Raspberry Pi. Custom board design is underway with the TI-published IWR6843AOPEVM Altium files as the starting point for the radar section and the Octavo OSD62x-PM as the AM62 island core.

Hardware target
Dev board: TI SK-AM62-LP (low-power AM62x starter kit)

SoC: AM625 — quad Cortex-A53 @ 1.4 GHz + Cortex-M4F + Cortex-R5F
Memory: LPDDR4
Debug console: onboard FT4232 USB-UART bridge via micro-USB (J17 on board) — enumerates as 4x tty.usbserial-*40/41/42/43; SOC_UART0 = port ending in 40. Confirmed port on this machine: tty.usbserial-102612400940. Open with: tio /dev/tty.usbserial-102612400940 -b 115200. Connect J17 micro-USB BEFORE running tio, BEFORE powering on.
JTAG: onboard XDS110 via separate micro-USB (J18)
Radar prototyping: IWR6843AOP via Mistral pre-built module on Raspberry Pi (early testing only; production uses raw silicon on custom board).

Custom board: integrates Octavo OSD62x-PM (AM6254 + 1GB DDR4 + passives) + IWR6843AOP. See "Custom board architecture" below.

Reference docs
workspace/docs/BOOT_DAY_RUNBOOK.md — First power-on procedure for SK-AM62-LP. Covers SD card prep, serial console setup, expected output at each boot stage, and troubleshooting.
workspace/device-tree/README.md — Custom device tree build flow.
docs/adr/ADR-0002-am62-soc-choice.md — AM62 SoC selection: Octavo OSD62x-PM. Supersedes the "AM62 vs AM62A" open decision.
docs/session-findings-2026-04-18.md — BOM/runtime/rootfs/OTA decision record.
docs/interfaces-am62-radar.md — Interface spec between AM62 and IWR6843AOP.

Host build environment
Host OS: macOS (Apple Silicon)
Build container: Ubuntu 22.04 x86_64 under Docker Desktop (QEMU emulation, Rosetta OFF)
Workspace bind mount: ~/ti-am62x/workspace (Mac) ↔ /workspace (container)
Enter container: ~/ti-am62x/enter.sh
Git workflow: edits happen in the container, commits and pushes happen in GitHub Desktop on the Mac (the bind mount makes container edits visible to the host).
SDK
Version: TI Processor SDK Linux AM62x 11.02.08.02 (2026 LTS)
SDK root: /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/ (in container)
On Mac: ~/ti-am62x/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/
Kernel: board-support/ti-linux-kernel-6.12.57+git-ti/
U-Boot: board-support/u-boot-*/
Prebuilt images (LP): board-support/prebuilt-images/am62xx-lp-evm/
Cross toolchain (A53): aarch64-oe-linux-gcc 13.4 in linux-devkit/sysroots/x86_64-arago-linux/usr/bin/aarch64-oe-linux/
R5F toolchain: k3r5-devkit/
Build conventions
Kernel and U-Boot
Do NOT source linux-devkit/environment-setup — it pollutes CPATH/CC/CFLAGS with aarch64 paths and breaks HOSTCC. Instead, source the project helper:

source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
This sets PATH, ARCH=arm64, CROSS_COMPILE=aarch64-oe-linux- without contaminating HOSTCC.

Standard kernel build:

cd /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/ti-linux-kernel-*/
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- ti_arm64_prune.config
make ARCH=arm64 CROSS_COMPILE=aarch64-oe-linux- -j$(nproc) Image dtbs
Userspace applications
DO source linux-devkit/environment-setup — this is what it's designed for.

Never mix
Open separate shells for kernel builds vs userspace builds.

Key device tree files for SK-AM62-LP
Base SoC: arch/arm64/boot/dts/ti/k3-am625.dtsi (or equivalent)
Board: arch/arm64/boot/dts/ti/k3-am62-lp-sk.dts
Overlays:
k3-am62-lp-sk-nand.dtso — NAND flash
k3-am62x-sk-lpm-standby.dtso — low-power standby mode
k3-am62-lp-sk-lincolntech-lcd185-panel.dtso — LCD panel
k3-am62-lp-sk-microtips-mf101hie-panel.dtso — LCD panel
Custom device tree workflow
Out-of-tree DTS lives at workspace/device-tree/k3-am62-lp-sk-ambient.dts. It #includes the stock k3-am62-lp-sk.dts and overrides only compatible and model. Ambient-specific peripherals (sensor nodes, custom pinmux) get added below the root node as new content lands.

Naming convention: TI uses am62-lp-sk (SoC family + LP variant), not am625-sk-lp. The earlier wrong name produced a non-existent include path. New ambient board files must follow TI's convention to keep includes resolvable.

Build flow: workspace/device-tree/Makefile is build glue, not a kernel Makefile. It copies the DTS into $(KERNEL_SRC)/arch/arm64/boot/dts/ti/, registers a new line in the kernel's DT Makefile via awk exact-line insertion (anchored on the stock k3-am62-lp-sk.dtb entry), then invokes make dtbs in the kernel tree. Idempotent — safe to re-run. Validates the anchor line exists in the kernel Makefile up front, so future SDK format changes fail loudly rather than silently no-op.

source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
cd /workspace/device-tree
make build KERNEL_SRC=$KERNEL_SRC
# produces $KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb
Ambient DTB confirmed booting: copy `k3-am62-lp-sk-ambient.dtb` to the BOOT FAT partition root, then reference it as `devicetree /k3-am62-lp-sk-ambient.dtb` in `EFI/BOOT/grub.cfg`. The `fdtfile` variable in `uEnv.txt` has no effect in this GRUB EFI boot path — GRUB's `devicetree` directive controls the DTB, not U-Boot. GRUB silently falls back to the U-Boot-loaded DTB if the file is not found, so the DTB file must be present on the FAT partition.

Note on DTB for custom board: the OSD62x-PM integrates AM6254 in the AMC package with its own LPDDR4 config. The production DTB will need the OSD62x-PM DDR device-tree configuration from Octavo (github.com/octavosystems/osd62-pm-ddr), not the SK-AM62-LP DDR settings. This is a separate DTB artifact from the SK-AM62-LP dev overlay.

Conventions / don'ts
Don't modify linux-devkit/ — that's the sysroot, treat as read-only
Kernel changes: create patches in a dedicated patches/ dir rather than committing directly to the TI kernel tree
Device tree overlays preferred over modifying base .dts files
Don't commit build artifacts (*.o, .tmp_versions, arch/arm64/boot/Image, etc.)
Build performance notes
Docker under QEMU emulation is 3–5× slower than native x86
Full kernel build: ~45–90 min (completed successfully once)
Yocto full build: not yet attempted; estimate 12–20+ hours; will likely use cloud VM
Current status
 Docker Ubuntu 22.04 x86_64 container set up (QEMU emulation, Rosetta OFF)
 TI Processor SDK Linux 11.02.08.02 installed
 Cross-toolchain verified (aarch64-oe-linux-gcc 13.4)
 Kernel + DTB build succeeded (Image=22MB, k3-am62-lp-sk.dtb=65KB)
 U-Boot compiled (tiboot3.bin, tispl.bin, u-boot.img)
 Git repo pushed to ambientintel/ambientfirm
 Custom DTB build flow validated end-to-end (k3-am62-lp-sk-ambient.dtb)
 IWR6843AOP prototyped on Raspberry Pi via Mistral module
 Path A committed for custom board (raw silicon, TI Altium source)
 AM62 island SoC locked: Octavo OSD62x-PM (ADR-0002, 2026-04-18)
 SK-AM62-LP hardware received (2026-05-15)
 First boot with prebuilt SD card image (SDK 12.x WIC, kernel 6.18.13-ti, 2026-05-15)
 OTA decision: Mender self-hosted (ADR-0003, 2026-05-15)
 First boot with custom kernel (SDK 11.x prebuilt, kernel 6.12.57-ti, 2026-05-16)
 Ambient DTB booted (k3-am62-lp-sk-ambient.dtb, model="Ambient Intel AM62x-LP", 2026-05-16)
 TFTP/NFS dev loop set up
 Radar boot mode decision (see Open decisions)
 Physical connectivity (Wi-Fi/Ethernet/cellular) still open (see Open decisions)
 App runtime: Python 3.11 — closed
 Cloud transport: AWS IoT Core MQTT + X.509 — closed
 Rootfs decision (deferred until BOM stabilizes)
 Pin mux spreadsheet against OSD62x-PM ball map
Custom board architecture
Path decision: Path A — raw silicon radar, OSD62x-PM AM62 module
Radar island uses TI's published Altium files for the IWR6843AOPEVM as the starting point, unchanged. AM62 island uses Octavo's OSD62x-PM SiP (AM6254 + 1GB DDR4 + passives) instead of raw AM625 + discrete LPDDR4. Rationale captured in docs/adr/ADR-0002-am62-soc-choice.md.

Path B (Mistral pre-built radar module soldered as a component) was considered and rejected — Path A gives volume cost optimization and full control on the radar side.

Key insight: Path A is lower-risk than it sounds
The IWR6843AOP is antenna-on-package. All 60 GHz RF is inside the chip. There is no millimeter-wave signal anywhere on our PCB. "RF layout" for this board collapses to: clean power rails, the 40 MHz crystal circuit, ground pour under the package, and respecting the 3D antenna keepout volume above the package. This is careful mixed-signal layout, not microwave PCB engineering.

On the AM62 side, the OSD62x-PM eliminates the hardest layout risk — LPDDR4 routing, length-matching, and signal integrity. The remaining AM62-side work is PMIC, oscillators, boot flash, and careful decoupling, all of which are well-documented in Octavo's application note set.

This framing matters because earlier design conversations overstated both the RF risk and the PMIC risk. Future sessions should not reintroduce those framings.

Two chip islands
Radar island (copy-paste from TI Altium, frozen):

IWR6843AOP
LP87745 PMIC (TI-specified, tight ripple requirements)
40 MHz crystal + load caps
QSPI flash (pending boot-mode decision)
VPP eFuse circuit
NRESET / SOP / WARM_RESET circuitry
Power sequencing
Ground pour geometry and controlled-impedance traces per EVM fab notes
Do not re-route inside this block. Do not substitute passive values. The RF rail ripple specs are tight (sub-100 µV RMS at some frequencies to hit -105 dBc spurs); small changes have real consequences.

AM62 island (OSD62x-PM + support components, our design work):

Octavo OSD62x-PM (OSD6254-1G-IPM) — AM6254 + 1GB DDR4 + passives in 9×14 mm, 500-ball, 0.5 mm pitch BGA
TPS65219 PMIC with AM62 pre-programmed NVM OPN (exact OPN per Octavo power app note)
OSPI or QSPI boot flash
eMMC (size TBD, awaiting OTA partitioning decision)
25 MHz main crystal for MCU_OSC0 + load caps
32.768 kHz RTC crystal for WKUP_LFOSC0 + load caps
Reset supervisor (TPS3839 class) + SYSBOOT strap resistors
20-pin cTI JTAG header (external XDS110 probe, no onboard emulator)
Debug UART header (MAIN_UART0, 4-pin 2.54 mm)
Status LEDs, I2C pull-ups, thermal provisions

Stripped from SK-AM62-LP reference: dual gigabit PHYs, HDMI, audio codec + mic/headphone, M.2, USB-C PD, all EXP/MCU/PRU connectors, WLAN/BT (pending connectivity decision), LVDS display, CSI camera, IO expanders (TCA6424 × 2), onboard XDS110 emulator.

Power isolation: separate PMICs for radar (LP87745, frozen per TI EVM) and AM62 (TPS65219, our design) with no shared rails, even where voltages match. AM62 DDR refresh, A53 clock transitions, and switching regulators generate noise in exactly the bands the radar cares about. Using OSD62x-PM rather than the full-integration OSD62x preserves the ability to tune TPS65219 switching frequencies away from radar-sensitive bands. Grounds joined at a single point near the radar.

Interface boundary (radar ↔ AM62)
See docs/interfaces-am62-radar.md for the authoritative spec. Short summary: UART for primary command + data at ~921.6 kbaud, SPI + SPI_HOST_INTR wired for future bandwidth expansion, NRESET / SOP[2:0] / NERROR_OUT for boot and error control. Short isolated runs across the single ground stitch between islands.

Voltage domain check: AM62 IO (via OSD62x-PM) and IWR6843 IO domain compatibility to be confirmed during schematic capture. If mismatched, level-shifters required on interface nets.

Fab process targets
From IWR6843AOPEVM fab notes, carried forward for the radar section. AM62 section fab targets to be re-validated against Octavo's OSD62x-PM Layout Guide — the 0.5 mm BGA pitch with 500 balls may require microvias or HDI process upgrades beyond the current spec:

8 layers, FR-4 High Tg, 64 mil ±10% thickness (under review for OSD62x-PM escape routing)
ENIG surface finish
18 mil min via, 3.5 mil min trace/clearance (likely needs tightening for OSD62x-PM)
UL94-V0, ANSI IPC-A-600F Class 2 (Class 3 optional)
Controlled impedance: 50 Ω microstrip, 100 Ω edge-coupled diff (LVDS/RGMII/USB), 90 Ω diff (USB), 120 Ω diff (CAN-FD), 50 Ω stripline
Bare-board electrical test required

Open: Octavo's OSD62x-PM Layout Guide will dictate final stackup — expect 10-layer with microvias or HDI process. This is a follow-up from ADR-0002.

Mechanical: AoP antenna keepout is absolute and 3-dimensional — applies to PCB, enclosure, and any material in front of the radar. Whatever sits in front of the AoP becomes part of the antenna.

Open decisions
Listed in priority order. Each blocks work downstream.

1. Radar boot mode
Autonomous QSPI (TI default): radar boots from its own flash, AM62 talks to it post-boot. Two OTA targets to manage.

Host-fed from AM62 over SPI: radar omits QSPI flash, AM62 pushes image on reset release. Single source of truth for radar firmware. Radar can't start until AM62 has booted far enough to feed it.

Decision affects the radar island BOM (QSPI present or not) and the OTA architecture. Lean toward host-fed for deployed product, but needs to be locked before schematic capture on the radar island completes.

Cross-domain dependency: this is the one firmware decision that blocks EE. EE cannot finalize the radar island BOM or place the fab order until this is closed. All other engineering domains (EE schematic work outside the radar island, mechanical, cloud, ambientapp) can proceed in parallel with firmware Steps 14–17.

2. BOM — one remaining open question
Connectivity (physical layer): wired Ethernet / Wi-Fi / BLE / cellular mix. Drives schematic, antenna count, certification scope. Current next task: Wi-Fi/BLE module driver maturity check in TI SDK source. Note: cloud transport is decided (AWS IoT Core MQTT — see closed decisions) but that decision is independent of the physical link layer.

Fleet management: AWS IoT Core handles the MQTT broker and per-device publish policy; ambientcloud-admin handles device provisioning and retirement. Scale model for >30 devices is not yet validated in pilot.

(App runtime, OTA strategy, and cloud transport are now closed — see closed decisions below.)

3. Rootfs (Buildroot / trimmed Yocto / tisdk default)
Deferred. Honest framing: with ML target, model shape, and update strategy all open, picking a minimal production rootfs now would actively get in the way of the research the rootfs is supposed to support.

Plan: research rootfs now (tisdk default or close), production rootfs decided after BOM stabilizes. Two artifacts, deliberate handoff between them.

Closed decisions (see ADRs)
- Custom board path: raw silicon (Path A), TI Altium source (implicit ADR-0001)
- AM62 SoC: Octavo OSD62x-PM (ADR-0002, 2026-04-18). Supersedes "AM62 vs AM62A" open decision.
- OTA: Mender self-hosted (ADR-0003, 2026-05-15).
- App runtime: Python 3.11, single systemd service (ambientapp — ambientintel/ambientapp, 2026-05-16).
- Cloud transport: AWS IoT Core MQTT + X.509 cert auth; no boto3 on device. Device-cloud wire format defined in ambientcloud/docs/device-cloud-contract.md v0.2 (2026-04-18). Rootfs must include: aws-iot-sdk-python-v2, pyarrow, requests, requests-aws4auth.

Radar workload shape (as of this writing)
Firmware option: potentially TI OOB demo / mmWave SDK / custom — still evaluating
Radar → AM62 link: UART initially (~921.6 kbaud)
ML inference target: undecided, may run partially on radar
Model shape: research-phase, unknown
Model update strategy: undecided

Note: a future decision to run ML on AM62A (rather than radar-side or AM625) would invalidate ADR-0002, since OSD62x-PM is AM625-only. Prototype ML workload on SK-AM62-LP first before any such move.

Lessons learned
Rosetta bss_size bug — disable Rosetta in Docker Desktop
Docker Desktop's Rosetta x86_64 emulation has a bug where .bss section sizes are miscalculated during linking, producing silently corrupt binaries (U-Boot SPL was the symptom). Fix: open Docker Desktop → Settings → General → uncheck "Use Rosetta for x86_64/amd64 emulation on Apple Silicon". Use QEMU emulation only.

linux-devkit/environment-setup pollutes CPATH for kernel/U-Boot builds
Sourcing linux-devkit/environment-setup sets CC, CFLAGS, and CPATH to aarch64 sysroot paths. This breaks HOSTCC (the host compiler used for scripts/, tools/, etc.) and causes confusing build failures. Never source it for kernel or U-Boot builds. Use /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh instead — it sets only PATH, ARCH, and CROSS_COMPILE.

U-Boot 2025.01 requires extra host packages
The TI U-Boot 2025.01 tree needs several host tools not present in a minimal Ubuntu 22.04 container:

apt-get install -y swig libgnutls28-dev python3-yaml yamllint \
    libssl-dev python3-dev python3-setuptools
Symptom without these: cryptic Python import errors or missing gnutls linker failures mid-build.

SDK Makefile defaults to MAKE_JOBS=1 — always override
The top-level SDK Makefile / Rules.make sets MAKE_JOBS ?= 1. Under QEMU this makes an already slow build ~8× slower than necessary. Always pass an explicit job count:

make MAKE_JOBS=$(nproc) ...
# or equivalently for direct kernel/U-Boot invocations:
make -j$(nproc) ...
TI device tree naming — am62-lp-sk, not am625-sk-lp
TI's upstream convention puts the SoC family (am62) and the variant tag (lp) in the prefix, with the board class (sk) at the end: k3-am62-lp-sk.dts. The intuitive-but-wrong order k3-am625-sk-lp.dts does not exist in the kernel tree. Any new derived DTS must #include the real upstream filename or the C preprocessor fails before DTC runs.

make -n does not propagate to recursive sub-makes
The dry-run flag stops at the first make -C ... invocation. For two-stage builds (workspace Makefile that invokes a kernel Makefile), make -n will print the outer commands but the sub-make actually runs. Don't trust -n to be a true dry run when recursion is involved — verify with explicit before/after state checks instead.

Anchoring sed insertions into the kernel DT Makefile
The kernel's arch/arm64/boot/dts/ti/Makefile has many lines containing k3-am62-lp-sk.dtb as a substring (e.g., in *-dtbs := k3-am62-lp-sk.dtb \ continuation blocks). A loose sed '/k3-am62-lp-sk\.dtb/a ...' will match all of them and insert duplicates on every run. Use exact-line matching (awk '$0 == anchor' or grep -Fxq) for both insertion and existence checks. Also: sed -i.bak overwrites the backup on every run, so the .bak is not a safe pristine-state restore — it's only the previous run's state, which may itself have been broken.

SK-AM62-LP vs custom board package mismatch
The SK-AM62-LP dev board uses AM625-Q1 or AM620-Q1 in the AMC package. The custom board uses Octavo OSD62x-PM, which wraps AM6254 in a different ball-out (500-ball Octavo package, not AMC directly). Ball numbers and pin mux references do not copy one-to-one from SK-AM62-LP schematics. Use Octavo's "OSD62x-PM to AM62x Pin Mapping" application note as the translation layer when porting SK-AM62-LP reference designs.

Octavo SiP naming — "-PM" means "processor module," not "fully integrated"
The OSD62x-PM integrates AM62 + LPDDR4 + passives only. PMIC, oscillators, boot flash, and decoupling are still on the carrier board. The fully-integrated sibling (OSD62x, Beta as of 2026-04-18) adds PMIC + EEPROM + oscillators but is not production-qualified. Don't confuse the two when referencing Octavo documentation or Digi-Key part numbers.

GRUB EFI DTB path — devicetree directive, not fdtfile
In this board's boot chain (U-Boot → GRUB EFI → kernel), the DTB passed to the kernel is controlled by GRUB's `devicetree` directive in `EFI/BOOT/grub.cfg`, not by `fdtfile` in `uEnv.txt`. The `fdtfile` variable is read by U-Boot's distro boot scripts, which are not executed in the EFI handoff path. GRUB silently falls back to whatever DTB U-Boot already loaded in memory if the specified file is not found — no error, no warning, boot continues with the stock DTB. Always verify the DTB file physically exists at the specified path on the BOOT FAT partition before rebooting.

Session conventions
Concise, no re-explaining established context
Push back on wrong framing rather than accommodating it
Ask clarifying questions one at a time with 2–4 options
No emojis, no headers in conversational responses, no restating the question before answering
When chip or capability facts are needed, search TI / Octavo / vendor docs rather than relying on memory
Current state (2026-05-16 session)
First boot achieved 2026-05-15 with SDK 12.x WIC image (kernel 6.18.13-ti). ADR-0003 committed (OTA = Mender self-hosted). Docs updated: RUNBOOK, FIRST_BOOT_TUTORIAL, CLAUDE.md, README.

Lesson (2026-05-16): Complete UART silence after replacing boot files was caused by micro-USB cable in J18 (XDS110 JTAG) instead of J17 (FT4232 UART). Both connectors are micro-USB-B and look identical. Always verify J17 before assuming boot failure. Added to RUNBOOK §A and §3.

JTAG / OpenOCD setup (Step 14, done 2026-05-17)
OpenOCD 0.12.0 installed on the Mac host (brew install openocd). Board config at workspace/jtag/am625-xds110.cfg.
A53 core 0 halted at EL1H, pc=0xffff800080010a00, MMU+caches enabled. Confirmed working.

Verified attach sequence:
1. Boot Linux fully (wait for login prompt on tio) — TIFS must run to assert DBGEN
2. openocd -f workspace/jtag/am625-xds110.cfg
3. telnet localhost 4444  (nc segfaults on macOS)
4. am625.cpu.a53.0 arp_examine  (only works after Linux boot)
5. am625.cpu.a53.0 arp_halt
6. targets am625.cpu.a53.0 → resume

Config gotchas (permanent):
- transport select jtag required — XDS110 auto-selects SWD, disconnects immediately on AM625
- Do NOT put init_board in cfg — segfaults before init completes
- Interface: interface/xds110.cfg NOT ti_xds110.cfg (old name, doesn't exist in 0.12.0)
- Target: ti_k3.cfg with set SOC am625 NOT ti_am625.cfg
- GDB port map: 3333=sysctrl, 3334=a53.0 (kernel debug target), 3335-7=a53.1-3, 3338=main0_r5.0, 3339=gp_mcu
- OpenOCD runs on Mac host; Docker container reaches it at host.docker.internal:3334
- GDB: use aarch64-oe-linux-gdb from inside container (after sourcing kernel-env.sh); NOT macOS gdb

Next task: Step 15 (TFTP/NFS dev loop) — BLOCKED pending Ethernet cable + USB-C adapter arrival.
Proceeding with Step 16 (IWR6843AOP interface prep) in parallel — see firmware page phase '11b'.

Step 16 is NOT a kernel driver patch. It is:
- A: Verify UART device node (/dev/ttyS1) accepts 921600 baud; install pyserial
- B: GPIO DTS nodes for NRESET, SOP[2:0], NERROR_OUT (pin numbers from OSD62x-PM ball map)
- C: Add radar/gpio.py to ambientapp (gpiod-based NRESET/SOP control)
- D: ambientapp deployment dry run on Arago rootfs (expect UART timeout, not crash)
- E: SPI node — blocked on Step 17 boot mode decision

Step 17 DECISION NEEDED — blocks EE fab order. Recommendation: autonomous QSPI.
Autonomous QSPI: radar boots from own flash, AM62 sends UART config post-boot, Mender handles updates.
Host-fed SPI: no QSPI flash, AM62 pushes firmware over SPI — requires radar/boot.py (not written).
