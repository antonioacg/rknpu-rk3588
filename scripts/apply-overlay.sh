#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Merge dts/rk3588-rknpu-overlay.dts into the running kernel's board DTB.
#
# Runtime configfs application is not used because the mainline Rocket
# driver binds to the NPU nodes at boot; modifying live driver-bound
# properties via overlay triggers a use-after-free oops. Instead we:
#
#   1. cpp + dtc  -> .dtbo           (uses kernel-headers dt-bindings)
#   2. fdtoverlay -> merged.dtb      (patches rknn_core_0 in place +
#                                     injects the OPP table)
#   3. fdtput -r  -> remove Rocket   (the .dtbo's `/delete-node/` inside
#      core_1/2 + mmu_0/1/2           an overlay fragment is a no-op; we
#                                     strip the nodes post-merge)
#   4. fdtput -d  -> strip stale     (original rknn_core_0 referenced
#      iommus phandle                 rknn_mmu_0 which we just deleted)
#
# The pristine board DTB is backed up to *.dtb.bak on first run so the
# script is idempotent — rerunning it rebuilds from the pristine copy.
#
# Run as root on the target board. Reboot after to activate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY_SRC="${REPO_ROOT}/dts/rk3588-rknpu-overlay.dts"
KVER="$(uname -r)"
KHEADERS="${KHEADERS:-/lib/modules/${KVER}/build}"
DTB_TARGET="${DTB_TARGET:-/boot/dtb/rockchip/rk3588s-orangepi-5-pro.dtb}"

# Rocket sibling nodes to remove and the stale property to strip.
SIBLINGS=(
    /npu@fdac0000
    /npu@fdad0000
    /iommu@fdab9000
    /iommu@fdaca000
    /iommu@fdada000
)
COMBINED_NODE=/npu@fdab0000
STALE_PROP=iommus

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (writes to /boot)." >&2
    exit 1
fi

for tool in cpp dtc fdtoverlay fdtput; do
    if ! command -v "${tool}" >/dev/null; then
        echo "Error: ${tool} not found. Install with: apt install device-tree-compiler cpp" >&2
        exit 1
    fi
done

if [ ! -f "${OVERLAY_SRC}" ]; then
    echo "Error: overlay source not found at ${OVERLAY_SRC}" >&2
    exit 1
fi

if [ ! -d "${KHEADERS}/include/dt-bindings" ]; then
    echo "Error: dt-bindings not found at ${KHEADERS}/include/dt-bindings" >&2
    echo "Install: apt install linux-headers-${KVER}" >&2
    exit 1
fi

# Resolve the real DTB (follow symlink so we back up the actual file).
if [ -L "${DTB_TARGET}" ]; then
    DTB_TARGET="$(readlink -f "${DTB_TARGET}")"
fi
if [ ! -f "${DTB_TARGET}" ]; then
    echo "Error: target DTB not found at ${DTB_TARGET}" >&2
    echo "Override with: DTB_TARGET=/path/to/board.dtb $0" >&2
    exit 1
fi

DTB_BAK="${DTB_TARGET}.bak"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "Overlay source : ${OVERLAY_SRC}"
echo "Kernel headers : ${KHEADERS}"
echo "Target DTB     : ${DTB_TARGET}"
echo "Backup         : ${DTB_BAK}"
echo ""

# Idempotent pristine backup.
if [ ! -f "${DTB_BAK}" ]; then
    echo "Saving pristine DTB to ${DTB_BAK}"
    cp "${DTB_TARGET}" "${DTB_BAK}"
else
    echo "Pristine backup already exists, reusing it"
fi

echo "Preprocessing overlay..."
cpp -nostdinc \
    -I "${KHEADERS}/include" \
    -undef -x assembler-with-cpp \
    "${OVERLAY_SRC}" \
    -o "${WORK}/overlay.pp.dts"

echo "Compiling .dtbo..."
dtc -@ -I dts -O dtb \
    -o "${WORK}/overlay.dtbo" \
    "${WORK}/overlay.pp.dts" 2>&1 | grep -v '^\(\S.*: \)\?Warning' || true

echo "Merging onto pristine DTB..."
cp "${DTB_BAK}" "${WORK}/merged.dtb"
fdtoverlay -i "${DTB_BAK}" -o "${WORK}/merged.dtb" "${WORK}/overlay.dtbo"

echo "Removing mainline Rocket sibling nodes..."
for node in "${SIBLINGS[@]}"; do
    if fdtput -r "${WORK}/merged.dtb" "${node}" 2>/dev/null; then
        echo "  removed ${node}"
    else
        echo "  (absent) ${node}"
    fi
done

echo "Stripping stale ${STALE_PROP} phandle from ${COMBINED_NODE}..."
fdtput -d "${WORK}/merged.dtb" "${COMBINED_NODE}" "${STALE_PROP}" 2>/dev/null \
    || echo "  (already absent)"

echo "Installing merged DTB..."
install -m 0644 "${WORK}/merged.dtb" "${DTB_TARGET}"

echo ""
echo "Done. Reboot to activate the overlay."
