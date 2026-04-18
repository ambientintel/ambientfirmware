# Session findings — 2026-04-18

Consolidates decisions locked this session. Supersedes earlier
working-assumption statements in the previous CLAUDE.md. Decisions here
are firm unless explicitly reopened.

---

## Product context (refined this session)

Target market is **commercial senior living**: memory care, assisted
living, independent living. Not consumer home. This changes several
upstream assumptions:

- **Buyer/user split:** facility staff (IT, maintenance, care
  coordinators) handle devices. Not sophisticated IT but not zero
  support either.
- **Sales model:** sold per-facility, not per-unit. 20–200 units per
  facility depending on level of care.
- **Regulatory exposure:** facilities are state-licensed. Fall detection
  is safety-adjacent. OTA/audit/signing requirements end up in
  SOC 2 / HIPAA-adjacent audits.
- **Unit economics:** $50–150/month/unit revenue range (competitive
  landscape: Caregiver Smart Solutions, Caraline, etc.). Per-device
  OTA/infra costs are rounding error at this price point.
- **Device lifetime:** 5–7 year capital depreciation cycle. Must ship
  kernel security updates on units for years after last-built date.
- **Network:** facility Wi-Fi is real and continuous; no cellular
  fallback needed v1.
- **False-positive/negative asymmetry:** residents in memory care fall
  3–5× general population rate and often can't self-report. Missed
  falls cost more than false alerts. Detector roadmap will reflect this.

---

## Decisions locked this session

### Hardware

| Decision | Resolution |
|---|---|
| Radar boot mode | **Host-fed** over SPI from AM62. QSPI flash footprint routed and placed on first spin but **DNI** (do not install) as escape hatch for standalone radar bring-up if ever needed. |
| SoC family | **AM62**, not AM62A. Betting radar-side compute (C674x DSP + HWA + 1.75 MB SRAM) handles inference. AM62 A53 quad does orchestration, networking, OTA, light post-processing only. |
| SoC SKU | **AM6254** — quad A53, no GPU, ALW package (17.2mm FCBGA-441). Matches SK-AM62-LP EVM pinout 1:1. |
| Connectivity | **Wi-Fi + BLE** via pre-certified combo module. Leaning Murata 1YN (NXP IW416) or CYW43xx class for BT 5.x support. Rejecting WL18xx (BT 4.2, aging). **TI SDK driver maturity check still pending** before final module selection. |
| eMMC size | **16 GB** (bumped from 8 GB default). Accommodates A/B rootfs slots + data partition with headroom. |
| Separate PMICs | Confirmed: **LP87745 for radar, TPS65219 for AM62**. No shared rails. Radar analog rail ripple spec <100 µV RMS drives this. |
| Fab process | 8-layer FR-4 High Tg, ENIG, controlled impedance per TI EVM spec. May push to 10 layers for DDR + power integrity — worth pricing when schematic stabilizes. |

### Software stack

| Decision | Resolution |
|---|---|
| App runtime | **Python 3.11+ on systemd.** Dev rig and production both. No containers v1. |
| App repo | **github.com/ambientintel/ambientapp** — clean ground-up rewrite pushed 2026-04-18. Replaces the `Ambient-Intelligence` fork. |
| Rootfs | **Yocto.** tisdk default for bring-up, custom Mender-integrated Yocto image for production. |
| OTA framework | **Mender hosted.** A/B rootfs updates for OS/kernel/radar-firmware; Mender update-module for app-only fast-path updates to `/var/lib/ambient`. |
| Fleet management | **Mender built-in.** No separate tool. Device attributes carry facility/wing/floor grouping. |
| Partition layout | `boot` (~32 MB) + `rootfs-A` + `rootfs-B` (~1–2 GB each) + `data` (rest) |

### App architecture (ambientapp repo)

- `src/ambient/radar/` — UART I/O, TLV parsing (vendored from legacy
  parseTLVs.py), tracker adapter, config loader that reads frameCfg to
  derive actual frame rate
- `src/ambient/detection/fall.py` — refactored from legacy
  fall_detection.py. **Edge-triggered** (fires once per transition,
  not every frame — fixes alert-spam from legacy). Parameterized by
  real frame rate from config.
- `src/ambient/events/` — event bus, debouncer, publisher (LogPublisher
  default, MqttPublisherStub placeholder)
