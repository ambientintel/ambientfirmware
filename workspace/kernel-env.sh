#!/bin/bash
# Source this for kernel/U-Boot builds only.
# Do NOT source linux-devkit/environment-setup together with this.
export PATH=/workspace/sdk/ti-processor-sdk-linux-am62xx-evm/linux-devkit/sysroots/x86_64-arago-linux/usr/bin/aarch64-oe-linux:$PATH
export ARCH=arm64
export CROSS_COMPILE=aarch64-oe-linux-
echo "Kernel build environment ready."
echo "  ARCH=$ARCH"
echo "  CROSS_COMPILE=$CROSS_COMPILE"
echo "  $(aarch64-oe-linux-gcc --version | head -1)"
