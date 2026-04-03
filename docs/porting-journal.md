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

## 2026-04-03 — Project bootstrap

- Created repository structure based on research into w568w/rknpu-module, vendor DTS, and mainline kernel sources.
- Wrote RK3588 DT overlay (`dts/rk3588-rknpu-overlay.dts`) from vendor `rk3588s.dtsi` register values.
- Overlay compiles cleanly with dtc. All numeric IDs verified against mainline v6.12 headers.

### Static verification (completed)

Cross-referenced overlay against driver source (`ref/rknpu-module/src/`):

- `compatible`, `interrupt-names`, `power-domain-names`, reg count, reset count: all match
- `clock-names` first entry: **bug found and fixed** — vendor DTS uses `"clk_npu"` but w568w's
  `rknpu_devfreq.c:176` calls `devm_pm_opp_set_clkname(dev, "scmi_clk")`. Changed to `"scmi_clk"`.
- IOMMU `compatible`: **bug found and fixed** — vendor uses `"rockchip,iommu-v2"`, mainline
  `rockchip-iommu.c` probes `"rockchip,rk3568-iommu"`. Changed.
- Added missing IOMMU `clock-names` and `interrupt-names` to match vendor DTS.

### Numeric ID verification

All values verified against mainline `v6.12` kernel headers:

| Category | IDs checked | Result |
|----------|------------|--------|
| Clock IDs (CRU) | 7 | All match mainline `rockchip,rk3588-cru.h` |
| Reset IDs | 6 | All match mainline `rockchip,rk3588-cru.h` |
| Power domain IDs | 3 | All match `rk3588-power.h` (same in vendor and mainline) |
| GIC SPI IRQs | 3 | 110, 111, 112 — match vendor DTS |
| IOMMU addresses | 4 | All match vendor DTS |

**Important**: BSP headers use different numeric values (e.g., `ACLK_NPU0` = 301 in vendor vs 287
in mainline). Our overlay uses `#include` with mainline header paths, so symbolic names resolve to
the correct mainline values. This is correct — the overlay is for mainline 6.19+.

---

## 2026-04-03 — Live board extraction (BSP kernel 6.1)

Extracted comprehensive reference data from the running Orange Pi 5 Pro (kernel 6.1.0-1026-rockchip,
Ubuntu 24.04, rknpu 0.9.7 built-in) via SSH. This is our ground truth for what a working RK3588 NPU
setup looks like.

### Board state

```
SoC:       RK3588S (rockchip,rk3588s-orangepi-5-pro)
Kernel:    6.1.0-1026-rockchip
RKNPU:     0.9.7, built-in (CONFIG_ROCKCHIP_RKNPU=y), NOT a loadable module
IOMMU:     enabled, NPU in IOMMU group 0
Device:    /dev/dri/renderD129 (card1)
NPU temp:  48.1°C (idle)
Uptime:    ~11.5 days
K3s:       running (single node, flannel CNI)
Boot:      eMMC 233GB, U-Boot + extlinux.conf
IP:        192.168.0.100
```

### DTB symbols (overlay support)

**1045 symbols present** in the DTB — overlay phandle resolution is fully supported.

Key symbols found:

| Symbol | Points to |
|--------|-----------|
| `cru` | `/clock-controller@fd7c0000` |
| `scmi_clk` | `/firmware/scmi/protocol@14` |
| `power` | `/power-management@fd8d8000/power-controller` |
| `rknpu` | `/npu@fdab0000` |
| `rknpu_mmu` | `/iommu@fdab9000` |
| `npu_opp_table` | `/npu-opp-table` |

**Note**: The symbol is `rknpu`, NOT `npu`. Our overlay creates new nodes (not patching existing
ones), so this doesn't matter for the mainline case where these nodes don't exist. But if we ever
need to reference the NPU node by label in an overlay-on-overlay scenario, we'd need `&rknpu`.

### Driver probe log (from journalctl)

```
vdd_npu_s0: 550 <--> 950 mV at 800 mV, enabled
RKNPU fdab0000.npu: Adding to iommu group 0
RKNPU fdab0000.npu: RKNPU: rknpu iommu is enabled, using iommu mode
RKNPU fdab0000.npu: can't request region for resource [mem 0xfdab0000-0xfdabffff]
RKNPU fdab0000.npu: can't request region for resource [mem 0xfdac0000-0xfdacffff]
RKNPU fdab0000.npu: can't request region for resource [mem 0xfdad0000-0xfdadffff]
[drm] Initialized rknpu 0.9.7 20240424 for fdab0000.npu on minor 1
RKNPU fdab0000.npu: RKNPU: bin=0
RKNPU fdab0000.npu: leakage=10
RKNPU fdab0000.npu: pvtm=877
RKNPU fdab0000.npu: pvtm-volt-sel=3
RKNPU fdab0000.npu: l=15000 h=85000 hyst=5000 l_limit=0 h_limit=800000000
```

