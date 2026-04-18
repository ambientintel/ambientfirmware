# ADR-0002: AM62 SoC Selection — Octavo OSD62x-PM

Date: 2026-04-18
Status: Accepted
Supersedes: Open decision "AM62 vs AM62A" in workspace/CLAUDE.md (dated 2026-04-18)

## Context

The custom board pairs a TI AM62x-class SoC with an IWR6843AOP 60 GHz radar. The SoC
selection had been left open pending ML inference workload decisions. With the project
at an early stage, time-to-market critical, and initial volume low, the expensive
hardware risks are board re-spins and LPDDR4 signal-integrity problems — not per-unit
BOM cost.

The team does not have deep in-house LPDDR4 layout experience. An engineering
consultation flagged PMIC integration as challenging; on investigation, the PMIC
concern is generic rather than specific to TPS65219 + AM62x, which has pre-programmed
NVM variants and a known-good reference in SK-AM62-LP. The real layout risk for a
discrete AM62x + LPDDR4 design is the DDR interface, not the PMIC.

## Decision

Use **Octavo OSD62x-PM** (`OSD6254-1G-IPM`) as the AM62 island SoC.

The OSD62x-PM integrates AM6254 + 1 GB DDR4 + passives in a 9×14 mm, 500-ball, 0.5 mm
pitch BGA. It is production-shipping as of this decision, priced at $22.50 at 1kU
through Octavo direct, with a v2.0 datasheet dated 2026-01-16 and a documented
application-note set covering schematic, pin mapping, layout, thermal, boot, and
power design.

## Alternatives Considered

### Raw AM625 discrete (rejected)
- TI-direct supply, lowest per-unit BOM cost
- Rejected: team lacks LPDDR4 layout experience; low volume cannot amortize the
  engineering investment; DDR re-spin risk incompatible with time-to-market

### TI AM625SIP (AMK package, DDR-integrated, no PMIC) (rejected as primary, noted as backup)
- First-party TI silicon with TI longevity commitments; same DDR integration benefit
- Rejected: thinner reference-design ecosystem than OSD62x-PM; no equivalent to
  Octavo's app note set or design review service; no published Altium symbols.
  Worth reconsidering if Octavo supply risk becomes material.

### Octavo OSD62x (full integration: AM62 + DDR + TPS65219 PMIC + EEPROM + oscillators) (rejected)
- Would also eliminate PMIC and oscillator work
- Rejected: Beta status as of 2026-04-18, incompatible with a commercial product
  shipping to senior-living facilities. Additionally, the integrated TPS65219 fixes
  the switching frequencies — which removes a degree of freedom for controlling
  noise in 60 GHz radar sensitive bands. Revisit if Octavo releases OSD62x to
  production before schematic freeze.

### AM62A (C7x DSP + MMA accelerator) (deferred)
- Relevant only if ML inference runs on the A53/accelerator path rather than on
  radar-side (C674x DSP + HWA)
- Not available in OSD62x-PM form factor
- Current plan: prototype ML workload on SK-AM62-LP first; if inference demand
  exceeds radar-side capacity, revisit SoC choice before custom-board schematic
  freeze. A move to AM62A breaks this ADR and requires a new SoC-selection exercise.

## Consequences

### Positive
- LPDDR4 routing, length-matching, and signal-integrity work eliminated from the
  AM62 island
- Reference schematic, layout guide, pin mapping, and power app notes available
  from Octavo
- Altium symbol library published — drops directly into the existing tool flow
- Breakout board (OSD62-PM-BRK) available if hardware prototyping of the SiP is
  wanted before committing the custom board
- Wide industrial temperature range (-40 to +85 °C) standard — no grade uplift
  needed
- PMIC noise spectrum still tunable at the board level (unlike full-integration
  OSD62x), preserving the ability to avoid radar-sensitive switching frequencies

### Negative
- 0.5 mm BGA pitch at 500 balls requires careful escape routing. Likely 8-layer
  minimum with microvias; may push to 10 layers or HDI depending on density.
  Current fab target (8-layer FR-4 per CLAUDE.md) needs re-validation against
  Octavo's layout guide.
- Octavo is the sole supplier of the SiP. TI is still the upstream silicon source,
  but a drop-in substitute does not exist. Mitigation path: discrete AM6254 +
  TPS65219 + LPDDR4 respin possible, at the cost of several months and new
  engineering effort.
- SiP premium over discrete BOM — acceptable at current volume, revisit if volume
  exceeds ~10k units/year.
- PMIC, oscillators, boot flash, and decoupling still required on the board — the
  "PM" in the part name means "processor module," not "all-integrated."

