# Porting Journal

Engineering log for porting the RKNPU vendor driver to mainline Linux on RK3588.

Inspired by [w568w's PLAN.md](https://github.com/w568w/rknpu-module/blob/main/PLAN.md) (in Chinese), which documented the RK3566 porting process.

## Format

Each entry should include:
- **Date**
- **What was attempted**
- **What happened** (including exact error messages, dmesg output)
- **What was learned**
- **Next steps**

---

## 2026-04-03 -- Project bootstrap

- Created repository structure based on research into w568w/rknpu-module, vendor DTS, and mainline kernel sources.
- Wrote RK3588 DT overlay (`dts/rk3588-rknpu-overlay.dts`) from vendor `rk3588s.dtsi` register values.
- Overlay is UNTESTED. Next step: compile overlay and test on Orange Pi 5 Pro with Armbian edge.

### Open questions
1. Does the Orange Pi 5 Pro Armbian edge DTB include `__symbols__`? (Needed for overlay phandle resolution)
2. Does the mainline kernel's SCMI agent properly expose `SCMI_CLK_NPU` on RK3588S?
3. Does IOMMU v2 have the same DMA32 zone bug as IOMMU v1 on RK3566?