**"can't request region"** for all three MMIO regions is logged but **non-fatal** — the driver
initializes successfully anyway. This appears to be a resource conflict with something else claiming
those regions on the BSP kernel (possibly the Rocket/DRM subsystem or a memory reservation). On
mainline 6.19+ where the NPU node doesn't exist in the base DTB, this conflict should not occur
since our overlay would be the only thing defining those regions.

### Interrupt mapping

```
/proc/interrupts:
 40: GICv3 142 Level  fdab9000.iommu, fdab0000.npu
 41: GICv3 143 Level  fdab9000.iommu, fdab0000.npu
 42: GICv3 144 Level  fdab9000.iommu, fdab0000.npu
```

GICv3 hardware IRQs 142/143/144 = GIC SPI 110/111/112 + 32 (SPI offset). **Confirms our overlay's
IRQ numbers are correct.** Zero interrupts fired — NPU was idle during extraction.

IRQs are shared between the IOMMU and the NPU driver (both registered on the same lines).

### Power domains

```
npu       off-0
  nputop  off-0
    npu1  off-0
    npu2  off-0
```

Four-level hierarchy: `npu` → `nputop` → `npu1`, `npu2`. All off (NPU idle/suspended).
The driver attaches virtual devices: `genpd:0:fdab0000.npu` (nputop),
`genpd:1:fdab0000.npu` (npu1), `genpd:2:fdab0000.npu` (npu2).

Power domain supply lookups (`nputop-supply`, `npu1-supply`, `npu2-supply`) all fail with
"property not found" — these are non-fatal; the domains still work via firmware/PMIC defaults.

### Devfreq

```
Device:               fdab0000.npu
Current frequency:    1,000,000,000 Hz (1 GHz)
Available:            300 400 500 600 700 800 900 1000 MHz
Governor:             rknpu_ondemand (vendor-specific)
Range:                300 MHz - 1 GHz
```

On mainline with w568w's port, the governor will be `simple_ondemand` (standard Linux) since
`rknpu_ondemand` is a vendor-only governor not present in w568w's code.

### SCMI firmware

`/sys/firmware/scmi_dev/` does not exist (BSP lacks `CONFIG_ARM_SCMI_POWER_CONTROL`), but SCMI
clocks are fully functional. Verified via clock debugfs:

```
scmi_clk_npu                  200 MHz  (SCMI-managed, initial rate)
  └─ aclk_npu0/1/2            250 MHz  (CRU-derived AXI clocks)
  └─ hclk_npu0/1/2            198 MHz  (CRU-derived AHB clocks)
  └─ pclk_npu_root            100 MHz  (CRU-derived APB clock)
```

All 8 clocks referenced in our overlay are present and active. The SCMI tracing interface exists
at `/sys/kernel/tracing/events/scmi/` (fc_call, xfer_begin, xfer_end). On mainline 6.19+, verify
clocks with: `sudo cat /sys/kernel/debug/clk/clk_summary | grep -i npu`

### CMA memory

```
CmaTotal:       8,192 kB (8 MB)
CmaAllocated:   2,112 kB
CmaFree:        0 kB
DMA heaps:      cma, system
```

**Only 8 MB CMA** (default `CONFIG_CMA_SIZE_MBYTES=16`, but actual allocation is 8 MB). This is
very small for NPU inference. Large models may need `cma=128M` or `cma=256M` boot parameter.
With IOMMU disabled on mainline, all NPU DMA allocations go through CMA — this could be a
bottleneck.

### Voltage regulator

`vdd_npu_s0`: 550–950 mV, currently 800 mV, supplied by `vcc5v0_sys`.

Our OPP table specifies voltages up to 1000 mV (for 1 GHz). The regulator max is 950 mV. The
OPP framework should clamp to the regulator's range, but this could mean 1 GHz is slightly
undervolted. The BSP OPP table has `opp-supported-hw` bitmasks to select variant-specific
voltage tables — our simplified overlay omits this. Monitor for stability issues at 1 GHz.

### Kernel config (relevant flags)

