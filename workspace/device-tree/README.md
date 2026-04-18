# Ambient Device Tree

This directory holds the ambient-specific device tree source for the AM62x-LP hardware. It is kept out of the kernel source tree and copied in at build time, so the kernel tree stays a pristine checkout of the TI SDK kernel.

## Files

* `k3-am62-lp-sk-ambient.dts` — the ambient DTS. Starts as a thin overlay that `#include`s the stock `k3-am62-lp-sk.dts` and overrides only the `compatible` and `model` strings. Sensor nodes and custom pinmux are added here as hardware work progresses.
* `Makefile` — build glue. Copies the DTS into the kernel tree, registers it in the kernel's `arch/arm64/boot/dts/ti/Makefile` via `awk` exact-line insertion, and invokes `make dtbs`.

## Naming convention

TI's upstream uses `am62-lp-sk` (SoC family + LP variant + board class), not `am625-sk-lp`. The intuitive-but-wrong order does not exist in the kernel tree. Any new derived DTS must `#include` the real upstream filename or the C preprocessor fails before DTC runs.

## Usage

From this directory, with the kernel build environment sourced:

```
source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
make build KERNEL_SRC=$KERNEL_SRC
```

Or pass `KERNEL_SRC` explicitly:

```
make build KERNEL_SRC=/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/board-support/ti-linux-kernel-6.12.57+git-ti
```

The resulting DTB lands at `$KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb`, alongside the stock `k3-am62-lp-sk.dtb`.

The build is idempotent — re-running is safe. The Makefile validates the kernel-Makefile anchor line up front, so future SDK format changes fail loudly rather than silently no-op.

## Why out-of-tree

* The kernel tree stays clean and can be re-fetched or bumped without losing ambient changes.
* DT changes live in the same repo as the rest of the ambient firmware source, versioned together.
* `make clean` reverses the install cleanly.

## Why not a DT overlay (`.dtbo`)

Overlays are a fit when the base DTS is fixed and changes are applied at runtime (e.g., U-Boot `fdt apply`). At this stage the ambient hardware diverges from SK-LP only in identification, and the differences will grow as sensors are added. A full DTS that `#include`s the upstream SK-LP DTS is simpler to reason about, easier to debug with `fdtdump`, and avoids runtime-apply complexity during bring-up. Revisit if the divergence stays small and overlays become preferable.

## Boot configuration

The stock `k3-am62-lp-sk.dtb` remains the default boot target until explicitly switched. This keeps a known-good fallback for the first power-on of the board. To boot the ambient DTB, update the `fdtfile` environment in U-Boot or the `fdt` line in `extlinux.conf` to point at `k3-am62-lp-sk-ambient.dtb`. See `workspace/docs/DEVICETREE.md` for details.

## Verifying a build without the board

```
# After 'make build', decompile and sanity-check:
$KERNEL_SRC/scripts/dtc/dtc -I dtb -O dts \
    $KERNEL_SRC/arch/arm64/boot/dts/ti/k3-am62-lp-sk-ambient.dtb 2>/dev/null | head -10
```

You should see the ambient `model` and `compatible` strings at the root node:

```
model = "Ambient Intel AM62x-LP";
compatible = "ambientintel,am62x-lp", "ti,am62-lp-sk", "ti,am625";
```

The compatible chain runs most-specific → upstream board → SoC, giving kernel matchers and userspace ID code the right fallback ladder.
