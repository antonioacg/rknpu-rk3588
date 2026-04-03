# Prompt: Bootstrap rknpu-rk3588 Repository

## Mission

Create a new GitHub repository `rknpu-rk3588` that ports the Rockchip vendor RKNPU kernel driver to mainline Linux kernels (6.19+) for the RK3588/RK3588S SoC. This builds on w568w/rknpu-module (which proved the approach on RK3566) by adding RK3588 device tree overlays, testing, and documentation.

## Context & Motivation

The RK3588 has a 6 TOPS NPU but the vendor RKNPU driver only ships in the BSP kernel (6.1.x). Rockchip has stopped BSP kernel development — there will never be a 6.3+ BSP. Meanwhile, the mainline "Rocket" driver (merged in 6.18) is a completely different stack (Mesa/Teflon/TFLite) that cannot run RKNN models or rkllama. The only path to running the vendor RKNN SDK on a modern kernel is an out-of-tree DKMS module.

w568w/rknpu-module proved this works on RK3566 (OrangePi 3B) with kernel 6.19.3. The driver code already contains full RK3588 support (3-core NPU, power domains, 40-bit DMA) but it has never been tested on RK3588. The DT overlay is RK3566-only. Our contribution is: write the RK3588 DT overlay, test on real hardware (Orange Pi 5 Pro / RK3588S), and document the process.

## What to Create

### 1. Repository Structure

```
rknpu-rk3588/
├── LICENSE                          # GPL-2.0-only (SPDX: GPL-2.0-only)
├── README.md                        # Human-readable project overview
├── CLAUDE.md                        # AI assistant instructions
├── CONTRIBUTING.md                  # Contribution guidelines (GPL-2.0-only, DCO)
├── dts/
│   └── rk3588-rknpu-overlay.dts    # THE MAIN DELIVERABLE — RK3588 NPU DT overlay
├── docs/
│   ├── hardware-reference.md       # All MMIO addresses, IRQs, clocks, power domains
│   ├── kernel-landscape.md         # Comparison of all kernel options for RK3588 NPU
│   ├── porting-journal.md          # Engineering log (inspired by w568w's PLAN.md)
│   └── testing.md                  # Test procedures and results
├── scripts/
│   ├── build-module.sh             # Build helper (wraps w568w's Makefile)
│   ├── install-dkms.sh             # DKMS install helper
│   ├── check-hardware.sh           # Verify RK3588 NPU hardware is present
│   └── test-rknn.sh                # Smoke test with librknnrt
├── ref/                            # Git submodules — reference implementations
│   ├── rknpu-module/               # w568w/rknpu-module (the base we build on)
│   ├── rknn-llm/                   # airockchip/rknn-llm (runtime libs + vendor driver source)
│   ├── rknpu-device-plugin/        # elct9620/rknpu-device-plugin (K8s integration)
│   ├── rknpu-driver-dkms/          # bmilde/rknpu-driver-dkms (failed attempt — for reference)
│   └── radxa-overlays/             # radxa-pkg/radxa-overlays (DT overlay patterns)
└── .github/
    └── workflows/
        └── build.yml               # CI: compile module + DT overlay (ARM64 cross-compile)
```

### 2. LICENSE File

Use the SPDX-standard GPL-2.0-only text. The full license text is available at:
https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt

SPDX identifier for all source files: `SPDX-License-Identifier: GPL-2.0-only`

Legal rationale:
- Linux kernel is GPL-2.0-only (not "or later") — Linus explicitly chose v2 only
- Kernel modules are derivative works of the kernel
- Rockchip's RKNPU source carries `SPDX-License-Identifier: GPL-2.0`
- w568w/rknpu-module inherits GPL-2.0 from Rockchip
- Our DT overlay + any driver patches must be GPL-2.0-only
- Scripts and documentation can be GPL-2.0-only for simplicity (single license)

### 3. Git Submodules

Add these as submodules under `ref/`:

```bash
git submodule add https://github.com/w568w/rknpu-module.git ref/rknpu-module
git submodule add https://github.com/airockchip/rknn-llm.git ref/rknn-llm
git submodule add https://github.com/elct9620/rknpu-device-plugin.git ref/rknpu-device-plugin
git submodule add https://github.com/bmilde/rknpu-driver-dkms.git ref/rknpu-driver-dkms
git submodule add https://github.com/radxa-pkg/radxa-overlays.git ref/radxa-overlays
```

NOTE: Do NOT add the full Linux kernel or rockchip-linux/kernel as submodules — they are multi-GB repos. Reference them in docs only.

### 4. README.md Content

