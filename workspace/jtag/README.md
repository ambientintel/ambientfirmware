# JTAG Quick Reference — SK-AM62-LP + XDS110

## Hardware connections

### Stage 1 — JTAG verification only (minimum cables)

J17 is **not required** to run OpenOCD and verify A53 detection.

| Cable | Connector | Purpose |
|-------|-----------|---------|
| USB-C | J13 | Power |
| micro-USB-B | J18 | XDS110 JTAG |

Power the board first (USB-C into J13), then plug J18. J18 enumerates as a Texas Instruments USB device — **no `/dev/tty` entry appears** for J18.

### Stage 2 — JTAG + console (kernel debug)

Add J17 when you need serial console output alongside JTAG (panic traces, printk, interactive U-Boot).
J18 is only needed during active JTAG sessions — unplug it for Steps 15–17 (TFTP/NFS, driver work).

| Cable | Connector | Purpose |
|-------|-----------|---------|
| USB-C | J13 | Power |
| micro-USB-B | J17 | FT4232 UART → 4× `/dev/tty.usbserial-*` |
| micro-USB-B | J18 | XDS110 JTAG |

Both J17 and J18 are micro-USB-B and look identical. J17 produces tty entries; J18 does not.

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

## Verified attach sequence (confirmed 2026-05-17)

**Boot Linux fully before running these steps.** TIFS must run during boot to assert DBGEN and open debug ports. Examine will fail before Linux is up.

```sh
# nc segfaults on macOS — use telnet:
telnet localhost 4444
```

At the `>` prompt, one command at a time:

```sh
# 1. List targets — all show "examine deferred" initially
targets

# 2. Examine A53 core 0 (only works after Linux has booted)
am625.cpu.a53.0 arp_examine
# → am625.cpu.a53.0: hardware has 6 breakpoints, 4 watchpoints

# 3. Halt
am625.cpu.a53.0 arp_halt
# → halted in AArch64 state due to debug-request, current mode: EL1H
# → cpsr: 0xa00003c5 pc: 0xffff800080010a00
# → MMU: enabled, D-Cache: enabled, I-Cache: enabled

# 4. Resume
targets am625.cpu.a53.0
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
