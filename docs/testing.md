# Testing Procedures

Runbook for validating this repo on a fresh board. For the engineering
history of how we got the driver working (and every blocker along the
way), see [porting-journal.md](porting-journal.md).

## Reference environment

| Item | Value |
|------|-------|
| Board | Orange Pi 5 Pro |
| SoC | RK3588S (3-core NPU, 6 TOPS) |
| RAM | 16 GB |
| OS | Armbian Trixie Minimal |
| Kernel | `6.18.22-current-rockchip64` |
| Driver | `rknpu 0.9.8` (DKMS, auto-loads on boot) |
| Vendor SDK | librknnrt 2.3.2 (airockchip/rknn-toolkit2) |

Any board with an `arm,gic-v3` interrupt controller using
`#interrupt-cells = 4`, SCMI clocks, and a compatible 3-core NPU at
`0xfdab0000/0xfdac0000/0xfdad0000` should also work — but nothing else
has been validated yet.

## Pre-flight checks

On the target board, before applying the overlay or loading the module:

```bash
sudo ./scripts/check-hardware.sh
```

Expected: `0 failed`. `CMA` and `SCMI` may warn on some distros —
they don't block the module loading but may affect stability under
load.

Manual spot-checks if the script isn't available:

```bash
# SoC: must be rk3588 or rk3588s
tr '\0' '\n' < /proc/device-tree/compatible

# Kernel >= 6.18
uname -r

# GIC is arm,gic-v3 with #interrupt-cells = 4 (our overlay depends on this)
tr '\0' '\n' < /sys/firmware/devicetree/base/interrupt-controller@fe600000/compatible
od -An -tx4 /sys/firmware/devicetree/base/interrupt-controller@fe600000/\#interrupt-cells
```

## Test 1 — Overlay compile + merge

```bash
sudo ./scripts/apply-overlay.sh
```

Expected output ends with `Done. Reboot to activate the overlay.` and
the cpp/dtc/fdtoverlay/fdtput steps all succeed. The pristine DTB is
saved to `<target>.dtb.bak` on the first run (idempotent).

Troubleshooting:

- **`dtc: syntax error`** — check the kernel headers package matches
  the running kernel. The overlay `#include`s `dt-bindings/*` from
  `/lib/modules/$(uname -r)/build/include/`.
- **`fdtput: FDT_ERR_NOTFOUND`** when removing siblings — harmless if
  the nodes are already absent (e.g. a rerun after a successful merge).
- **`__symbols__` missing** from the base DTB — the overlay can't
  resolve `&cru`, `&scmi_clk`, `&power`. Rebuild the board DTB with
  `dtc -@` or request one from the distro.

## Test 2 — DKMS install

```bash
sudo ./scripts/install-dkms.sh
echo rknpu | sudo tee /etc/modules-load.d/rknpu.conf
sudo reboot
```

After reboot:

```bash
# Module loaded automatically
lsmod | grep rknpu

# Version is 0.9.8
cat /sys/module/rknpu/version

# DRM device is present
ls /dev/dri/renderD129

# No probe errors
sudo dmesg | grep -i rknpu | grep -iE 'error|fail|warn'   # should be empty
```

Expected `dmesg` probe trace (clean boot):

```
rknpu: loading out-of-tree module taints kernel.
RKNPU fdab0000.npu: RKNPU: rknpu iommu device-tree entry not found!, using non-iommu mode
[drm] Initialized rknpu 0.9.8 for fdab0000.npu on minor 2
RKNPU fdab0000.npu: RKNPU: devfreq enabled, initial freq: 200000000 Hz, volt: 800000 uV
```

The "iommu device-tree entry not found" line is intentional — see the
porting journal for why we strip the `iommus` property.

Troubleshooting:

- **`modinfo: not found`** — Armbian minimal doesn't ship kmod utilities
  on `$PATH` for unprivileged users. Use `/sbin/modinfo` or `sudo modinfo`.
- **Probe fails with `request_irq(N) EINVAL`** — GIC interrupt-cells
  mismatch. Check `#interrupt-cells` on the live interrupt-controller
  (see pre-flight). Our overlay assumes 4.
