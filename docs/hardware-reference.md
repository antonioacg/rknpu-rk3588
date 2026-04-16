# RK3588 NPU Hardware Reference

All values sourced from the Rockchip vendor kernel DTS (`rk3588s.dtsi` from rockchip-linux/kernel develop-5.10 and develop-6.6) and cross-referenced with the mainline kernel DTS. Values that ended up in the shipping overlay were additionally verified against the live DT on an Orange Pi 5 Pro running Armbian 6.18.22.

## Register Map

| Region | Address Range | Size | Description |
|--------|--------------|------|-------------|
| NPU Core 0 | `0xfdab0000` - `0xfdabffff` | 64KB | Core 0 registers |
| NPU Core 1 | `0xfdac0000` - `0xfdacffff` | 64KB | Core 1 registers |
| NPU Core 2 | `0xfdad0000` - `0xfdadffff` | 64KB | Core 2 registers |
| NPU IOMMU (core0-a) | `0xfdab9000` - `0xfdab90ff` | 256B | IOMMU region A, core 0 (see note) |
| NPU IOMMU (core0-b) | `0xfdaba000` - `0xfdaba0ff` | 256B | IOMMU region B, core 0 (see note) |
| NPU IOMMU (core1) | `0xfdaca000` - `0xfdaca0ff` | 256B | IOMMU, core 1 (see note) |
| NPU IOMMU (core2) | `0xfdada000` - `0xfdada0ff` | 256B | IOMMU, core 2 (see note) |
| NPU GRF | `0xfd5a2000` - `0xfd5a20ff` | 256B | General Register File (syscon) |
| NPU PVTM | `0xfdaf0000` - `0xfdaf00ff` | 256B | Process-Voltage-Temperature Monitor |

**IOMMU note.** The current shipping overlay runs with `iommus` stripped from the combined node (non-IOMMU mode). The mainline Rocket DT exposes the IOMMUs as sibling nodes (`/iommu@fdab9000/fdaca000/fdada000`) which `scripts/apply-overlay.sh` deletes post-merge. Re-enabling the IOMMU is an open work item — addresses are recorded here for that future effort.

## Interrupts

| IRQ | GIC SPI Number | Type | Description |
|-----|----------------|------|-------------|
| npu0_irq | 110 | LEVEL_HIGH | NPU Core 0 interrupt |
| npu1_irq | 111 | LEVEL_HIGH | NPU Core 1 interrupt |
| npu2_irq | 112 | LEVEL_HIGH | NPU Core 2 interrupt |

**Cell count note.** Mainline RK3588 DT binds the GIC as `arm,gic-v3` with `#interrupt-cells = 4` (the 4th cell is the PPI affinity mask; 0 for SPIs). The vendor BSP DT binds it with 3 cells. Copying a 3-cell `interrupts` property from the BSP DTS into a mainline overlay will silently misalign the parser — see [porting-journal.md](porting-journal.md) § "IRQ blocker resolved" for the symptom and diagnostic. Always use 4-cell tuples on mainline.

## Clocks

| Clock Name | Provider | Constant | Numeric ID | Description |
|------------|----------|----------|------------|-------------|
| clk_npu | scmi_clk | SCMI_CLK_NPU | 6 | Main NPU clock (SCMI-managed) |
| aclk0 | cru | ACLK_NPU0 | 287 | AXI clock, core 0 |
| aclk1 | cru | ACLK_NPU1 | 276 | AXI clock, core 1 |
| aclk2 | cru | ACLK_NPU2 | 278 | AXI clock, core 2 |
| hclk0 | cru | HCLK_NPU0 | 288 | AHB clock, core 0 |
| hclk1 | cru | HCLK_NPU1 | 277 | AHB clock, core 1 |
| hclk2 | cru | HCLK_NPU2 | 279 | AHB clock, core 2 |
| pclk | cru | PCLK_NPU_ROOT | 291 | APB clock, NPU root |

## Resets

| Reset Name | Constant | Numeric ID | Description |
|------------|----------|------------|-------------|
| srst_a0 | SRST_A_RKNN0 | 272 | AXI reset, core 0 |
| srst_a1 | SRST_A_RKNN1 | 250 | AXI reset, core 1 |
| srst_a2 | SRST_A_RKNN2 | 254 | AXI reset, core 2 |
| srst_h0 | SRST_H_RKNN0 | 274 | AHB reset, core 0 |
| srst_h1 | SRST_H_RKNN1 | 252 | AHB reset, core 1 |
| srst_h2 | SRST_H_RKNN2 | 256 | AHB reset, core 2 |

## Power Domains

| Domain Name | Constant | Numeric ID | Description |
|-------------|----------|------------|-------------|
| npu0 | RK3588_PD_NPUTOP | 9 | Top-level NPU power domain (required for all cores) |
| npu1 | RK3588_PD_NPU1 | 10 | NPU core 1 power domain |
| npu2 | RK3588_PD_NPU2 | 11 | NPU core 2 power domain |

## QoS Registers

| Node | Address | Description |
|------|---------|-------------|
| qos_npu0_mwr | `0xfdf72000` | NPU core 0, memory write QoS |
| qos_npu0_mro | `0xfdf72200` | NPU core 0, memory read QoS |
| qos_mcu_npu | `0xfdf72400` | NPU MCU QoS |
| qos_npu1 | `0xfdf70000` | NPU core 1 QoS |
| qos_npu2 | `0xfdf71000` | NPU core 2 QoS |

## OPP Table (Operating Performance Points)

From vendor kernel `rk3588s.dtsi`. Used for devfreq dynamic frequency scaling.

| Frequency | Min Voltage | Target Voltage | Max Voltage |
|-----------|-------------|----------------|-------------|
| 300 MHz | 675 mV | 675 mV | 850 mV |
| 400 MHz | 675 mV | 675 mV | 850 mV |
| 500 MHz | 675 mV | 675 mV | 850 mV |
| 600 MHz | 675 mV | 675 mV | 850 mV |
| 700 MHz | 700 mV | 700 mV | 850 mV |
| 800 MHz | 750 mV | 750 mV | 850 mV |
| 900 MHz | 800 mV | 800 mV | 850 mV |
| 1000 MHz | 850 mV | 850 mV | 1000 mV |

## Comparison: RK3566 vs RK3588

| Aspect | RK3566 | RK3588 |
|--------|--------|--------|
| NPU Cores | 1 | 3 |
| TOPS | 0.8 | 6.0 |
| MMIO Base | `0xfde40000` | `0xfdab0000` |
| IRQs | SPI 151 | SPI 110, 111, 112 |
| Clocks | 4 | 8 |
| Resets | 2 | 6 |
| Power Domains | 1 | 3 |
| DMA Mask | 32-bit | 40-bit |
| Max Frequency | 800 MHz | 1000 MHz |
| SCMI Clocks | Optional | Required |
