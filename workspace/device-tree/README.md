# Ambient Device Tree

This directory holds the ambient-specific device tree source for the
AM62x-LP hardware. It is kept **out of the kernel source tree** and copied in
at build time, so the kernel tree stays a pristine checkout of the TI SDK
kernel.

## Files

- `k3-am625-sk-lp-ambient.dts` — the ambient DTS. Starts as a thin overlay
  that `#include`s the stock `k3-am625-sk-lp.dts` and overrides only the
  `compatible` and `model` strings. Sensor nodes and custom pinmux are added
  here as hardware work progresses.
- `Makefile` — build glue. Copies the DTS into the kernel tree, patches the
  kernel's `arch/arm64/boot/dts/ti/Makefile` to build it, and invokes
  `make dtbs`.

## Usage

From this directory:

```
make build KERNEL_SRC=<path to TI SDK kernel source>
```

For example, if the SDK is unpacked at
`~/ti-am62x/ti-processor-sdk-linux-am62x/`:

```
make build KERNEL_SRC=~/ti-am62x/ti-processor-sdk-linux-am62x/board-support/linux
```

The resulting DTB lands at
`$KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am625-sk-lp-ambient.dtb`, alongside
the stock `k3-am625-sk-lp.dtb`.

## Why out-of-tree

- The kernel tree stays clean and can be re-fetched or bumped without losing
  ambient changes.
- DT changes live in the same repo as the rest of the ambient firmware
  source, versioned together.
- One `make clean` reverses the install cleanly.

## Why not a DT overlay (`.dtbo`)

Overlays are a fit when the base DTS is fixed and changes are applied at
runtime (e.g., U-Boot `fdt apply`). At this stage the ambient hardware
diverges from SK-LP only in identification, and the differences will grow as
sensors are added. A full DTS that `#include`s the upstream SK-LP DTS is
simpler to reason about, easier to debug with `fdtdump`, and avoids
runtime-apply complexity during bring-up. Revisit if the divergence stays
small and overlays become preferable.

## Boot configuration

The stock `k3-am625-sk-lp.dtb` remains the default boot target until
explicitly switched. This keeps a known-good fallback for the first power-on
of the board. To boot the ambient DTB, update the `fdtfile` environment in
U-Boot or the `fdt` line in `extlinux.conf` to point at
`k3-am625-sk-lp-ambient.dtb`. See `workspace/docs/DEVICETREE.md` for
details.

## Verifying a build without the board

```
# After 'make build', decompile and sanity-check:
dtc -I dtb -O dts -o /tmp/ambient.dts \
    $KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am625-sk-lp-ambient.dtb
grep -E 'model|compatible' /tmp/ambient.dts | head
```

You should see the ambient `model` and `compatible` strings at the root
node.
