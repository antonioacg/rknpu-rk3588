#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the RKNPU kernel module using w568w/rknpu-module's Makefile.
# Run from the repository root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="${REPO_ROOT}/ref/rknpu-module"
KDIR="${KDIR:-/lib/modules/$(uname -r)/build}"

if [ ! -d "${MODULE_DIR}/src" ]; then
    echo "Error: rknpu-module submodule not found at ${MODULE_DIR}"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if [ ! -d "${KDIR}" ]; then
    echo "Error: Kernel headers not found at ${KDIR}"
    echo "Install with: apt install linux-headers-$(uname -r)"
    exit 1
fi

echo "Building RKNPU module..."
echo "  Module source: ${MODULE_DIR}"
echo "  Kernel headers: ${KDIR}"
echo ""

cd "${MODULE_DIR}"

if [ -n "${CROSS_COMPILE:-}" ]; then
    make ARCH="${ARCH:-arm64}" CROSS_COMPILE="${CROSS_COMPILE}" KDIR="${KDIR}"
else
    make KDIR="${KDIR}"
fi

echo ""
echo "Build complete."
ls -la rknpu.ko 2>/dev/null && echo "Module: ${MODULE_DIR}/rknpu.ko"
