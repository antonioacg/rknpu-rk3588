# CLAUDE.md

## Project Purpose

Out-of-tree RKNPU kernel module for RK3588/RK3588S on mainline Linux 6.19+. Enables the vendor RKNN SDK (librknnrt, rkllama, rknn-toolkit2) on modern kernels. The driver code exists in `ref/rknpu-module` (a git submodule of w568w/rknpu-module). Our job is the RK3588 device tree overlay, testing, and documentation.

## Repository Layout

```
rknpu-rk3588/
├── LICENSE                          # GPL-2.0-only
├── README.md                        # Human-readable project overview
├── CLAUDE.md                        # This file — AI assistant instructions
├── CONTRIBUTING.md                  # Contribution guidelines (GPL-2.0-only, DCO)
├── dts/
│   └── rk3588-rknpu-overlay.dts    # THE MAIN DELIVERABLE — RK3588 NPU DT overlay
├── docs/
│   ├── hardware-reference.md       # All MMIO addresses, IRQs, clocks, power domains
│   ├── kernel-landscape.md         # Comparison of all kernel options for RK3588 NPU
│   ├── porting-journal.md          # Engineering log
│   └── testing.md                  # Test procedures and results
├── scripts/
│   ├── build-module.sh             # Build helper (wraps w568w's Makefile)
│   ├── install-dkms.sh             # DKMS install helper
│   ├── check-hardware.sh           # Verify RK3588 NPU hardware is present
│   └── test-rknn.sh               # Smoke test with librknnrt
├── ref/                            # Git submodules — reference implementations
│   ├── rknpu-module/               # w568w/rknpu-module (base DKMS module)
│   ├── rknn-llm/                   # airockchip/rknn-llm (runtime libs + vendor driver)
│   ├── rknpu-device-plugin/        # elct9620/rknpu-device-plugin (K8s integration)
│   ├── rknpu-driver-dkms/          # bmilde/rknpu-driver-dkms (failed attempt — reference)
│   └── radxa-overlays/             # radxa-pkg/radxa-overlays (DT overlay patterns)
└── .github/
    └── workflows/
        └── build.yml               # CI: compile module + DT overlay (ARM64 cross-compile)
```

## The Main Deliverable: `dts/rk3588-rknpu-overlay.dts`

This is the DT overlay that adds the NPU device tree node to a mainline kernel DTB. It must define:

### NPU node (`npu@fdab0000`)
- compatible: `"rockchip,rk3588-rknpu"`
- reg: `0xfdab0000` (core0), `0xfdac0000` (core1), `0xfdad0000` (core2) — each 0x10000
- interrupts: GIC_SPI 110, 111, 112 (IRQ_TYPE_LEVEL_HIGH)
- clocks: SCMI_CLK_NPU(6), ACLK_NPU0(287), ACLK_NPU1(276), ACLK_NPU2(278), HCLK_NPU0(288), HCLK_NPU1(277), HCLK_NPU2(279), PCLK_NPU_ROOT(291)
- resets: SRST_A_RKNN0(272), SRST_A_RKNN1(250), SRST_A_RKNN2(254), SRST_H_RKNN0(274), SRST_H_RKNN1(252), SRST_H_RKNN2(256)
- power-domains: RK3588_PD_NPUTOP(9), RK3588_PD_NPU1(10), RK3588_PD_NPU2(11)
- iommus: reference to rknpu_mmu
- status: "okay"

### IOMMU node (`iommu@fdab9000`)
- compatible: `"rockchip,iommu-v2"`
- reg: 0xfdab9000, 0xfdaba000, 0xfdaca000, 0xfdada000 — each 0x100
- interrupts: GIC_SPI 110, 111, 112
- status: "disabled" (IOMMU v2 has known bugs — test before enabling)

### OPP table
300, 400, 500, 600, 700, 800, 900, 1000 MHz with vendor voltage ranges.

### Phandle resolution
The overlay references `&cru`, `&scmi_clk`, `&power`. Check if the target DTB has `__symbols__`:
```bash
dtc -I dtb -O dts /path/to/rk3588s-orangepi-5-pro.dtb | grep -c __symbols__
```
If `__symbols__` exists: use standard `&label` references.
If not: must use hardcoded phandle values or rebuild DTB with `-@` flag.

## Key Differences: RK3566 vs RK3588

