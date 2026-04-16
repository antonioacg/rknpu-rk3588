#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Print a one-shot NPU activity snapshot. Meant to be driven by watch(1):
#
#     sudo watch -n 0.5 /path/to/watch-npu.sh
#
# Reads a handful of files under /sys/kernel/debug/rknpu/ and the NPU
# rows from /proc/interrupts. Needs root to read debugfs.

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo (debugfs requires root)." >&2
    exit 1
fi

DBG=/sys/kernel/debug/rknpu
if [ ! -d "${DBG}" ]; then
    echo "No ${DBG} — is rknpu.ko loaded?" >&2
    exit 1
fi

# Debugfs snapshot (one line each).
printf 'version : %s\n' "$(cat "${DBG}/version"  2>/dev/null)"
printf 'freq    : %s Hz\n' "$(cat "${DBG}/freq"  2>/dev/null)"
printf 'volt    : %s uV\n' "$(cat "${DBG}/volt"  2>/dev/null)"
printf 'power   : %s\n' "$(cat "${DBG}/power" 2>/dev/null)"
printf 'load    : %s\n' "$(cat "${DBG}/load"  2>/dev/null)"
echo

# NPU IRQs — columns: virq, cpu counts, hwirq, trigger, device
echo 'interrupts (cpu0..cpu7):'
awk '/fdab0000.npu/ {
    printf "  virq %-4s ", $1
    for (i = 2; i <= 9; i++) printf "%8s", $i
    printf "  %s\n", $NF
}' /proc/interrupts
