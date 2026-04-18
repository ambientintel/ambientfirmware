# AM62 ↔ IWR6843AOP interface

Nets crossing between the AM62 (host) and IWR6843AOP (radar) subsystems
on the custom board. Written before Altium work begins to have a
reference that doesn't require opening the schematic.

Boot model: **host-fed**. AM62 feeds radar firmware binary over SPI at
boot using TI's SBL protocol. Radar QSPI footprint is DNI.

---

## Interface summary

| Net | Direction | Required v1 | Purpose |
|---|---|---|---|
| RADAR_UART_TX | radar → AM62 | Yes | Primary data stream, 921600 baud |
| RADAR_UART_RX | AM62 → radar | Yes | CLI config send, boot-time config |
| RADAR_NRESET | AM62 → radar | Yes | Hardware reset, active low |
| RADAR_SOP0 | AM62 → radar | Yes | Boot mode select bit 0 |
| RADAR_SOP1 | AM62 → radar | Yes | Boot mode select bit 1 |
| RADAR_SOP2 | AM62 → radar | Yes | Boot mode select bit 2 |
| RADAR_NERROR | radar → AM62 | Yes | Radar fault indicator, active low |
| RADAR_SPI_CLK | AM62 → radar | Yes (host-fed) | SBL firmware transfer + runtime high-BW path |
| RADAR_SPI_MOSI | AM62 → radar | Yes (host-fed) | SBL firmware transfer |
| RADAR_SPI_MISO | radar → AM62 | Yes (host-fed) | SBL ACKs + runtime bidirectional |
| RADAR_SPI_CS | AM62 → radar | Yes (host-fed) | SPI chip select |
| RADAR_HOST_INTR | radar → AM62 | Reserved | Frame-ready interrupt for SPI high-BW path |

All signals are 3.3V logic (verify against final PMIC rail selection —
LP87745 gives IWR6843 IO a 1.8V option that would require level
shifters; keep at 3.3V to avoid that).

---

## UART

- Primary data path: radar's UART TX to AM62 UART RX, 921600 baud, 8N1,
  no flow control.
- Reverse path: AM62 UART TX to radar RX for CLI config at startup.
  The radar's CLI accepts config-file lines at 115200 initially, then
  data streams at 921600 after `sensorStart`. The legacy two-COM-port
  architecture is collapsed into one UART on our board; the radar
  handles mode switching internally.
- AM62-side: use one of the `MAIN_UART*` peripherals. `MAIN_UART0` is
  the default debug console on SK-AM62-LP — don't reuse. `MAIN_UART2`
  or `MAIN_UART3` likely candidates.
- No hardware flow control wired. The Pi rig doesn't use it either.
  Reserve pads for CTS/RTS only if trivial; otherwise skip.

## Reset (NRESET)

- Active-low, asserted pulls radar into reset.
- AM62 drives from a GPIO. `GPIO0_*` pins preferred — always-on domain
  so reset state is deterministic across suspend/resume.
- Pull-up on radar side (datasheet specifies value; follow TI EVM).
- Reset is the only recovery path if the radar becomes unresponsive.
  The app (`RadarUart` class in ambientapp) should toggle this on
  repeated read timeouts.

## SOP[2:0] — boot mode

- Three strapping pins read once at radar power-up. Determine boot
  source.
- For host-fed: typically `SOP = 0b100` (TI doc, confirm from IWR6843
  datasheet — varies by silicon rev).
- Drive from AM62 GPIOs, not hardwired. Reason: we want the option to
  switch to flash boot for debug without rework (if the QSPI DNI parts
  are ever populated).
- Latched at rising edge of NRESET. Set SOP pins before releasing
  reset.

## NERROR

- Active-low fault line from radar. Asserted on internal error
  conditions (ESM, watchdog, etc.).
- Route to an AM62 GPIO with interrupt capability.
- App-layer handler should log + trigger reset sequence if persistently
  asserted.

## SPI

Host-fed boot requires SPI before UART streaming is useful. Also
reserved as a higher-bandwidth runtime path if we ever need to stream
raw ADC data or point clouds faster than UART can carry.

- AM62 master, radar slave. `MCU_SPI*` or `MAIN_SPI*` — pick based on
  pin availability after UART assignment.
- Clock rate: 20–40 MHz for firmware transfer. Radar SBL auto-detects
  within a range.
- Mode: follow IWR6843 SBL spec (typically Mode 0).
- `SPI_CS` is a GPIO-driven chip select, not hardware CS. Gives app
  software control over framing during SBL.

## SPI_HOST_INTR (reserved)

- Radar-to-host interrupt for "frame ready" signaling on the SPI path.
- Route now even if unused v1. Route cost is one trace; value is
  preserving the option without a respin.
- Connect to an AM62 GPIO with interrupt capability.

---

## Pull-ups, level shifting, ESD

- 3.3V logic on both sides (with LP87745 radar IO rail at 3.3V, not
  1.8V). No level shifters.
- NRESET: pull-up on radar side per TI EVM.
- SOP pins: weak internal pull-downs on radar; drive actively from AM62.
- NERROR: pull-up to 3.3V so line is deasserted when radar is off.
- SPI: standard pull-ups on CS recommended.
- ESD: TVS diodes on nets that route near connectors or board edges.
  Internal interconnects (AM62↔radar on the same PCB, not leaving the
  board) don't need ESD protection beyond normal CMOS pad structures.

## Trace routing notes

- UART, SPI, reset, GPIOs — all are low-speed CMOS. No controlled
  impedance needed for these, no length matching. Keep reasonably
  short (<50 mm) and clean.
- The signal-integrity work on this board is **AM62↔LPDDR4**, not
  AM62↔radar. Routing this interface is a non-issue by comparison.

---

## Mapping TBD until SK-AM62-LP arrives

Specific AM62 pin assignments come from the SK-AM62-LP EVM pinout
study. Once the EVM arrives:

1. Identify which MAIN_UART, MAIN_SPI, and GPIO pins are free after
   the stripped-down BOM (no Gigabit PHYs, no HDMI, no audio, etc.).
2. Cross-reference with the TPS65219 PMIC rail availability.
3. Produce a concrete pin-assignment table and add it to this doc.

Until then, specific peripheral instance numbers above are
placeholders.
