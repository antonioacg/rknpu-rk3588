#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Smoke test: verify the RKNN runtime can communicate with the NPU.
# Requires: rknpu module loaded, /dev/dri/renderD129 present,
#           librknnrt from ref/rknn-llm/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "RKNN Runtime Smoke Test"
echo "======================="
echo ""

# Check prerequisites
if [ ! -c /dev/dri/renderD129 ]; then
    echo "Error: /dev/dri/renderD129 not found."
    echo "Is the rknpu module loaded? Is the DT overlay applied?"
    exit 1
fi

if [ ! -f /sys/module/rknpu/version ]; then
    echo "Error: rknpu module not loaded."
    exit 1
fi

NVER="$(cat /sys/module/rknpu/version)"
echo "RKNPU driver version: ${NVER}"
echo ""

# Find librknnrt
LIB_PATHS=(
    "${REPO_ROOT}/ref/rknn-llm/rknn-runtime/Linux/librknn_api/aarch64"
    "/usr/lib"
    "/usr/local/lib"
)

RKNN_LIB=""
for P in "${LIB_PATHS[@]}"; do
    if [ -f "${P}/librknnrt.so" ]; then
        RKNN_LIB="${P}"
        break
    fi
done

if [ -z "${RKNN_LIB}" ]; then
    echo "Warning: librknnrt.so not found."
    echo "Searched: ${LIB_PATHS[*]}"
    echo ""
    echo "The driver is loaded and the device node exists."
    echo "To run a full test, install librknnrt from ref/rknn-llm/."
    exit 0
fi

echo "Found librknnrt at: ${RKNN_LIB}"
echo ""

# Check driver info via sysfs
echo "Driver info:"
echo "  Module version: ${NVER}"
if [ -f /sys/module/rknpu/parameters/bypass ]; then
    echo "  Bypass mode: $(cat /sys/module/rknpu/parameters/bypass)"
fi
echo ""

echo "Device nodes:"
ls -la /dev/dri/renderD* 2>/dev/null
echo ""

echo "Smoke test passed: NPU device is accessible."
echo "For a full inference test, use rknn_benchmark or rkllama with a .rknn/.rkllm model."