The README should cover:

#### Project Overview
- What: Out-of-tree RKNPU kernel module for RK3588 on mainline Linux 6.19+
- Why: Vendor kernel (6.1) is EOL, mainline Rocket driver doesn't support RKNN SDK
- How: DKMS module + DT overlay, building on w568w/rknpu-module
- Status: Work in progress — RK3588 DT overlay untested

#### The Two NPU Stacks (critical context)
Explain that two mutually exclusive NPU stacks exist:

| Stack | Driver | Userspace | Models | Kernel |
|-------|--------|-----------|--------|--------|
| **Vendor RKNN** | `rknpu` (out-of-tree) | librknnrt, rknn-toolkit2, rkllama | .rkllm, .rknn | 5.10, 6.1, **6.19+ (this project)** |
| **Mainline Rocket** | `accel/rocket` (in-tree) | Mesa Teflon, TFLite | .tflite only | 6.18+ |

This project enables the **vendor RKNN stack** on modern kernels. It does NOT replace or compete with the Rocket driver.

#### Hardware Reference Table
- Target SoC: RK3588 / RK3588S
- Tested board: Orange Pi 5 Pro (RK3588S)
- NPU: 3 cores, 6 TOPS total
- Device: `/dev/dri/renderD129`
- Kernel: 6.19+ (tested on Armbian edge)

#### Quick Start
```bash
# Prerequisites
apt install linux-headers-$(uname -r) build-essential device-tree-compiler dkms

# Clone with submodules
git clone --recurse-submodules https://github.com/antonioacg/rknpu-rk3588.git
cd rknpu-rk3588

# Build module (uses w568w's Makefile)
cd ref/rknpu-module && make KDIR=/lib/modules/$(uname -r)/build

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

#### Submodule Reference Table

| Submodule | Source | Purpose | License |
|-----------|--------|---------|---------|
| `ref/rknpu-module` | w568w/rknpu-module | Base DKMS module (RK3566-tested) | GPL-2.0 |
| `ref/rknn-llm` | airockchip/rknn-llm | RKNN runtime libs + vendor driver source | Apache-2.0 (runtime), GPL-2.0 (driver) |
| `ref/rknpu-device-plugin` | elct9620/rknpu-device-plugin | Kubernetes device plugin | MIT |
| `ref/rknpu-driver-dkms` | bmilde/rknpu-driver-dkms | Failed DKMS attempt (reference) | GPL-2.0 |
| `ref/radxa-overlays` | radxa-pkg/radxa-overlays | DT overlay patterns (RK3568) | GPL-2.0+ OR MIT |

#### Version Matrix

| Component | Version | Source |
|-----------|---------|--------|
| RKNPU driver | 0.9.8 | rockchip-linux/kernel develop-6.6 (via w568w port) |
| librknnrt | 2.3.2 | airockchip/rknn-llm |
| rkllm-runtime | 1.2.3 | airockchip/rknn-llm |
| Target kernel | 6.19+ | Armbian edge / mainline |
| Tested kernel | 6.19.3-edge-rockchip64 | Armbian (w568w, RK3566 only) |

#### Related Projects & Prior Art
Link to all the projects we researched, with one-line descriptions of what they do and their status.

### 5. CLAUDE.md Content

This is the AI assistant instruction file. It should contain:

#### Project Purpose
One paragraph: Out-of-tree RKNPU kernel module for RK3588/RK3588S on mainline Linux 6.19+. Enables vendor RKNN SDK (librknnrt, rkllama, rknn-toolkit2) on modern kernels. The driver code exists in ref/rknpu-module — our job is the RK3588 DT overlay, testing, and documentation.

#### Repository Layout
The directory structure from above, annotated with what each file does.

#### The Main Deliverable: `dts/rk3588-rknpu-overlay.dts`

This is the DT overlay that adds the NPU device tree node to a mainline kernel DTB. It must define:

**NPU node** (`npu@fdab0000`):
```
compatible:     "rockchip,rk3588-rknpu"
reg:            0xfdab0000 (core0), 0xfdac0000 (core1), 0xfdad0000 (core2) — each 0x10000
interrupts:     GIC_SPI 110, 111, 112 (IRQ_TYPE_LEVEL_HIGH)
interrupt-names: "npu0_irq", "npu1_irq", "npu2_irq"
clocks:         SCMI_CLK_NPU(6), ACLK_NPU0(287), ACLK_NPU1(276), ACLK_NPU2(278),
                HCLK_NPU0(288), HCLK_NPU1(277), HCLK_NPU2(279), PCLK_NPU_ROOT(291)
