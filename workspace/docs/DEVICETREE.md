# Device Tree Strategy

Companion doc to `BOOT_DAY_RUNBOOK.md`. Covers how the ambient device tree
is organized, how it is built, and how to switch the board between the
stock SK-LP DTB and the ambient DTB.

## Layout

The ambient DTS lives in the project repo, not in the kernel source tree:

```
workspace/device-tree/
├── k3-am62-lp-sk-ambient.dts   # the DTS (overlay-style via #include)
├── Makefile                     # copy-in + build glue
└── README.md                    # directory-local usage notes
```

The kernel source tree (unpacked from the TI Processor SDK Linux AM62x
11.02.08.02) is treated as a read-mostly artifact. The ambient DTS is
copied into `arch/arm64/boot/dts/ti/` and registered in that directory's
Makefile by `workspace/device-tree/Makefile`. A `make clean` reverses both
steps.

## Why this shape

- **Kernel tree stays clean.** No ambient changes living inside the SDK
  kernel checkout means SDK bumps are a re-extract, not a rebase.
- **DT is versioned with firmware.** The DTS evolves alongside the sensor
  drivers, userspace tooling, and boot scripts it depends on; keeping them
  in one repo avoids split-brain history.
- **Thin overlay, not a rewrite.** The ambient DTS `#include`s
  `k3-am62-lp-sk.dts` and only overrides `compatible` and `model` at the
  root. Sensor and pinmux additions append below that.
- **DTS, not `.dtbo` overlay, for now.** Runtime overlay application is
  useful when the base is fixed; the ambient hardware will diverge from
  SK-LP over time, so a full DTS is simpler. Reconsider if divergence
  stays narrow.

## Build workflow

From `workspace/device-tree/`:

```
make build KERNEL_SRC=<path to SDK kernel source>
```

What this does, in order:

1. Copies `k3-am62-lp-sk-ambient.dts` into
   `$KERNEL_SRC/arch/arm64/boot/dts/ti/`.
2. Appends a `dtb-$(CONFIG_ARCH_K3) += k3-am62-lp-sk-ambient.dtb` line to
   the kernel's `arch/arm64/boot/dts/ti/Makefile`, next to the stock
   `k3-am62-lp-sk.dtb` entry. A `.ambient-bak` backup is left behind so
   `make clean` can restore the original.
3. Invokes the kernel's `dtbs` target with
   `ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-`.

Output:
`$KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb`.

### Sanity check without hardware

```
dtc -I dtb -O dts -o /tmp/ambient.dts \
    $KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb
grep -E 'model|compatible' /tmp/ambient.dts | head
```

Expect to see:

```
compatible = "ambientintel,am62x-lp", "ti,am625-sk-lp", "ti,am625";
model = "Ambient Intel AM62x-LP";
```

## Boot-time DTB selection

The stock `k3-am62-lp-sk.dtb` remains the default boot target. The
ambient DTB is built and placed next to it, but is not selected until
explicitly switched. This preserves a known-good fallback for first power-
on of the board (see `BOOT_DAY_RUNBOOK.md`).

Two ways to switch, depending on which boot path is in use:

### 1. U-Boot `fdtfile` env

At the U-Boot prompt:

```
=> setenv fdtfile ti/k3-am62-lp-sk-ambient.dtb
=> saveenv
=> boot
```

Revert by setting `fdtfile` back to `ti/k3-am62-lp-sk.dtb`.

### 2. `extlinux.conf` (distro boot)

Edit `/boot/extlinux/extlinux.conf` on the SD card's boot partition. Add
or duplicate a `LABEL` block with the ambient FDT:

```
LABEL ambient
    KERNEL /Image
    FDT    /ti/k3-am62-lp-sk-ambient.dtb
    APPEND root=/dev/mmcblk1p2 rw rootwait console=ttyS2,115200n8

DEFAULT ambient
```

Keep a `LABEL stock` block pointing at `k3-am62-lp-sk.dtb` and toggle
`DEFAULT` between them. This gives a one-line revert path if the ambient
DTB misbehaves.

### Verifying which DTB the kernel booted

Once Linux is up:

```
cat /proc/device-tree/model
cat /proc/device-tree/compatible | tr '\0' '\n'
```

Ambient DTB → `Ambient Intel AM62x-LP` and the
`ambientintel,am62x-lp` compatible string at the head of the list.

## Adding sensors later

When hardware is in hand and a sensor is being wired up:

1. Identify the bus (I²C, SPI, GPIO) and the SoC controller node in the
   stock SK-LP DTS (`main_i2c1`, `main_spi0`, etc.).
2. In `k3-am62-lp-sk-ambient.dts`, reference the controller with `&label`
   and add the child node.
3. If pinmux differs from the SK-LP defaults, add a pins group under
   `&main_pmx0` (or `&mcu_pmx0`) and reference it with `pinctrl-0`.
4. Rebuild (`make build`), boot with the ambient DTB, confirm the driver
   binds (`dmesg | grep <driver>`, `ls /sys/bus/i2c/devices/`).

Commented placeholder blocks in the DTS show the shape.

## Gotchas

- The kernel Makefile edit is a literal `sed` append. If the stock
  `k3-am62-lp-sk.dtb` entry is not present (SDK version drift,
  reorganized tree), `make install` will silently not register the new
  DTB. Verify by grepping the kernel Makefile after install.
- Do not commit the kernel tree's modified Makefile. The edit is a build
  artifact; `make clean` in `workspace/device-tree/` reverses it.
- If U-Boot loads the DTB from a FIT image rather than a loose file, the
  `fdtfile` env approach does not apply — update the FIT description
  instead. The current TI SDK boot flow uses loose DTBs, so this is a
  future concern.