```
CONFIG_ROCKCHIP_RKNPU=y          # Built-in (not module!)
CONFIG_ROCKCHIP_RKNPU_DRM_GEM=y  # Uses DRM GEM for buffer management
CONFIG_ROCKCHIP_IOMMU=y          # Built-in
CONFIG_ARM_SCMI_PROTOCOL=y       # SCMI enabled
CONFIG_PM_DEVFREQ=y              # Devfreq enabled
CONFIG_DMA_CMA=y                 # CMA enabled
CONFIG_CMA_SIZE_MBYTES=16        # Default CMA size
```

On mainline 6.19+, we need: `CONFIG_ROCKCHIP_IOMMU` (for when we enable IOMMU),
`CONFIG_ARM_SCMI_PROTOCOL`, `CONFIG_PM_DEVFREQ`, `CONFIG_DMA_CMA`. The RKNPU driver will be our
out-of-tree DKMS module, not built-in.

### Boot configuration

U-Boot + extlinux.conf. DTBs at `/lib/firmware/6.1.0-1026-rockchip/device-tree/rockchip/`.
Board DTB: `rk3588s-orangepi-5-pro.dtb`.

**Runtime DT overlays (configfs) NOT available** — `/sys/kernel/config/device-tree/overlays/`
doesn't exist despite configfs being mounted. This BSP kernel doesn't support runtime overlays.

Board-specific overlays exist at `/lib/firmware/.../device-tree/rockchip/overlay/` (cam1, cam2,
lcd, etc.) — these are applied at boot time by U-Boot, not at runtime.

On Armbian edge, check if `CONFIG_OF_OVERLAY` and `CONFIG_OF_CONFIGFS` are enabled. If runtime
overlays aren't available, we'll need to either:
1. Apply the overlay at boot time via U-Boot `fdtoverlays` in extlinux.conf
2. Merge the overlay into the DTB with `fdtoverlay` tool before booting
3. Use Armbian's `user_overlays` mechanism in `/boot/armbianEnv.txt`

### Properties in BSP NPU node that our overlay lacks

| Property | BSP value | In our overlay? | Needed? |
|----------|-----------|----------------|---------|
| `rknpu-supply` | regulator phandle | No | Maybe — needed for voltage scaling |
| `mem-supply` | regulator phandle | No | Maybe — same regulator as rknpu-supply |
| `assigned-clocks` | scmi_clk, SCMI_CLK_NPU | No | Nice-to-have — sets initial frequency |
| `assigned-clock-rates` | 200 MHz | No | Nice-to-have |
| `opp-supported-hw` | bitmask per OPP | No | Maybe — selects variant-specific voltages |

The `rknpu-supply` and `mem-supply` are board-specific (reference the voltage regulator). Since
different boards have different PMIC configurations, we can't hardcode these in a generic overlay.
The driver should still work without explicit regulator references — it just won't scale voltage,
only frequency. If stability issues appear at high frequencies, we'll need a board-specific fragment.

### Answers to open questions

1. **Does the DTB include `__symbols__`?** YES — 1045 symbols. Phandle resolution will work for
   overlays. Need to verify this holds true on Armbian edge as well.

2. **Does SCMI properly expose `SCMI_CLK_NPU`?** The SCMI clock works (devfreq uses it), but
   `/sys/firmware/scmi_dev/` doesn't exist on this BSP. The DT symbol `scmi_clk` points to
   `/firmware/scmi/protocol@14`. Need to verify on mainline 6.19+.

3. **Does IOMMU v2 work on RK3588?** YES — on the BSP kernel with `rockchip,iommu-v2`, the IOMMU
   is enabled and working (NPU in IOMMU group 0). The question remains whether mainline
   `rockchip-iommu.c` with `rockchip,rk3568-iommu` compat string works correctly on RK3588.

---

## Next steps

1. **Get Armbian edge image** for Orange Pi 5 Pro (kernel 6.19+)
2. **Flash to SD card** — boot from SD, keep eMMC intact
3. **Verify on Armbian edge**:
   - Does the DTB have `__symbols__`?
   - Does configfs runtime overlays work? If not, use boot-time overlay
   - Is `SCMI_CLK_NPU` available?
   - Are power domains accessible?
4. **Apply overlay and load module** — follow the 9-step test plan from the PR
5. **CMA sizing** — may need `cma=128M` boot parameter for NPU inference
6. **Voltage scaling** — monitor stability at 900 MHz / 1 GHz without explicit regulator reference