### Neutral / To Verify
- Octavo longevity statement for OSD62x-PM specifically — should be obtained and
  filed alongside this ADR before schematic freeze.
- Schematic and layout review by Octavo's design review service recommended before
  first fab.

## AM62 Island BOM (informational, not authoritative)

The following parts are required on the custom board in addition to the OSD62x-PM
itself. Component values and specific OPNs are to be confirmed against Octavo's
schematic checklist, power application note, and power design & budgeting app note
during schematic capture. This list is scoped to the AM62 island only — the radar
island is frozen and inherits from the TI IWR6843AOPEVM Altium source.

### Core module
- OSD6254-1G-IPM (Octavo) — AM6254 + 1 GB DDR4 + passives

### Power
- TPS65219 PMIC with AM62 pre-programmed NVM OPN (exact OPN per Octavo power app
  note)
- Input supply: 5 V nominal (per Octavo recommendation, to be confirmed)
- PMIC input/output capacitors, switcher inductors per TPS65219 datasheet reference
- Per-rail bulk decoupling (10 µF / 1 µF / 100 nF network) per Octavo schematic
  checklist
- External LDOs for any IO voltages not served by the PMIC (e.g., switchable MMC
  1.8/3.3 V if required)

### Clocks
- 25 MHz crystal or TCXO, ±50 ppm, for MCU_OSC0
- 32.768 kHz crystal, ±20 ppm, for WKUP_LFOSC0
- Load capacitors per oscillator datasheet and PCB stray analysis

### Boot and storage
- OSPI or QSPI boot flash (e.g., Macronix MX25U51245G or Winbond W25Q512JV class)
- eMMC for rootfs (size TBD — depends on OTA partitioning decision in
  session-findings-2026-04-18)
- Optional µSD connector for development only, not production

### Reset and boot control
- Reset supervisor (TPS3839 class) for clean power-on reset
- SYSBOOT[15:0] boot-mode strap resistors
- Dev-only: reset pushbutton, boot-mode DIP switches (removed at production)

### Debug
- 20-pin cTI JTAG header for external XDS110
- 4-pin debug UART header (MAIN_UART0)

### AM62 ↔ IWR6843AOP interface (per workspace/docs/interfaces-am62-radar.md)
- UART TX/RX direct nets, 0 Ω series for debug stuffing option
- SPI CLK/MOSI/MISO/CS reserved nets
- SPI_HOST_INTR, NERROR_OUT — pull-ups per direction
- NRESET direct or level-shifted depending on IO voltage domain match (confirm
  both sides are 3.3 V LVCMOS during schematic capture)
- SOP[2:0] strap resistors per IWR6843AOP boot mode decision (separate open item)

### Connectivity (placeholder pending BOM decisions)
- Wi-Fi/BLE module — module selection is the next task in this project
- Ethernet PHY + magnetics + RJ45 if wired Ethernet is in scope (DP83867 per
  SK-AM62-LP reference)
- Antenna count depends on connectivity choice

### Miscellaneous
- USB-C connector + ESD protection (if USB is exposed for service)
- Status LEDs
- I2C pull-ups (4.7 kΩ class)
- Thermal pad or heatsink provision for sustained A53 loading

## References

- Octavo OSD62x-PM product page: https://octavosystems.com/octavo-products/osd62x-pm/
- OSD62-PM datasheet v2.0 (2026-01-16)
- OSD62x-PM Schematic Checklist (Octavo app note)
- OSD62x-PM to AM62x Pin Mapping (Octavo app note)
- OSD62x-PM Layout Guide (Octavo app note)
- OSD62x-PM Power Design and Budgeting (Octavo app note)
- OSD62x-PM Boot Chain and Debug (Octavo app note)
- OSD62-PM-BRK breakout board: https://octavosystems.com/octavo-products/osd62-pm-brk/
- DDR device-tree configuration: https://github.com/octavosystems/osd62-pm-ddr
- workspace/CLAUDE.md — project master doc
- docs/session-findings-2026-04-18.md — BOM/runtime/rootfs/OTA decision record
- docs/interfaces-am62-radar.md — interface spec between AM62 and IWR6843AOP
- ADR-0001 (implicit) — Path A: raw silicon custom board using TI IWR6843AOPEVM
  Altium source

## Follow-ups

- Obtain Octavo longevity statement for OSD62x-PM
- Confirm exact TPS65219 OPN against Octavo power app note
- Validate fab stackup (8-layer FR-4) against Octavo layout guide; upgrade to 10
  layers / HDI if required
- Pin mux spreadsheet against OSD62x-PM ball map (next task)
- eMMC size selection after OTA partitioning is locked
- Schedule Octavo design review service engagement before first fab
