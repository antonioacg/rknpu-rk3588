# rknpu-rk3588

Out-of-tree RKNPU kernel module for RK3588/RK3588S on mainline Linux 6.19+. Enables the vendor RKNN SDK (librknnrt, rknn-toolkit2, rkllama) on modern kernels.

## Status

**Work in progress.** The RK3588 device tree overlay is a first draft based on vendor kernel sources. Hardware testing on RK3588 has not been performed yet. The underlying driver code (from w568w/rknpu-module) has been proven on RK3566 with kernel 6.19.3.

## Why This Exists

The RK3588 has a 6 TOPS NPU, but the vendor RKNPU driver only ships in the BSP kernel (6.1.x). Rockchip has stopped BSP kernel development — there will never be a 6.3+ BSP. Meanwhile, the mainline "Rocket" driver (merged in 6.18) is a completely different stack (Mesa/Teflon/TFLite) that cannot run RKNN models or rkllama.

The only path to running the vendor RKNN SDK on a modern kernel is an out-of-tree DKMS module. w568w/rknpu-module proved this works on RK3566. This project extends it to RK3588 by adding the device tree overlay, testing, and documentation.

## The Two NPU Stacks

Two mutually exclusive NPU stacks exist for RK3588:

| Stack | Driver | Userspace | Models | Kernel |
|-------|--------|-----------|--------|--------|
| **Vendor RKNN** | `rknpu` (out-of-tree) | librknnrt, rknn-toolkit2, rkllama | .rkllm, .rknn | 5.10, 6.1, **6.19+ (this project)** |
| **Mainline Rocket** | `accel/rocket` (in-tree) | Mesa Teflon, TFLite | .tflite only | 6.18+ |

This project enables the **vendor RKNN stack** on modern kernels. It does not replace or compete with the Rocket driver.

## Hardware

- **Target SoC**: RK3588 / RK3588S
- **Tested board**: Orange Pi 5 Pro (RK3588S)
- **NPU**: 3 cores, 6 TOPS total
- **Device node**: `/dev/dri/renderD129`
- **Kernel**: 6.19+ (Armbian edge)

## Quick Start

```bash
# Prerequisites
apt install linux-headers-$(uname -r) build-essential device-tree-compiler dkms

# Clone with submodules
git clone --recurse-submodules https://github.com/antonioacg/rknpu-rk3588.git
cd rknpu-rk3588

# Build module (uses w568w's Makefile)
cd ref/rknpu-module && make KDIR=/lib/modules/$(uname -r)/build
cd ../..

# Compile DT overlay
dtc -@ -I dts -O dtb -o rk3588-rknpu.dtbo dts/rk3588-rknpu-overlay.dts

# Load overlay (requires root)
sudo mkdir -p /sys/kernel/config/device-tree/overlays/rknpu
sudo cat rk3588-rknpu.dtbo > /sys/kernel/config/device-tree/overlays/rknpu/dtbo

# Load module
sudo modprobe rknpu  # or: sudo insmod ref/rknpu-module/rknpu.ko

# Verify
ls /dev/dri/renderD*
cat /sys/module/rknpu/version  # should show 0.9.8
```

## Repository Structure

```
rknpu-rk3588/
├── LICENSE                          # GPL-2.0-only
├── README.md                        # This file
├── CLAUDE.md                        # AI assistant instructions
├── CONTRIBUTING.md                  # Contribution guidelines
├── dts/
│   └── rk3588-rknpu-overlay.dts    # RK3588 NPU device tree overlay (UNTESTED)
├── docs/
│   ├── hardware-reference.md       # MMIO addresses, IRQs, clocks, power domains
│   ├── kernel-landscape.md         # Comparison of kernel options for RK3588 NPU
│   ├── porting-journal.md          # Engineering log
│   └── testing.md                  # Test procedures and results
├── scripts/
│   ├── build-module.sh             # Build helper
│   ├── install-dkms.sh             # DKMS install helper
│   ├── check-hardware.sh           # Verify RK3588 NPU hardware presence
│   └── test-rknn.sh               # Smoke test with librknnrt
├── ref/                            # Git submodules
│   ├── rknpu-module/               # w568w/rknpu-module
│   ├── rknn-llm/                   # airockchip/rknn-llm
│   ├── rknpu-device-plugin/        # elct9620/rknpu-device-plugin
│   ├── rknpu-driver-dkms/          # bmilde/rknpu-driver-dkms
│   └── radxa-overlays/             # radxa-pkg/radxa-overlays
└── .github/
    └── workflows/
        └── build.yml               # CI: cross-compile check
```