- `src/ambient/app.py` — wiring, signal handling, main loop
- `tools/replay.py` — runs detector against captured JSON for iteration
- `tools/capture.py` — raw UART capture for future regression corpus
- `deploy/ambient.service`, `deploy/install.sh` — systemd install
- `tests/` — unit tests for detector, debouncer, config

### Known behavioral change from legacy

The legacy `fall_detection.py` hardcoded `frame_time = 55` as Hz. Real
frame rate from `Final_config_6m.cfg` is 18.18 Hz (55 ms periodicity).
Legacy's "1.5s buffer" was effectively 4.5s. Refactored code reads
frameCfg and sizes correctly. **Will need re-tuning against captured
JSON** — the shorter window is more responsive but may shift the
false-positive/negative balance. Pass `fall_window_seconds=4.5` to
restore legacy behavior explicitly if needed.

---

## Open items (not blocking current work)

### Short-term, next session or two

- **Wi-Fi/BLE module final selection.** Need to evaluate TI SDK driver
  maturity for Murata 1YN (IW416) vs CYW43xx vs others. Decision blocks
  schematic-level Wi-Fi integration but not AM62/radar work.
- **Mender signing key management.** Generate keypair, decide on storage
  (HSM ideal, encrypted offline minimum). Treat like code-signing cert.
  Needed before first production deployment, not before dev.
- **Radar firmware path.** TI OOB vs mmWave SDK vs custom. Given the
  bet that radar does inference, OOB is likely insufficient (it's a
  demo shell). Defer concrete decision until AM62 EVM is up and we can
  test with the current people-tracking firmware first.
- **Drop in two .cfg files into ambientapp/configs/.** (Done this
  session — wall_mount_6m.cfg and roof_mount.cfg committed.)

### Medium-term, post-EVM bring-up

- **Re-tune fall detector.** Run ambientapp against existing JSON
  captures via `tools/replay.py`. Decide whether to keep 1.5s window
  or match legacy 4.5s. Label captures with ground truth to build
  regression corpus.
- **MQTT/HTTPS publisher implementation.** Replace the LogPublisher
  stub. Backend choice (own backend vs AWS IoT Core vs Azure IoT Hub
  vs something else) still open.
- **BLE provisioning flow.** Design for facility-staff first-time
  setup. Likely a paired mobile app for the installer. Scope and
  spec deferred.

### Longer-term

- **Fall detector improvements.** Current threshold-over-window
  algorithm will need replacement for memory-care accuracy targets.
  Likely direction: small sequence model over trackData (position,
  velocity, acceleration) rather than height alone. Runs in Python
  on AM62 via ONNX Runtime or TFLite, still fits A53 budget.
- **Self-hosted Mender migration.** When device count reaches
  5–10k, hosted Mender economics flip. Mender sells an on-prem
  version for this transition.
- **Compliance work.** SOC 2 readiness, HIPAA BAA with any cloud
  vendors that touch PHI (fall events may qualify). Not urgent until
  paid pilots.

---

## Current work surface

EVM arrives in a few days. Productive work during the wait:

1. Define the AM62↔radar interface nets in detail — pin mappings,
   voltage levels, pull-ups, signal integrity requirements. Document
   in `ambientfirmware/docs/interfaces.md` or equivalent. Useful
   before opening Altium.
2. Stripped-down AM62 schematic review — walk through SK-AM62-LP
   schematic and mark every net/component as "keep," "drop," or "TBD."
3. Wi-Fi/BLE module driver maturity check in TI SDK source.

After EVM arrives:

1. Stand up base tisdk image, boot to Linux.
2. Deploy ambientapp against stock SK-AM62-LP via USB-serial radar (bridge from Pi rig).
3. End-to-end smoke test: radar → UART → parser → detector → LogPublisher events.
4. Start schematic in earnest once software stack is proven on EVM.

---

## Behavioral notes (carry forward)

- Concise. No padding, no re-explaining known context.
- Push back when framing is wrong. Examples this session: corrected
  height-column semantics (maxZ not "currentHeight"), surfaced the
  55Hz-vs-18Hz latent bug in legacy detector, flipped OTA
  recommendation when commercial senior-living context emerged.
- `ask_user_input_v0` for clarifying questions with 2–4 options.
- No emojis, no conversational headers, no restated questions.