clock-names:    "clk_npu", "aclk0", "aclk1", "aclk2", "hclk0", "hclk1", "hclk2", "pclk"
resets:         SRST_A_RKNN0(272), SRST_A_RKNN1(250), SRST_A_RKNN2(254),
                SRST_H_RKNN0(274), SRST_H_RKNN1(252), SRST_H_RKNN2(256)
reset-names:    "srst_a0", "srst_a1", "srst_a2", "srst_h0", "srst_h1", "srst_h2"
power-domains:  RK3588_PD_NPUTOP(9), RK3588_PD_NPU1(10), RK3588_PD_NPU2(11)
power-domain-names: "npu0", "npu1", "npu2"
iommus:         <&rknpu_mmu>
status:         "okay"
```

**IOMMU node** (`iommu@fdab9000`):
```
compatible:     "rockchip,iommu-v2"
reg:            0xfdab9000, 0xfdaba000, 0xfdaca000, 0xfdada000 — each 0x100
interrupts:     GIC_SPI 110, 111, 112
clocks:         ACLK_NPU0, ACLK_NPU1, ACLK_NPU2, HCLK_NPU0, HCLK_NPU1, HCLK_NPU2
#iommu-cells:   <0>
status:         "disabled"  ← start disabled (w568w found IOMMU v2 bugs on RK3566; test before enabling)
```

**OPP table** (operating performance points for devfreq):
```
300 MHz, 400 MHz, 500 MHz, 600 MHz, 700 MHz, 800 MHz, 900 MHz, 1000 MHz
```
Voltage ranges from vendor DTS. Include `opp-supported-hw` bitmask if needed.

**Phandle resolution strategy**: The overlay references `&cru`, `&scmi_clk`, `&power`. Check if the target DTB has `__symbols__`:
```bash
dtc -I dtb -O dts /path/to/rk3588s-orangepi-5-pro.dtb | grep -c __symbols__
```
If __symbols__ exists: use standard `&label` references in the overlay.
If not: must use hardcoded phandle values (fragile) or rebuild DTB with `-@` flag.

#### Key Differences: RK3566 vs RK3588

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

#### Reference Sources (for looking things up)

All hardware details come from three authoritative sources:
1. **Rockchip vendor DTS** (`rk3588s.dtsi`): Defines the complete NPU node for the vendor driver. This is our primary reference. NOT in a submodule (kernel repo is too large). Use: `https://github.com/rockchip-linux/kernel/blob/develop-5.10/arch/arm64/boot/dts/rockchip/rk3588s.dtsi`
2. **Mainline kernel Rocket DTS** (`rk3588s.dtsi`): Same hardware, different driver — confirms addresses independently. Search mainline `torvalds/linux` for `rk3588-rknn-core`.
3. **Running hardware**: The Orange Pi 5 Pro already has the NPU active under kernel 6.1. Check `/proc/device-tree/npu@fdab0000/`, `/proc/interrupts`, `/sys/module/rknpu/`.

For clock/reset/power-domain constants, check:
- `include/dt-bindings/clock/rockchip,rk3588-cru.h` (mainline kernel)
- `include/dt-bindings/power/rk3588-power.h` (mainline kernel)
- `include/dt-bindings/reset/rockchip,rk3588-cru.h` (mainline kernel)

These headers exist in mainline and the numeric values are stable across kernel versions.

#### Known Issues & Risks

1. **IOMMU v2 bug** (w568w found on RK3566): Mainline `rockchip-iommu.c` doesn't constrain page table allocations to DMA32 zone. If page tables land above 4GB, bus errors occur. Workaround: disable IOMMU (`status = "disabled"` in overlay). RK3588 uses a different IOMMU version — the bug may or may not apply. Test with IOMMU disabled first, then try enabling.

2. **Phandle resolution**: If the board DTB lacks `__symbols__`, the overlay can't resolve `&cru` etc. May need to hardcode phandle values or rebuild DTB. w568w documented this in PLAN.md.

3. **SCMI clocks**: RK3588 NPU clock (`SCMI_CLK_NPU`) is managed by the SCP (System Control Processor) via SCMI. The SCMI agent must be running and the SCMI clock provider must be in the DTB. Mainline kernels should have this. Verify with: `ls /sys/firmware/scmi_dev/*/`.

4. **Power domain sequencing**: RK3588 has per-core power domains (`NPUTOP`, `NPU1`, `NPU2`). The driver probes them in order and falls back to fewer cores if domains are unavailable. If power domain binding fails, the driver may fall back to single-core mode or fail entirely. The `genpd_dev_npu0/1/2` virtual device attachment in the driver source is the code path to watch.

