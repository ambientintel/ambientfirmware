# Session Findings Appendix — 2026-04-18 (PM session)

Append to or consolidate with the existing docs/session-findings-2026-04-18.md. This
entry records a decision made later the same day as the main findings doc and
supersedes the "AM62 vs AM62A" open item carried forward from that record.

## Context

The 2026-04-18 AM session locked BOM / runtime / rootfs / OTA decisions but left the
AM62 SoC choice open pending ML inference workload decisions. A follow-up
conversation in the PM session reopened the SoC question after an engineering
consultation flagged PMIC integration as challenging.

Investigation of the PMIC concern clarified that:

1. TPS65219 with AM62 pre-programmed NVM is well-documented and has a known-good
   reference in SK-AM62-LP. PMIC design for AM62x is closer to "copy the reference
   and follow layout rules" than a from-scratch exercise.
2. The real layout risk for a discrete AM62x + LPDDR4 design is the DDR interface,
   not the PMIC. LPDDR4 signal integrity, length-matching, and layer count
   dominate the engineering burden.
3. Octavo's OSD62x-PM eliminates LPDDR4 work entirely while leaving PMIC on the
   carrier board — where it can be copied from the SK-AM62-LP reference.

Given the project is early-stage, time-to-market critical, and initial volume is
low, the LPDDR4 risk outweighs the PMIC risk, and the SiP premium amortizes into
noise at current volumes.

## Decision

AM62 SoC: **Octavo OSD62x-PM** (OSD6254-1G-IPM). Full rationale, alternatives
considered, and consequences captured in docs/adr/ADR-0002-am62-soc-choice.md.

## Supersedes

- "AM62 vs AM62A" open decision listed in workspace/CLAUDE.md (2026-04-18 AM
  state). That decision is now closed to AM625 (via OSD62x-PM). A future reversal
  to AM62A would break ADR-0002 and require a new SoC-selection ADR.

## Still open after this decision

- Radar boot mode (autonomous QSPI vs host-fed over SPI)
- Connectivity (Wi-Fi/BLE/Ethernet/cellular mix) — next task: TI SDK driver
  maturity check for Wi-Fi/BLE module candidates
- App runtime (native / Python / containers / Node)
- OTA strategy (A/B / delta / container / full image)
- Fleet management (size, access, observability)
- Production rootfs (deferred until BOM stabilizes)

## Follow-ups from ADR-0002

- Obtain Octavo longevity statement for OSD62x-PM, file alongside the ADR
- Confirm exact TPS65219 pre-programmed NVM OPN against Octavo power app note
- Validate current 8-layer FR-4 fab spec against Octavo OSD62x-PM Layout Guide;
  expect to upgrade to 10 layers with microvias or HDI process
- Pin mux spreadsheet against OSD62x-PM ball map using Octavo's pin mapping app
  note (next concrete task)
- eMMC size selection after OTA partitioning is locked
- Schedule Octavo design review service engagement before first fab

## Cross-references

- docs/adr/ADR-0002-am62-soc-choice.md — full decision record
- workspace/CLAUDE.md — updated project master doc reflecting this decision
- docs/session-findings-2026-04-18.md — original AM-session findings (BOM /
  runtime / rootfs / OTA)
- docs/interfaces-am62-radar.md — AM62 ↔ IWR6843AOP interface spec