| Aspect | RK3566 (w568w working) | RK3588 (our target) |
|--------|----------------------|---------------------|
| Cores | 1 | 3 (independent power domains) |
| MMIO regions | 1 (`0xfde40000`) | 3 (`0xfdab0000`, `0xfdac0000`, `0xfdad0000`) |
| IRQs | 1 (SPI 151) | 3 (SPI 110, 111, 112) |
| Clocks | 4 | 8 |
| Resets | 2 | 6 |
| Power domains | 1 (`RK3568_PD_NPU`) | 3 (`NPUTOP`, `NPU1`, `NPU2`) |
| IOMMU reg regions | 1 | 4 |
| DMA mask | 32-bit | 40-bit |
| Max frequency | 800 MHz | 1000 MHz |
| SCMI clocks | Optional | Required (`SCMI_CLK_NPU`) |
| NPU GRF | Not needed | `npu_grf@fd5a2000` (syscon) |

## Reference Sources

All hardware details come from three authoritative sources:

1. **Rockchip vendor DTS** (`rk3588s.dtsi`): Defines the complete NPU node for the vendor driver. Primary reference. URL: `https://github.com/rockchip-linux/kernel/blob/develop-5.10/arch/arm64/boot/dts/rockchip/rk3588s.dtsi`
2. **Mainline kernel Rocket DTS** (`rk3588s.dtsi`): Same hardware, different driver — confirms addresses independently. Search mainline `torvalds/linux` for `rk3588-rknn-core`.
3. **Running hardware**: The Orange Pi 5 Pro already has the NPU active under kernel 6.1. Check `/proc/device-tree/npu@fdab0000/`, `/proc/interrupts`, `/sys/module/rknpu/`.

For clock/reset/power-domain constants:
- `include/dt-bindings/clock/rockchip,rk3588-cru.h` (mainline kernel)
- `include/dt-bindings/power/rk3588-power.h` (mainline kernel)
- `include/dt-bindings/reset/rockchip,rk3588-cru.h` (mainline kernel)

## Known Issues and Risks

1. **IOMMU v2 bug**: Mainline `rockchip-iommu.c` doesn't constrain page table allocations to DMA32 zone. If page tables land above 4GB, bus errors occur. Workaround: disable IOMMU in overlay. Test with IOMMU disabled first.

2. **Phandle resolution**: If the board DTB lacks `__symbols__`, the overlay can't resolve `&cru` etc. May need hardcoded phandle values or DTB rebuild.

3. **SCMI clocks**: RK3588 NPU clock (`SCMI_CLK_NPU`) is managed by the SCP via SCMI. The SCMI agent must be running. Verify with: `ls /sys/firmware/scmi_dev/*/`.

4. **Power domain sequencing**: RK3588 has per-core power domains (`NPUTOP`, `NPU1`, `NPU2`). The driver probes them in order and falls back to fewer cores if unavailable.

5. **40-bit DMA**: RK3588 uses 40-bit DMA addressing. If IOMMU is disabled and CMA is above 4GB, allocations may fail. Boot with `cma=128M` or `cma=64M@0-4G` as fallback.

## Submodule Grep Patterns

```bash
# Find all RK3588 NPU references across all submodules
rg "rk3588.*rknpu\|rk3588.*npu\|fdab0000" ref/

# Compare vendor driver source with w568w's port
diff ref/rknn-llm/rknpu-driver/driver/rknpu_drv.c ref/rknpu-module/src/rknpu_drv.c

# Find DT overlay patterns from Radxa
rg "rknpu\|npu" ref/radxa-overlays/
```

## Development Workflow

1. Write/edit the DT overlay (`dts/rk3588-rknpu-overlay.dts`) using vendor DTS as reference
2. Cross-compile test: `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -C ref/rknpu-module`
3. Compile overlay: `dtc -@ -I dts -O dtb -o rk3588-rknpu.dtbo dts/rk3588-rknpu-overlay.dts`
4. Copy to test board (Orange Pi 5 Pro running Armbian edge 6.19+)
5. Apply overlay and load module
6. Verify: `cat /sys/module/rknpu/version` shows `0.9.8`, `/dev/dri/renderD129` exists
7. Test with librknnrt: run RKNN benchmark or rkllama inference

## Test Hardware

```
Board:    Orange Pi 5 Pro
SoC:      RK3588S (3-core NPU, 6 TOPS)
Current:  Ubuntu 24.04, kernel 6.1.0-1026-rockchip, rknpu 0.9.7
Target:   Armbian edge, kernel 6.19+
```

## Commit Style

Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`. Reference upstream sources in commit messages.

## What NOT to Do

- Do NOT modify w568w's code in the submodule — fork upstream if needed
- Do NOT add the full Linux kernel as a submodule (multi-GB)
- Do NOT use GPL-2.0-or-later — must be GPL-2.0-only
- Do NOT vendor Rockchip binary blobs — reference submodule paths
- Do NOT assume IOMMU works on RK3588 — start disabled, test incrementally