## Submodules

| Submodule | Source | Purpose | License |
|-----------|--------|---------|---------|
| `ref/rknpu-module` | [w568w/rknpu-module](https://github.com/w568w/rknpu-module) | Base DKMS module (RK3566-tested) | GPL-2.0 |
| `ref/rknn-llm` | [airockchip/rknn-llm](https://github.com/airockchip/rknn-llm) | RKNN runtime libs + vendor driver source | Apache-2.0 (runtime), GPL-2.0 (driver) |
| `ref/rknpu-device-plugin` | [elct9620/rknpu-device-plugin](https://github.com/elct9620/rknpu-device-plugin) | Kubernetes device plugin | MIT |
| `ref/rknpu-driver-dkms` | [bmilde/rknpu-driver-dkms](https://github.com/bmilde/rknpu-driver-dkms) | Failed DKMS attempt (reference only) | GPL-2.0 |
| `ref/radxa-overlays` | [radxa-pkg/radxa-overlays](https://github.com/radxa-pkg/radxa-overlays) | DT overlay patterns | GPL-2.0+ OR MIT |

## Version Matrix

| Component | Version | Source |
|-----------|---------|--------|
| RKNPU driver | 0.9.8 | rockchip-linux/kernel develop-6.6 (via w568w port) |
| librknnrt | 2.3.2 | airockchip/rknn-llm |
| rkllm-runtime | 1.2.3 | airockchip/rknn-llm |
| Target kernel | 6.19+ | Armbian edge / mainline |
| Tested kernel | 6.19.3-edge-rockchip64 | Armbian (w568w, RK3566 only) |

## Related Projects

- [w568w/rknpu-module](https://github.com/w568w/rknpu-module) — Out-of-tree RKNPU DKMS module, proven on RK3566 with kernel 6.19.3. The foundation this project builds on.
- [airockchip/rknn-llm](https://github.com/airockchip/rknn-llm) — Rockchip's official RKNN-LLM runtime and vendor driver source (GPL-2.0 driver, Apache-2.0 runtime).
- [rockchip-linux/kernel](https://github.com/rockchip-linux/kernel) — Rockchip BSP kernel (5.10, 6.1). Contains the authoritative `rk3588s.dtsi` with NPU node definitions.
- [elct9620/rknpu-device-plugin](https://github.com/elct9620/rknpu-device-plugin) — Kubernetes device plugin for RKNPU, enabling NPU scheduling in K8s clusters.
- [bmilde/rknpu-driver-dkms](https://github.com/bmilde/rknpu-driver-dkms) — Earlier DKMS attempt that encountered build issues. Useful as a reference for what didn't work.
- [radxa-pkg/radxa-overlays](https://github.com/radxa-pkg/radxa-overlays) — Radxa's DT overlay collection, includes RK3568 NPU overlay patterns.
- [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) — Ubuntu images for RK3588 boards. Noble uses kernel 6.1 with RKNPU 0.9.7; Oracular uses 6.11 without NPU support.

## License

This project is licensed under GPL-2.0-only. See [LICENSE](LICENSE) for the full text.

The RKNPU kernel driver is a derivative work of the Linux kernel and carries `SPDX-License-Identifier: GPL-2.0`. All original contributions in this repository use the same license.