- **Module loads but `/dev/dri/renderD129` missing** — the overlay
  didn't merge, or the bootloader loaded an older DTB. Check
  `readlink -f /boot/dtb` matches what `apply-overlay.sh` targeted.

## Test 3 — Passive smoke test

Confirms userspace can open the DRM device and the debugfs + IRQ
bindings are live. Does not run any inference.

```bash
sudo ./scripts/test-rknn.sh
```

Expected output ends with:

```
Smoke test passed: driver responds, debugfs live, 3/3 IRQs bound.
```

## Test 4 — End-to-end inference (the real smoke test)

Downloads `librknnrt.so` + `mobilenet_v1.rknn` from
airockchip/rknn-toolkit2, compiles `tests/rknn_smoke.c` against them,
runs 200 iterations, prints timing and IRQ counter deltas.

```bash
sudo ./scripts/test-inference.sh
```

Expected (within ±20% on the same board):

```
SDK api=2.3.2 (429f97ae6b@2025-04-09T09:09:27) driver=0.9.8
inputs=1 outputs=1
  in[0] name=input dims=[1,224,224,3] size=150528 fmt=NHWC

=== RESULTS ===
iterations  : 200
per-inference: ~8 ms
throughput  : ~123 inf/s

Non-zero interrupt deltas on virq 146/147/148 mean the NPU actually executed.
```

Multi-core version (exercises all three NPU cores, confirms all three
IRQs fire):

```bash
sudo CORE_MASK=0_1_2 ITERS=300 ./scripts/test-inference.sh
```

Expected: ~3.7 ms/inference, ~271 inf/s, `load` in
`/sys/kernel/debug/rknpu/load` showing Core0/1/2 all in the 70–80%
range during the run.

## Live monitoring

For eyeballing what happens while a workload runs:

```bash
sudo watch -n 0.5 ./scripts/watch-npu.sh
```

Updates at 2 Hz with `freq`, `volt`, `power`, per-core `load`, and per-IRQ
counters.

## Known issues (do NOT step on these)

- **Writing to devfreq sysfs hangs the board.** Setting `governor` to
  `userspace` and writing `min_freq`/`max_freq`/`set_freq` triggers an
  SCMI/PD deadlock that requires a physical power-cycle. Passive reads
  are fine. See porting journal "Known issue: devfreq userspace
  governor hangs the board".
- **NPU frequency doesn't scale up under load.** The vendor's custom
  devfreq governor relied on `rockchip_system_monitor` which isn't in
  mainline; our `simple_ondemand` fallback doesn't get the busy signal
  it expects. Performance measured above is the floor, not the ceiling.
- **IOMMU is disabled.** Re-enabling it requires wiring a working IOMMU
  node and is tracked as an open item. Current non-IOMMU mode works for
  all tested workloads.

## Results log

| Date | Kernel | Board | Test | Result | Notes |
|------|--------|-------|------|--------|-------|
| 2026-04-16 | 6.18.22-current-rockchip64 | Orange Pi 5 Pro (RK3588S) | Test 1 (overlay merge) | PASS | cpp/dtc/fdtoverlay/fdtput all clean |
| 2026-04-16 | 6.18.22-current-rockchip64 | Orange Pi 5 Pro (RK3588S) | Test 2 (DKMS install) | PASS | auto-load 4.0 s after kernel start |
| 2026-04-16 | 6.18.22-current-rockchip64 | Orange Pi 5 Pro (RK3588S) | Test 3 (smoke) | PASS | DRM_IOCTL_VERSION reports driver=rknpu 0.9.8, 3/3 IRQs bound |
| 2026-04-16 | 6.18.22-current-rockchip64 | Orange Pi 5 Pro (RK3588S) | Test 4 single-core | PASS | MobileNet v1 @ 123.3 inf/s (8.11 ms) |
| 2026-04-16 | 6.18.22-current-rockchip64 | Orange Pi 5 Pro (RK3588S) | Test 4 all-3-cores | PASS | MobileNet v1 @ 270.9 inf/s (3.69 ms); Core0 78%, Core1/2 73% |
