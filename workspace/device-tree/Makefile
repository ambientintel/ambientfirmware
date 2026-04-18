# Build glue for the ambient device tree.
#
# Keeps the custom DTS out of the kernel source tree. This Makefile copies
# the DTS into the kernel's arch/arm64/boot/dts/ti/ directory, ensures the
# kernel Makefile builds it, and invokes the kernel's dtbs target.
#
# Expected environment:
#   KERNEL_SRC    Path to the kernel source tree (TI SDK kernel).
#   ARCH          arm64 (default).
#   CROSS_COMPILE aarch64-oe-linux- (default; matches TI Arago toolchain).
#
# Typical usage from workspace/device-tree/:
#   source /workspace/sdk/ti-processor-sdk-linux-am62xx-evm/kernel-env.sh
#   make build KERNEL_SRC=/path/to/ti-linux-kernel

DTS_NAME      := k3-am62-lp-sk-ambient
DTS_FILE      := $(DTS_NAME).dts
DTB_FILE      := $(DTS_NAME).dtb

KERNEL_SRC    ?=
ARCH          ?= arm64
CROSS_COMPILE ?= aarch64-oe-linux-

DT_SUBDIR     := arch/arm64/boot/dts/ti
KERNEL_DT_DIR := $(KERNEL_SRC)/$(DT_SUBDIR)
KERNEL_MK     := $(KERNEL_DT_DIR)/Makefile

ANCHOR_LINE   := dtb-$$(CONFIG_ARCH_K3) += k3-am62-lp-sk.dtb
NEW_LINE      := dtb-$$(CONFIG_ARCH_K3) += $(DTB_FILE)

.PHONY: all install build clean check help

all: build

help:
	@echo "Targets:"
	@echo "  install  Copy DTS into kernel tree and register it in the kernel Makefile."
	@echo "  build    install + invoke kernel 'make dtbs' to produce $(DTB_FILE)."
	@echo "  clean    Remove the installed DTS and Makefile entry from the kernel tree."
	@echo "  check    Verify KERNEL_SRC looks like a kernel tree."
	@echo ""
	@echo "Required: KERNEL_SRC=<path to kernel source>"

check:
	@if [ -z "$(KERNEL_SRC)" ]; then \
		echo "ERROR: KERNEL_SRC is not set."; exit 1; \
	fi
	@if [ ! -f "$(KERNEL_MK)" ]; then \
		echo "ERROR: $(KERNEL_MK) not found. Is KERNEL_SRC correct?"; exit 1; \
	fi
	@if ! grep -Fxq '$(ANCHOR_LINE)' $(KERNEL_MK); then \
		echo "ERROR: anchor line not found in $(KERNEL_MK):"; \
		echo "       $(ANCHOR_LINE)"; \
		echo "       Kernel Makefile format may have changed; update ANCHOR_LINE."; \
		exit 1; \
	fi

install: check
	@echo ">> Copying $(DTS_FILE) -> $(KERNEL_DT_DIR)/"
	cp -f $(DTS_FILE) $(KERNEL_DT_DIR)/$(DTS_FILE)
	@if grep -Fxq '$(NEW_LINE)' $(KERNEL_MK); then \
		echo ">> $(DTB_FILE) already registered in kernel Makefile."; \
	else \
		echo ">> Registering $(DTB_FILE) in kernel Makefile."; \
		awk -v anchor='$(ANCHOR_LINE)' -v newline='$(NEW_LINE)' \
		    '{ print } $$0 == anchor { print newline }' \
		    $(KERNEL_MK) > $(KERNEL_MK).new && \
		mv $(KERNEL_MK).new $(KERNEL_MK); \
	fi

build: install
	@echo ">> Building DTBs in $(KERNEL_SRC)"
	$(MAKE) -C $(KERNEL_SRC) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) dtbs
	@echo ">> Built: $(KERNEL_DT_DIR)/$(DTB_FILE)"

clean: check
	@echo ">> Removing $(DTS_FILE) from kernel tree"
	rm -f $(KERNEL_DT_DIR)/$(DTS_FILE)
	@echo ">> Removing any $(DTB_FILE) entries from kernel Makefile"
	@grep -vF '$(NEW_LINE)' $(KERNEL_MK) > $(KERNEL_MK).new && \
		mv $(KERNEL_MK).new $(KERNEL_MK)