5. **40-bit DMA**: RK3588 uses 40-bit DMA addressing (vs 32-bit on RK3566). The driver sets `dma_set_mask(dev, DMA_BIT_MASK(40))` for RK3588. If the IOMMU is disabled and CMA is above 4GB, allocations may fail. Boot with `cma=128M` or `cma=64M@0-4G` as fallback.

#### Submodule Grep Patterns

The submodules are searchable with ripgrep. Useful searches:

```bash
# Find all RK3588 NPU references across all submodules
rg "rk3588.*rknpu\|rk3588.*npu\|fdab0000" ref/

# Compare vendor driver source with w568w's port
diff ref/rknn-llm/rknpu-driver/driver/rknpu_drv.c ref/rknpu-module/src/rknpu_drv.c

# Find device plugin Kubernetes resource registration
rg "rock-chips" ref/rknpu-device-plugin/

# See how bmilde's attempt failed vs w568w's success
diff ref/rknpu-driver-dkms/ ref/rknpu-module/

# Find DT overlay patterns from Radxa
rg "rknpu\|npu" ref/radxa-overlays/
```

#### Development Workflow

1. **Write the DT overlay** (`dts/rk3588-rknpu-overlay.dts`) using vendor DTS as reference
2. **Cross-compile test** (if on non-ARM64): `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -C ref/rknpu-module`
3. **Compile overlay**: `dtc -@ -I dts -O dtb -o rk3588-rknpu.dtbo dts/rk3588-rknpu-overlay.dts`
4. **Copy to test board** (Orange Pi 5 Pro running Armbian edge 6.19+)
5. **Apply overlay** and load module
6. **Verify**: `cat /sys/module/rknpu/version` shows `0.9.8`, `/dev/dri/renderD129` exists
7. **Test with librknnrt**: Run RKNN benchmark or rkllama inference

#### Test Hardware

```
Board:    Orange Pi 5 Pro
SoC:     RK3588S (3-core NPU, 6 TOPS)
Current: Ubuntu 24.04, kernel 6.1.0-1026-rockchip, rknpu 0.9.7
Target:  Armbian edge, kernel 6.19+
SSH:     192.168.0.100 (via ~/git/ops/remote-exec.sh)
```

Current device state (verified 2026-04-03):
```
/dev/dri/renderD128, renderD129  ← renderD129 is NPU
/dev/dma_heap/cma, system
/dev/rga                         ← present
/dev/mpp_service                 ← present
/proc/device-tree/compatible = "rockchip,rk3588s-orangepi-5-pro rockchip,rk3588"
rknpu driver version: 0.9.7
k3s v1.34.6 running (single node)
```

#### Commit Style
Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`. Reference upstream sources in commit messages.

#### What NOT to Do
- Do NOT modify w568w's code in the submodule — fork upstream if needed
- Do NOT add the full Linux kernel as a submodule (multi-GB)
- Do NOT use GPL-2.0-or-later — must be GPL-2.0-only
- Do NOT vendor Rockchip binary blobs — reference submodule paths
- Do NOT assume IOMMU works on RK3588 — start disabled, test incrementally

### 6. docs/hardware-reference.md

Include ALL the hardware details gathered in this conversation:

**Register Map (from vendor rk3588s.dtsi)**:
```
NPU Core 0:  0xfdab0000 - 0xfdabffff (64KB)
NPU Core 1:  0xfdac0000 - 0xfdacffff (64KB)
NPU Core 2:  0xfdad0000 - 0xfdadffff (64KB)
NPU IOMMU:   0xfdab9000 (core0-a), 0xfdaba000 (core0-b),
              0xfdaca000 (core1), 0xfdada000 (core2)
