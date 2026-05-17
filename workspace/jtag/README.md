# JTAG Quick Reference — SK-AM62-LP + XDS110

## Hardware

- J17 (FT4232, micro-USB-B) → UART console — keep connected
- J18 (XDS110, micro-USB-B) → JTAG — second USB cable
- Power board first via J13 (USB-C), then plug J18

The two ports look identical. J17 produces 4 `/dev/tty.usbserial-*` entries.
J18 enumerates as a Texas Instruments USB device (no tty).

## Start OpenOCD (on Mac, outside Docker)

```sh
# From ambientfirmware/ repo root
openocd -f workspace/jtag/am625-xds110.cfg
```

Successful output includes:
```
Info : XDS110: connected
Info : XDS110: firmware version ...
Info : [am625.cpu.a53.0] Cortex-A53 r0p4 processor detected
Info : [am625.cpu.a53.1] Cortex-A53 r0p4 processor detected
Info : [am625.cpu.a53.2] Cortex-A53 r0p4 processor detected
Info : [am625.cpu.a53.3] Cortex-A53 r0p4 processor detected
Info : Listening on port 3333 for gdb connections
```

## Quick verification (no GDB needed)

```sh
# In a second terminal, while OpenOCD is running:
nc localhost 4444

# In the telnet console:
targets                         # list all targets and state
am625.cpu.a53.0 halt            # halt core 0
am625.cpu.a53.0 reg pc          # read program counter
am625.cpu.a53.0 resume          # resume

# Read 10 words at DTB load address (typical 0x88000000)
am625.cpu.a53.0 halt
mdw 0x88000000 10
resume
```

## Kernel debug with GDB (from inside Docker container)

```sh
# OpenOCD running on Mac; container reaches it via host.docker.internal
# Run in container:
aarch64-oe-linux-gdb vmlinux -x /workspace/jtag/gdb-kernel.init

# Or interactively:
aarch64-oe-linux-gdb vmlinux
(gdb) target extended-remote host.docker.internal:3334
(gdb) monitor halt
(gdb) info registers
(gdb) hbreak start_kernel      # hardware breakpoint at kernel init
(gdb) continue
```

## GDB port map

| Port | Target | Core type |
|------|--------|-----------|
| 3333 | sysctrl | Cortex-M3 (System Controller) |
| 3334 | a53.0 | Cortex-A53 ← kernel debug |
| 3335 | a53.1 | Cortex-A53 |
| 3336 | a53.2 | Cortex-A53 |
| 3337 | a53.3 | Cortex-A53 |
| 3338 | main0_r5.0 | Cortex-R5F (DMSC/SBL) |
| 3339 | gp_mcu | Cortex-M4F |

## Adapter speed

Start at 1 MHz (default in `am625-xds110.cfg`). Once link is verified:

```sh
# In OpenOCD telnet console:
adapter speed 4000   # 4 MHz — reliable for most sessions
adapter speed 8000   # 8 MHz — max for XDS110; try if 4 MHz is stable
```

## Key debug use cases

- **Kernel panic before console**: JTAG can read registers and stack trace even if UART is silent
- **DDR bring-up debugging** (custom board): attach R5 core before A53 is running; inspect training registers
- **IWR6843AOP driver**: set breakpoint in `probe()` to catch driver bind failure
- **Silent boot**: read UART status registers directly to bypass console dependency
