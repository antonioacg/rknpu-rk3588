#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Install the RKNPU kernel module via DKMS so it survives reboots and
# auto-rebuilds on kernel upgrades.
#
# Stages ref/rknpu-module under /usr/src/rknpu-<VER>/, applies every
# patches/*.patch (same set scripts/build-module.sh applies), then
# registers + builds + installs via dkms. Idempotent — re-running
# removes the previous registration first and rebuilds cleanly.
#
# Run as root. Requires: dkms, patch, linux-headers-$(uname -r).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_SRC="${REPO_ROOT}/ref/rknpu-module"
PATCHES_DIR="${REPO_ROOT}/patches"
DKMS_NAME="rknpu"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root." >&2
    exit 1
fi

for tool in dkms patch; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Error: '${tool}' not found. Install with: apt install ${tool}" >&2
        exit 1
    fi
done

if [ ! -f "${MODULE_SRC}/dkms.conf" ]; then
    echo "Error: ${MODULE_SRC}/dkms.conf not found." >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 1
fi

# Read version from the submodule's dkms.conf so we track whatever
# w568w ships (currently 0.9.8).
DKMS_VERSION="$(awk -F'"' '/^PACKAGE_VERSION=/ {print $2; exit}' "${MODULE_SRC}/dkms.conf")"
if [ -z "${DKMS_VERSION}" ]; then
    echo "Error: could not parse PACKAGE_VERSION from ${MODULE_SRC}/dkms.conf" >&2
    exit 1
fi
DKMS_SRC="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"

# Remove any previous registration for this version cleanly.
if dkms status "${DKMS_NAME}/${DKMS_VERSION}" 2>/dev/null | grep -q "${DKMS_NAME}"; then
    echo "Removing existing DKMS registration ${DKMS_NAME}/${DKMS_VERSION}..."
    dkms remove -m "${DKMS_NAME}" -v "${DKMS_VERSION}" --all 2>/dev/null || true
fi

echo "Staging module source..."
echo "  From: ${MODULE_SRC}"
echo "  To:   ${DKMS_SRC}"
rm -rf "${DKMS_SRC}"
cp -r "${MODULE_SRC}" "${DKMS_SRC}"

# Apply patches to the staged tree — NOT the submodule (which stays
# pristine per project policy).
if [ -d "${PATCHES_DIR}" ]; then
    shopt -s nullglob
    patches=("${PATCHES_DIR}"/*.patch)
    shopt -u nullglob
    if [ ${#patches[@]} -gt 0 ]; then
        echo ""
        echo "Applying patches..."
        for p in "${patches[@]}"; do
            echo "  $(basename "${p}")"
            patch --quiet -d "${DKMS_SRC}" -p1 < "${p}"
        done
    fi
fi

echo ""
echo "Registering with DKMS..."
dkms add -m "${DKMS_NAME}" -v "${DKMS_VERSION}"

echo ""
echo "Building..."
dkms build -m "${DKMS_NAME}" -v "${DKMS_VERSION}"

echo ""
echo "Installing..."
dkms install -m "${DKMS_NAME}" -v "${DKMS_VERSION}"

echo ""
echo "=== DKMS status ==="
dkms status "${DKMS_NAME}/${DKMS_VERSION}"

echo ""
echo "Load now with:  sudo modprobe rknpu"
echo "The module will auto-load on boot if /etc/modules-load.d/ has it,"
echo "and auto-rebuild on kernel upgrades via the DKMS hook."
