#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the RKNPU kernel module.
#
# The w568w/rknpu-module submodule under ref/ must stay pristine, so
# this script stages a copy under build/rknpu-module/, applies the
# patches in patches/*.patch, then invokes the vendor Makefile there.
# Re-running refreshes the staging tree from the submodule.
#
# Run from the repository root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_SRC="${REPO_ROOT}/ref/rknpu-module"
PATCHES_DIR="${REPO_ROOT}/patches"
BUILD_DIR="${REPO_ROOT}/build/rknpu-module"
KDIR="${KDIR:-/lib/modules/$(uname -r)/build}"

if [ ! -d "${MODULE_SRC}/src" ]; then
    echo "Error: rknpu-module submodule not found at ${MODULE_SRC}" >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 1
fi

if [ ! -d "${KDIR}" ]; then
    echo "Error: Kernel headers not found at ${KDIR}" >&2
    echo "Install with: apt install linux-headers-$(uname -r)" >&2
    exit 1
fi

if ! command -v patch >/dev/null 2>&1; then
    echo "Error: 'patch' command not found." >&2
    echo "Install with: apt install patch" >&2
    exit 1
fi

echo "Staging module source..."
echo "  From: ${MODULE_SRC}"
echo "  To:   ${BUILD_DIR}"
rm -rf "${BUILD_DIR}"
mkdir -p "$(dirname "${BUILD_DIR}")"
cp -r "${MODULE_SRC}" "${BUILD_DIR}"

if [ -d "${PATCHES_DIR}" ]; then
    shopt -s nullglob
    patches=("${PATCHES_DIR}"/*.patch)
    shopt -u nullglob
    if [ ${#patches[@]} -gt 0 ]; then
        echo ""
        echo "Applying patches from ${PATCHES_DIR}/..."
        for p in "${patches[@]}"; do
            echo "  $(basename "${p}")"
            patch --quiet -d "${BUILD_DIR}" -p1 < "${p}"
        done
    fi
fi

echo ""
echo "Building module..."
echo "  Kernel headers: ${KDIR}"

cd "${BUILD_DIR}"

if [ -n "${CROSS_COMPILE:-}" ]; then
    make ARCH="${ARCH:-arm64}" CROSS_COMPILE="${CROSS_COMPILE}" KDIR="${KDIR}"
else
    make KDIR="${KDIR}"
fi

echo ""
echo "Build complete: ${BUILD_DIR}/rknpu.ko"
ls -la "${BUILD_DIR}/rknpu.ko"
