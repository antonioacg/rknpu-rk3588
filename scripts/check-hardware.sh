#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Verify that the current system has RK3588 NPU hardware and
# the necessary kernel/firmware support for the RKNPU driver.

set -euo pipefail

PASS=0
WARN=0
FAIL=0

check_pass() { echo "  [OK]   $1"; PASS=$((PASS + 1)); }
check_warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }
check_fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "RK3588 NPU Hardware Check"
echo "========================="
echo ""

# 1. Check SoC compatibility
echo "SoC:"
if [ -f /proc/device-tree/compatible ]; then
    COMPAT="$(tr '\0' ' ' < /proc/device-tree/compatible)"
    echo "  compatible: ${COMPAT}"
    if echo "${COMPAT}" | grep -q "rk3588"; then
        check_pass "RK3588 SoC detected"
    else
        check_fail "Not an RK3588 system (found: ${COMPAT})"
    fi
else
    check_fail "/proc/device-tree/compatible not found"
fi
echo ""

# 2. Check kernel version
echo "Kernel:"
KVER="$(uname -r)"
echo "  version: ${KVER}"
KMAJOR="$(echo "${KVER}" | cut -d. -f1)"
KMINOR="$(echo "${KVER}" | cut -d. -f2)"
if [ "${KMAJOR}" -gt 6 ] || { [ "${KMAJOR}" -eq 6 ] && [ "${KMINOR}" -ge 19 ]; }; then
    check_pass "Kernel ${KVER} is 6.19+"
elif [ "${KMAJOR}" -eq 6 ] && [ "${KMINOR}" -le 1 ]; then
    check_warn "Kernel ${KVER} — BSP kernel, NPU likely already in-tree"
else
    check_warn "Kernel ${KVER} — not tested, may or may not work"
fi
echo ""

# 3. Check kernel headers
echo "Kernel headers:"
if [ -d "/lib/modules/${KVER}/build" ]; then
    check_pass "Headers found at /lib/modules/${KVER}/build"
else
    check_fail "Headers not found — install linux-headers-${KVER}"
fi
echo ""

# 4. Check NPU device tree node
echo "Device tree:"
if [ -d /proc/device-tree/npu@fdab0000 ]; then
    check_pass "NPU node present at /proc/device-tree/npu@fdab0000/"
else
    check_warn "NPU node not in device tree — overlay needed"
fi
echo ""

# 5. Check RKNPU module
echo "RKNPU module:"
if [ -f /sys/module/rknpu/version ]; then
    NVER="$(cat /sys/module/rknpu/version)"
    check_pass "rknpu loaded, version ${NVER}"
elif modinfo rknpu >/dev/null 2>&1; then
    check_warn "rknpu available but not loaded"
else
    check_warn "rknpu module not found — needs to be built"
fi
echo ""

# 6. Check device nodes
echo "Device nodes:"
if [ -c /dev/dri/renderD129 ]; then
    check_pass "/dev/dri/renderD129 exists (NPU)"
elif ls /dev/dri/renderD* >/dev/null 2>&1; then
    check_warn "DRI render nodes exist but renderD129 not found"
else
    check_warn "No DRI render nodes found"
fi
echo ""

# 7. Check SCMI firmware
echo "SCMI firmware:"
if [ -d /sys/firmware/scmi_dev ]; then
    check_pass "SCMI firmware present"
else
    check_warn "SCMI firmware not found — NPU clock may not work"
fi
echo ""

# 8. Check power domains
echo "Power domains:"
if [ -f /sys/kernel/debug/pm_genpd/pm_genpd_summary ]; then
    if grep -qi npu /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null; then
        check_pass "NPU power domains found"
    else
        check_warn "NPU power domains not visible (may need overlay)"
    fi
else
    check_warn "pm_genpd_summary not accessible (need root or debugfs)"
fi
echo ""

# 9. Check CMA
echo "CMA memory:"
if [ -f /proc/meminfo ]; then
    CMA_TOTAL="$(grep CmaTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
    if [ -n "${CMA_TOTAL}" ] && [ "${CMA_TOTAL}" -gt 0 ]; then
        CMA_MB=$((CMA_TOTAL / 1024))
        check_pass "CMA available: ${CMA_MB}MB"
    else
        check_warn "No CMA memory — NPU DMA allocations may fail"
    fi
else
    check_warn "Cannot read /proc/meminfo"
fi
echo ""

# Summary
echo "========================="
echo "Results: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
if [ "${FAIL}" -gt 0 ]; then
    echo "Some checks failed. See above for details."
    exit 1
fi
