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

## 2026-04-16 — First boot on Armbian (kernel 6.18.22)

Flashed Armbian Trixie Minimal CLI (Debian 13, kernel 6.18.21 → upgraded to 6.18.22 for
matching headers) to a microSD. Booted on the Orange Pi 5 Pro alongside the eMMC Ubuntu
install (SD takes priority). This is the first session against a mainline kernel.

### Major discovery: mainline 6.18+ has Rocket NPU nodes

The mainline RK3588 DTS (`arch/arm64/boot/dts/rockchip/rk3588s.dtsi`) defines the NPU
hardware for the Rocket driver (merged in Linux 6.18). The architecture is fundamentally
different from the vendor RKNPU driver:

| Aspect | Vendor RKNPU (what we're porting) | Mainline Rocket (what's in the DTB) |
|--------|-----------------------------------|-------------------------------------|
| Node structure | 1 combined node, 3 reg regions | 3 separate nodes (one per core) |
| Symbols | N/A (we create it) | `rknn_core_0`, `rknn_core_1`, `rknn_core_2` |
| Addresses | `/npu@fdab0000` (combined) | `/npu@fdab0000`, `/npu@fdac0000`, `/npu@fdad0000` |
| compatible | `rockchip,rk3588-rknpu` | `rockchip,rk3588-rknn-core` |
| IRQs per node | 3 | 1 |
| Clocks per node | 8 (SCMI + 7 CRU) | 4 (aclk, hclk, npu, pclk) |
| reg-names | (by index) | `pc`, `cna`, `core` (3 sub-regions within each core) |
| IOMMU nodes | 1 combined | 3 separate (`rknn_mmu_0/1/2`) |
| IOMMU compat | vendor: `rockchip,iommu-v2` | mainline: `rockchip,rk3588-iommu`, `rockchip,rk3568-iommu` |
| Driver module | `rknpu` (out-of-tree, this project) | `rocket` (in-tree, `/dev/accel/accel0`) |

This invalidates our original overlay design. The original overlay added a new
`npu@fdab0000` node at the root, but mainline already has one there — the overlay
system rejects duplicate unit addresses. The overlay needed a complete rework.

### Overlay rework: patch existing nodes instead of add new ones

New approach:

1. Disable `rknn_core_1` and `rknn_core_2` (their hardware is absorbed into the combined node)
2. Disable `rknn_mmu_0/1/2` (we'll run without IOMMU until tested)
3. Patch `rknn_core_0` in place to become the vendor RKNPU node:
   - Override `compatible` to `rockchip,rk3588-rknpu`
   - Override `reg` to include all 3 cores' MMIO regions
   - Override `interrupts` to include all 3 cores' SPIs
   - Override `clocks`, `clock-names` to vendor's 8-clock layout
   - Add `resets`, `reset-names`, `power-domain-names`, `interrupt-names`
   - Add `operating-points-v2` pointing to new OPP table
4. Add `npu-opp-table` at root (new node, no address conflict)

The node **name** stays `/npu@fdab0000` (can't rename via overlay), but the driver only
looks at `compatible`, so this is fine.

### Runtime configfs overlay is fundamentally broken for this case

First attempt: apply the overlay via `/sys/kernel/config/device-tree/overlays/rknpu/dtbo`.

**Result**: kernel oops with `Unable to handle kernel paging request at virtual address
dead000000000122` — a poison pattern indicating use-after-free in the OF overlay subsystem.
The crash happened during `of_reconfig_notify` when modifying the `power-domains` property.

Root cause: the Rocket driver (`accel/rocket`) was already bound to `rknn_core_0/1/2`
when the overlay tried to modify their properties. Modifying live driver-bound property
lists triggers use-after-free on the resolved phandles.

Even without `/delete-property/` directives, just overriding `compatible` and other
properties causes the same crash. Runtime configfs overlays are unusable for replacing
driver bindings on a live system.

### Offline DTB merge (fdtoverlay) is the correct path

Armbian boots via U-Boot, which reads the DTB from
`/boot/dtb/rockchip/rk3588s-orangepi-5-pro.dtb` (a symlink to
`/boot/dtb-<kver>/rockchip/...`). Merging our overlay into that DTB with `fdtoverlay`
and rebooting avoids all the runtime overlay problems:

```bash
# On the target:
sudo cp /boot/dtb/rockchip/rk3588s-orangepi-5-pro.dtb{,.bak}
sudo fdtoverlay -i .../rk3588s-orangepi-5-pro.dtb.bak \
                -o /tmp/merged.dtb /tmp/rk3588-rknpu.dtbo
sudo cp /tmp/merged.dtb /boot/dtb/rockchip/rk3588s-orangepi-5-pro.dtb
sudo reboot
```

**This worked.** After reboot, the NPU node shows `compatible = "rockchip,rk3588-rknpu"`,
cores 1/2 are `disabled`, the OPP table is present, and the Rocket module doesn't load
(its compat string no longer matches any live node).

### Module build on 6.18.22: devfreq-governor.h is now private

With the DTB live, building `rknpu.ko` against Armbian's kernel headers failed:

```
src/rknpu_devfreq.c:14:10: fatal error: linux/devfreq-governor.h: No such file or directory
```

Starting somewhere between 6.12 and 6.18, `<linux/devfreq-governor.h>` was moved from
`include/linux/` to a private location (`drivers/devfreq/governor.h`) and is no longer
exported to out-of-tree modules. The driver uses it for a custom `rknpu_ondemand`
governor.

Local workaround (patch applied only on the target, not upstream yet):

```c
#if __has_include(<linux/devfreq-governor.h>)
#include <linux/devfreq-governor.h>
#define RKNPU_HAVE_CUSTOM_GOV 1
#endif
```

And wrap the custom governor struct, `devfreq_add_governor` call, and
`devfreq_remove_governor` calls in `#ifdef RKNPU_HAVE_CUSTOM_GOV`. When the header
isn't available, register the devfreq device with `"simple_ondemand"` instead of
`"rknpu_ondemand"`. The custom governor's only job is to report the driver-chosen
ramp-up/ramp-down frequency, so falling back to `simple_ondemand` works — we just
lose job-submission-triggered ramp control.

With that patch, `rknpu.ko` builds clean against 6.18.22 headers. Needs to be upstreamed
to w568w/rknpu-module or carried as a patch in this repo.

### Module loads, but probe blocks on IRQ registration

`sudo insmod rknpu.ko` returns 0. dmesg shows:

```
RKNPU fdab0000.npu: RKNPU: rknpu iommu is disabled, using non-iommu mode
RKNPU fdab0000.npu: error -EINVAL: request_irq(147) rknpu_core1_irq_handler [rknpu]
                   0x0 fdab0000.npu
RKNPU fdab0000.npu: RKNPU: request npu1_irq failed: -22
RKNPU fdab0000.npu: probe with driver RKNPU failed with error -22
```

Core 0 IRQ (SPI 110) registers successfully. Core 1 IRQ (SPI 111) fails with `EINVAL`.
The driver passes `IRQF_SHARED` and `rknpu_dev` as the `dev_id` — but it reuses the
**same `dev_id`** for all three cores. For `IRQF_SHARED`, `request_irq` requires a
unique `dev_id` per handler on the same IRQ line, which may be rejected as EINVAL.

But more likely suspect: the disabled `rknn_core_1` node at `/npu@fdac0000` still has
an `interrupts` property referencing SPI 111. The OF core may still reserve that virq
mapping for the disabled node, leaving it unavailable for our combined node to claim.

**Still blocked here.** Investigation options for next session:
1. Use `/delete-node/ &rknn_core_1;` (+ core_2, mmu_0/1/2) in the overlay to remove
   them entirely instead of disabling. Apply via offline fdtoverlay merge (the only
   safe path).
2. Study `rknpu_drv.c` around `rknpu_probe+0x4b8/0x4e4` to confirm whether the probe
   logic is salvageable or needs adjustment for the combined-node-with-disabled-siblings
   topology.
3. Compare `dev_id` passed to `devm_request_irq` — may need a unique cookie per IRQ
   (e.g., `&rknpu_dev->subcore_datas[i]` instead of `rknpu_dev`).

### Sanity-check results (what IS working)

- DTB symbols on Armbian: 851 (`cru`, `scmi_clk`, `power`, `rknn_core_0/1/2`, `rknn_mmu_0/1/2`)
- configfs overlays directory exists (`CONFIG_OF_OVERLAY + CONFIG_OF_CONFIGFS` enabled)
- `fdtoverlay` tool available via `device-tree-compiler` package
- `/sys/firmware/scmi_dev/` still doesn't exist (expected — missing CONFIG), but SCMI
  clocks work via the kernel clock framework
- Kernel headers package name: `linux-headers-current-rockchip64` (pulls in matching
  image; doesn't offer a version-pinned flavour)
- After reboot with merged DTB: Rocket module (`rocket`, `drm_shmem_helper`, `gpu_sched`)
  doesn't load, confirming our compat override took effect

---

## 2026-04-16 — IRQ blocker resolved; module probes cleanly on 6.18.22

### Root cause: GIC-v3 `#interrupt-cells = 4` on mainline

None of the three theories from the prior session was correct. The real cause
was a device-tree cell-count mismatch that the overlay had silently inherited
from the vendor BSP.

- Mainline RK3588 DT: `interrupt-controller@fe600000` with
  `compatible = "arm,gic-v3"` and **`#interrupt-cells = 4`** (the 4th cell is
  the PPI affinity mask; 0 for SPIs).
- Vendor BSP DT: same GIC but `#interrupt-cells = 3`.

Our overlay copied the BSP form verbatim:

```
interrupts = <GIC_SPI 110 IRQ_TYPE_LEVEL_HIGH>,
             <GIC_SPI 111 IRQ_TYPE_LEVEL_HIGH>,
             <GIC_SPI 112 IRQ_TYPE_LEVEL_HIGH>;
```

That encoded 9 cells. Reading them as 4-cell tuples (what the live DT
expects), the kernel resolved:

| Tuple | cells          | type      | num | flags     | affinity | result        |
|-------|----------------|-----------|-----|-----------|----------|---------------|
| 1     | `<0 110 4 0>`  | SPI       | 110 | LVL_HIGH  | 0        | virq 146 ✓    |
| 2     | `<111 4 0 111>`| junk(111) | 4   | 0         | 111      | virq 147 w/ `hwirq=0, type=edge` |
| 3     | (misaligned)   | —         | —   | —         | —        | never mapped  |

The first IRQ worked by pure luck — cell #3 happened to be 0, which is a
valid PPI-affinity-mask value. Tuples 2 and 3 were offset by one cell each
and became garbage. `request_threaded_irq()` then WARNed and returned
`-EINVAL` for the bogus virq 147.

### Diagnostic that exposed it

Before the fix, on the live board:

```bash
$ cat /sys/kernel/irq/147/hwirq   # expected 143 (32+SPI 111)
0
$ cat /sys/kernel/irq/147/type    # expected "level"
edge
```

These two numbers — `hwirq=0` and `type=edge` where DT said level-high —
were the smoking gun. Future bring-ups on unfamiliar SoCs should always
sanity-check `/sys/kernel/irq/<virq>/{hwirq,type}` against the DT spec
before blaming the driver.

### Fix

`dts/rk3588-rknpu-overlay.dts` now uses 4-cell interrupt tuples:

```
interrupts = <GIC_SPI 110 IRQ_TYPE_LEVEL_HIGH 0>,
             <GIC_SPI 111 IRQ_TYPE_LEVEL_HIGH 0>,
             <GIC_SPI 112 IRQ_TYPE_LEVEL_HIGH 0>;
```

### Residual loose ends that were also tied up this session

1. **Dangling `iommus` phandle.** The pristine `rknn_core_0` referenced
   `rknn_mmu_0`. Our overlay replaced other properties but not `iommus`,
   which left the patched node pointing at a phandle we later deleted via
   `fdtput -r`. The kernel logs `iommu device-tree entry not found` but
   could also corrupt state. The merge pipeline now strips the property
   with `fdtput -d /npu@fdab0000 iommus` after the merge.

2. **OPP regulator name mismatch.** The driver calls
   `devm_regulator_get_optional(dev, "rknpu")` and `"mem"`, looking for
   `rknpu-supply` / `mem-supply`. The original node only had `npu-supply`
   and `sram-supply`. Added both `rknpu-supply = <&vdd_npu_s0>` and
   `mem-supply = <&vdd_npu_s0>` (same regulator the original node used).
   devfreq now prints `RKNPU: devfreq enabled, initial freq: 200000000 Hz,
   volt: 800000 uV` instead of failing the OPP setup.

3. **`/delete-node/` inside an overlay fragment is a no-op.** DTC compiles
   it into an empty `__overlay__` block; `fdtoverlay` emits no deletion
   opcodes. The merge script deletes the Rocket sibling nodes
   (`/npu@fdac0000`, `/npu@fdad0000`, `/iommu@fdab9000/fdaca000/fdada000`)
   post-merge with `fdtput -r`.

4. **Offline-only reproducibility.** Ad-hoc shell commands are replaced by
   `scripts/apply-overlay.sh` (cpp → dtc → fdtoverlay → fdtput -r/-d) and
   `scripts/build-module.sh` (stages the submodule into `build/`, applies
   `patches/0001-devfreq-governor-conditional.patch`, builds).

### Final verification (Armbian 6.18.22 on Orange Pi 5 Pro)

```
[drm] Initialized rknpu 0.9.8 for fdab0000.npu on minor 2
RKNPU fdab0000.npu: RKNPU: devfreq enabled, initial freq: 200000000 Hz, volt: 800000 uV
```

```
$ ls /dev/dri/
card0  card1  card2  renderD128  renderD129
$ cat /sys/module/rknpu/version
0.9.8
$ grep fdab /proc/interrupts
146: ... GICv3 142 Level  fdab0000.npu
147: ... GICv3 143 Level  fdab0000.npu
148: ... GICv3 144 Level  fdab0000.npu
```

### Passive smoke test

`scripts/test-rknn.sh` (runs on the board) confirms the userspace path end to
end without exercising the NPU:

```
DRM identity via /dev/dri/renderD129:
  driver     : rknpu
  version    : 0.9.8
  description: RKNPU driver

Debugfs (/sys/kernel/debug/rknpu/):
  version  : RKNPU driver: v0.9.8
  freq     : 200000000
  volt     : 800000
  power    : off
  load     : NPU load:  Core0:  0%, Core1:  0%, Core2:  0%,

NPU interrupts:
  146: 142 fdab0000.npu
  147: 143 fdab0000.npu
  148: 144 fdab0000.npu
```

The DRM `DRM_IOCTL_VERSION` ioctl identifies the driver as `"rknpu"` (vendor),
which confirms the overlay and binding, not the mainline `"rocket"` stack.
Debugfs entries are live (the `load` file was what made it into the original
user question — it exists as soon as the module is loaded; if it's missing,
the module isn't loaded).

### Real inference on the NPU (2026-04-16)

`scripts/test-inference.sh` downloads `librknnrt.so` + `rknn_api.h` +
`mobilenet_v1.rknn` from airockchip/rknn-toolkit2, compiles
`tests/rknn_smoke.c`, and runs inference against the real NPU. Results
on Armbian 6.18.22 / Orange Pi 5 Pro:

```
SDK api=2.3.2 (429f97ae6b@2025-04-09T09:09:27) driver=0.9.8

core_mask=auto   iters=200   8.11 ms/inf   123.3 inf/s
core_mask=0_1_2  iters=300   3.69 ms/inf   270.9 inf/s
```

- **Single-core baseline**: 123 inf/s MobileNet v1, matching vendor
  expectations for RK3588 NPU at the lowest OPP.
- **Multi-core**: 2.2× scaling to 271 inf/s, with all three cores
  registering work (debugfs `load` showed Core0: 78%, Core1: 73%,
  Core2: 73% during a run). IRQ counters on virq 146/147/148 all
  incremented proportionally (~2× iters for core 0 in multi-core,
  ~2× iters / 3 for cores 1 and 2).
- **Performance is at the floor**: `freq` and `volt` stayed pinned at
  200 MHz / 800 mV the whole time. The vendor's custom governor would
  have scaled up under load; our `simple_ondemand` fallback doesn't
  receive the busy signal in the shape it expects, so the OPP never
  changes. A 1 GHz OPP would be 3–5× faster but requires either a
  driver patch that feeds devfreq a proper busy/total ratio, or
  porting parts of `rockchip_system_monitor` back in.

This **validates the project's core hypothesis**: the vendor RKNN SDK
binaries work against our mainline-kernel driver port. Downstream
consumers (rkllama + Gemma on NPU, or any other librknnrt-based
pipeline) have a proven foundation to build on.

### Known issue: devfreq userspace governor hangs the board

Switching the `fdab0000.npu` devfreq governor to `userspace` and then writing
a frequency (via `max_freq`/`min_freq`/`userspace/set_freq`) freezes the board
— SSH becomes unresponsive, LEDs stay steady, a hard power-cycle is the only
recovery. The passive devfreq reads are fine; only *writes* trigger the hang.

Most likely cause: the `simple_ondemand` fallback governor (from our
`patches/0001-devfreq-governor-conditional.patch`) drives the SCMI clock +
power-domain transition without the vendor's `rockchip_system_monitor` layer,
which would normally coordinate voltage-first / frequency-second ordering and
suppress transitions while jobs are queued. When userspace forces a
transition, the SCP firmware path deadlocks or gets into a state the kernel
never recovers from.

Workarounds for now:
- Leave devfreq on its default governor (`simple_ondemand` here, chosen
  automatically because our overlay's OPP table has `opp-microvolt`).
- Do not poke `min_freq` / `max_freq` / `set_freq` from userspace.

Real fix is upstream work: either port enough of `rockchip_system_monitor` /
`rockchip_opp_select` to the out-of-tree module, or rebuild the custom
`rknpu_ondemand` governor on top of private API that the module ships itself
instead of the kernel's `<linux/devfreq-governor.h>`.

## Next steps

1. Install via DKMS so the module persists across reboots. Currently the
   build + insmod cycle only lives in `/tmp`, so every reboot requires a
   rebuild. `scripts/install-dkms.sh` exists but hasn't been exercised
   against the patched tree.
2. Upstream `patches/0001-devfreq-governor-conditional.patch` to
   w568w/rknpu-module so the carry becomes temporary.
3. Restore NPU frequency scaling (see Known Issues). Either feed
   `simple_ondemand` a proper busy/total signal from the driver, or port
   parts of `rockchip_system_monitor` to rebuild the vendor's custom
   `rknpu_ondemand` governor. 3–5× throughput headroom is currently
   locked behind this.
4. Investigate the devfreq userspace-write hang (see Known Issues). Low
   priority if the default governor stays stable — no consumer we care
   about writes to devfreq from userspace.
5. Optional: wire a working IOMMU node and re-enable `iommus` on the
   combined node (IOMMU v2 has the `dead000000000122` bug history — test
   incrementally with `cma=128M` fallback first).
6. Evaluate whether the OPP table needs a 200 MHz entry (driver's initial
   frequency is lower than the table's current min of 300 MHz; likely why
   the NPU starts at 200 MHz and can't scale down further).
