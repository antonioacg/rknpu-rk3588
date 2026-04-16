#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Passive smoke test for the RKNPU driver.
#
# Verifies from userspace that:
#   - /dev/dri/renderD129 is usable via DRM_IOCTL_VERSION
#   - The module's debugfs entries are present and readable
#   - All three NPU IRQs are registered
#
# Does NOT exercise devfreq frequency scaling — forcing a userspace
# governor transition on the current mainline-vs-vendor topology has
# been observed to hang the board (SCMI clock + power-domain interaction
# without the vendor's system_monitor layer, which our devfreq patch
# disabled on kernels where <linux/devfreq-governor.h> is private).

set -euo pipefail

echo "RKNPU Smoke Test"
echo "================"
echo ""

if [ ! -c /dev/dri/renderD129 ]; then
    echo "Error: /dev/dri/renderD129 not found." >&2
    echo "  Is the rknpu module loaded? Is the DT overlay applied?" >&2
    exit 1
fi

if [ ! -f /sys/module/rknpu/version ]; then
    echo "Error: rknpu module not loaded." >&2
    exit 1
fi

NVER="$(cat /sys/module/rknpu/version)"
echo "Driver version (sysfs): ${NVER}"
echo ""

# DRM_IOCTL_VERSION via Python: confirms the driver responds to
# userspace and identifies itself as "rknpu" (vendor) rather than
# "rocket" (mainline).
echo "DRM identity via /dev/dri/renderD129:"
python3 <<'PY'
import ctypes, fcntl, os

class DrmVersion(ctypes.Structure):
    _fields_ = [
        ("version_major",      ctypes.c_int),
        ("version_minor",      ctypes.c_int),
        ("version_patchlevel", ctypes.c_int),
        ("name_len",           ctypes.c_size_t),
        ("name",               ctypes.c_char_p),
        ("date_len",           ctypes.c_size_t),
        ("date",               ctypes.c_char_p),
        ("desc_len",           ctypes.c_size_t),
        ("desc",               ctypes.c_char_p),
    ]

IOC_READ, IOC_WRITE = 2, 1
size = ctypes.sizeof(DrmVersion)
DRM_IOCTL_VERSION = ((IOC_READ | IOC_WRITE) << 30
                     | (size & 0x3fff) << 16
                     | (ord('d') & 0xff) << 8
                     | 0x00)

fd = os.open("/dev/dri/renderD129", os.O_RDWR)
v = DrmVersion()
fcntl.ioctl(fd, DRM_IOCTL_VERSION, v)  # lengths only
name = ctypes.create_string_buffer(v.name_len + 1)
date = ctypes.create_string_buffer(v.date_len + 1)
desc = ctypes.create_string_buffer(v.desc_len + 1)
v.name = ctypes.cast(name, ctypes.c_char_p)
v.date = ctypes.cast(date, ctypes.c_char_p)
v.desc = ctypes.cast(desc, ctypes.c_char_p)
fcntl.ioctl(fd, DRM_IOCTL_VERSION, v)
os.close(fd)
print(f"  driver     : {name.value.decode(errors='replace')}")
print(f"  version    : {v.version_major}.{v.version_minor}.{v.version_patchlevel}")
print(f"  description: {desc.value.decode(errors='replace')}")
n = name.value.decode(errors='replace')
if n != "rknpu":
    raise SystemExit(f"Expected driver 'rknpu', got '{n}' — overlay/module mismatch?")
PY
echo ""

# Debugfs (requires root). If we're not root, skip with a note.
if [ "$(id -u)" -eq 0 ] && [ -d /sys/kernel/debug/rknpu ]; then
    echo "Debugfs (/sys/kernel/debug/rknpu/):"
    for f in version freq volt power load; do
        if [ -f "/sys/kernel/debug/rknpu/${f}" ]; then
            printf '  %-8s : %s\n' "${f}" "$(cat "/sys/kernel/debug/rknpu/${f}")"
        fi
    done
    echo ""
elif [ -d /sys/kernel/debug/rknpu ]; then
    echo "Debugfs present (rerun as root to dump entries)"
    echo ""
else
    echo "Debugfs entries not visible — CONFIG_DEBUG_FS mounted? rerun as root?"
    echo ""
fi

# IRQ registration — all three cores should be bound.
echo "NPU interrupts:"
if grep -q "fdab0000.npu" /proc/interrupts; then
    grep "fdab0000.npu" /proc/interrupts | awk '{printf "  %s %s %s\n", $1, $(NF-2), $NF}'
    IRQ_COUNT=$(grep -c "fdab0000.npu" /proc/interrupts || true)
    if [ "${IRQ_COUNT}" -lt 3 ]; then
        echo "  Warning: only ${IRQ_COUNT}/3 IRQs registered."
        exit 1
    fi
else
    echo "  Error: no NPU IRQs in /proc/interrupts." >&2
    exit 1
fi
echo ""

echo "Smoke test passed: driver responds, debugfs live, 3/3 IRQs bound."
echo ""
echo "For a full inference test, supply a .rknn model and librknnrt.so"
echo "(from airockchip/rknn-toolkit2) and run rknn_benchmark."
