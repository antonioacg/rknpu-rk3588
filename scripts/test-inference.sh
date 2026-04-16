#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# End-to-end inference smoke test: downloads the vendor RKNN runtime
# (librknnrt.so) and a prebuilt MobileNet v1 .rknn model from
# airockchip/rknn-toolkit2, compiles tests/rknn_smoke.c against them,
# and runs it.
#
# Purpose: validate that the vendor RKNN SDK actually drives our ported
# kernel module — i.e. the whole reason this project exists. A clean
# `insmod` + `/dev/dri/renderD129` tells you the driver loaded; this
# script tells you an RKNN model can actually execute on the NPU.
#
# Safe to re-run. Downloaded artifacts are cached under build/rknn-runtime/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${REPO_ROOT}/build/rknn-runtime"
TEST_SRC="${REPO_ROOT}/tests/rknn_smoke.c"

# airockchip/rknn-toolkit2 raw asset URLs (pin to master at time of writing).
UPSTREAM=https://raw.githubusercontent.com/airockchip/rknn-toolkit2/master
LIB_URL="${UPSTREAM}/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so"
HDR_URL="${UPSTREAM}/rknpu2/runtime/Linux/librknn_api/include/rknn_api.h"
MODEL_URL="${UPSTREAM}/rknpu2/examples/rknn_mobilenet_demo/model/RK3588/mobilenet_v1.rknn"

ITERS="${ITERS:-200}"
CORE_MASK="${CORE_MASK:-auto}"   # auto | 0 | 1 | 2 | 0_1_2

if [ ! -c /dev/dri/renderD129 ]; then
    echo "Error: /dev/dri/renderD129 not found — load rknpu.ko first." >&2
    exit 1
fi

if [ ! -f "${TEST_SRC}" ]; then
    echo "Error: test source missing at ${TEST_SRC}" >&2
    exit 1
fi

mkdir -p "${WORK_DIR}"

fetch() {
    local url="$1" dest="$2"
    if [ -s "${dest}" ]; then
        echo "  cached: $(basename "${dest}")"
    else
        echo "  fetching: $(basename "${dest}")"
        curl -fsSL -o "${dest}" "${url}"
    fi
}

echo "Downloading vendor runtime + model..."
fetch "${LIB_URL}"   "${WORK_DIR}/librknnrt.so"
fetch "${HDR_URL}"   "${WORK_DIR}/rknn_api.h"
fetch "${MODEL_URL}" "${WORK_DIR}/mobilenet_v1.rknn"
echo ""

echo "Compiling test..."
cp "${TEST_SRC}" "${WORK_DIR}/rknn_smoke.c"
gcc "${WORK_DIR}/rknn_smoke.c" \
    -I"${WORK_DIR}" -L"${WORK_DIR}" -lrknnrt \
    -o "${WORK_DIR}/rknn_smoke"
echo ""

# Snapshot NPU interrupt counters before/after so the user can confirm
# the NPU hardware actually woke up.
snap_irq() {
    grep "fdab0000.npu" /proc/interrupts \
        | awk '{s=0; for(i=2;i<=9;i++) s+=$i; printf "  %s total=%d\n", $1, s}'
}

echo "--- NPU interrupt counters BEFORE ---"
snap_irq
echo ""

echo "--- Inference run (iters=${ITERS}, core_mask=${CORE_MASK}) ---"
LD_LIBRARY_PATH="${WORK_DIR}" \
    "${WORK_DIR}/rknn_smoke" "${WORK_DIR}/mobilenet_v1.rknn" "${ITERS}" "${CORE_MASK}"
echo ""

echo "--- NPU interrupt counters AFTER ---"
snap_irq
echo ""

echo "Done. Non-zero interrupt deltas on virq 146/147/148 mean the NPU actually executed."
echo "For live monitoring, run (separate terminal):"
echo "  sudo watch -n 0.5 ${REPO_ROOT}/scripts/watch-npu.sh"
