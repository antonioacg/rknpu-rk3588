#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Install the RKNPU kernel module via DKMS.
# Requires: dkms, linux-headers-$(uname -r)
# Run as root from the repository root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="${REPO_ROOT}/ref/rknpu-module"
DKMS_NAME="rknpu"
DKMS_VERSION="0.9.8"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

if ! command -v dkms >/dev/null 2>&1; then
    echo "Error: dkms is not installed."
    echo "Install with: apt install dkms"
    exit 1
fi

if [ ! -d "${MODULE_DIR}/src" ]; then
    echo "Error: rknpu-module submodule not found."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Create DKMS source directory
DKMS_SRC="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"
echo "Installing DKMS source to ${DKMS_SRC}..."

rm -rf "${DKMS_SRC}"
cp -r "${MODULE_DIR}" "${DKMS_SRC}"

# Create dkms.conf if not present
if [ ! -f "${DKMS_SRC}/dkms.conf" ]; then
    cat > "${DKMS_SRC}/dkms.conf" <<EOF
PACKAGE_NAME="${DKMS_NAME}"
PACKAGE_VERSION="${DKMS_VERSION}"
BUILT_MODULE_NAME[0]="${DKMS_NAME}"
DEST_MODULE_LOCATION[0]="/kernel/drivers/misc/"
AUTOINSTALL="yes"
MAKE[0]="make KDIR=\${kernel_source_dir}"
CLEAN="make clean"
EOF
fi

# Register and build
dkms add -m "${DKMS_NAME}" -v "${DKMS_VERSION}" 2>/dev/null || true
dkms build -m "${DKMS_NAME}" -v "${DKMS_VERSION}"
dkms install -m "${DKMS_NAME}" -v "${DKMS_VERSION}"

echo ""
echo "DKMS installation complete."
echo "Load with: modprobe rknpu"