NPU GRF:     0xfd5a2000 - 0xfd5a20ff (syscon)
NPU PVTM:    0xfdaf0000 - 0xfdaf00ff
```

**Interrupts**: GIC SPI 110 (core0), 111 (core1), 112 (core2) — all LEVEL_HIGH

**Clocks**:
| Name | Provider | Constant | Numeric ID |
|------|----------|----------|------------|
| clk_npu | scmi_clk | SCMI_CLK_NPU | 6 |
| aclk0 | cru | ACLK_NPU0 | 287 |
| aclk1 | cru | ACLK_NPU1 | 276 |
| aclk2 | cru | ACLK_NPU2 | 278 |
| hclk0 | cru | HCLK_NPU0 | 288 |
| hclk1 | cru | HCLK_NPU1 | 277 |
| hclk2 | cru | HCLK_NPU2 | 279 |
| pclk | cru | PCLK_NPU_ROOT | 291 |

**Resets**:
| Name | Constant | Numeric ID |
|------|----------|------------|
| srst_a0 | SRST_A_RKNN0 | 272 |
| srst_a1 | SRST_A_RKNN1 | 250 |
| srst_a2 | SRST_A_RKNN2 | 254 |
| srst_h0 | SRST_H_RKNN0 | 274 |
| srst_h1 | SRST_H_RKNN1 | 252 |
| srst_h2 | SRST_H_RKNN2 | 256 |

**Power Domains**:
| Name | Constant | Numeric ID |
|------|----------|------------|
| npu0 | RK3588_PD_NPUTOP | 9 |
| npu1 | RK3588_PD_NPU1 | 10 |
| npu2 | RK3588_PD_NPU2 | 11 |

**QoS Registers**:
| Node | Address |
|------|---------|
| qos_npu0_mwr | 0xfdf72000 |
| qos_npu0_mro | 0xfdf72200 |
| qos_mcu_npu | 0xfdf72400 |
| qos_npu1 | 0xfdf70000 |
| qos_npu2 | 0xfdf71000 |

**OPP Table** (from vendor kernel, RK3588 standard):
| Frequency | Voltage range |
|-----------|--------------|
| 300 MHz | 675-850 mV |
| 400 MHz | 675-850 mV |
| 500 MHz | 675-850 mV |
| 600 MHz | 675-850 mV |
| 700 MHz | 700-850 mV |
| 800 MHz | 750-850 mV |
| 900 MHz | 800-850 mV |
| 1000 MHz | 850-1000 mV |

### 7. docs/kernel-landscape.md

Document all kernel options for RK3588 NPU:

| Option | Kernel | NPU Driver | RKNN Compatible | Status |
|--------|--------|-----------|-----------------|--------|
| Rockchip BSP | 6.1.99 | RKNPU 0.9.8 in-tree | Yes | Stable, EOL |
| Joshua Riek PPA (Noble) | 6.1.0-1026 | RKNPU 0.9.7 in-tree | Yes | Stale (~67 weeks) |
| Armbian vendor | 6.1.x | RKNPU in-tree | Yes | Stable |
| Joshua Riek (Oracular) | 6.11 | None | No | No NPU |
| Armbian current | 6.12 | None | No | No NPU |
| Armbian edge | 6.18+ | Rocket (mainline) | No (Mesa/Teflon) | Different stack |
| **This project** | **6.19+** | **RKNPU 0.9.8 DKMS** | **Yes** | **In progress** |

Include links to all source repos, PPAs, forum threads.

### 8. Create the GitHub Repository

Use `gh repo create antonioacg/rknpu-rk3588 --public --license gpl-2.0 --description "Out-of-tree RKNPU kernel module for RK3588/RK3588S on mainline Linux 6.19+ — enables vendor RKNN SDK on modern kernels"`.

Then add submodules, create all files, and push.

## Summary of Deliverables

1. `LICENSE` — GPL-2.0-only full text
2. `README.md` — comprehensive human-readable docs (project overview, two NPU stacks, quick start, version matrix, related projects)
3. `CLAUDE.md` — AI assistant instructions (repo layout, hardware reference, DT overlay spec, known issues, dev workflow)
4. `CONTRIBUTING.md` — GPL-2.0-only, DCO sign-off, how to test
5. `dts/rk3588-rknpu-overlay.dts` — skeleton with all addresses filled in (marked UNTESTED)
6. `docs/hardware-reference.md` — complete register map, clocks, resets, power domains
7. `docs/kernel-landscape.md` — all kernel options compared
8. `docs/porting-journal.md` — empty template for engineering log
9. `docs/testing.md` — test plan template
10. `scripts/check-hardware.sh` — verify NPU hardware presence
11. 5 git submodules under `ref/`
12. `.github/workflows/build.yml` — basic CI for cross-compilation check

## Important Notes

- The DT overlay should be a COMPLETE first draft with all addresses filled in from the vendor DTS, clearly marked as UNTESTED. Include comments explaining each field.
- The README should be honest about status: "RK3588 support is untested. The DT overlay is a first draft based on vendor kernel sources. Hardware testing is the next step."
- Reference w568w's PLAN.md (Chinese) as prior art and inspiration. Our porting-journal.md serves the same purpose in English.
- The check-hardware.sh script should verify: kernel version, rknpu module presence, /dev/dri/renderD129, /proc/device-tree/compatible, SCMI firmware, power domain availability.
