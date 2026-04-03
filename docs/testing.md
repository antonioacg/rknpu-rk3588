# Testing Procedures

## Test Environment

| Item | Value |
|------|-------|
| Board | Orange Pi 5 Pro |
| SoC | RK3588S |
| RAM | 16GB |
| Current OS | Ubuntu 24.04, kernel 6.1.0-1026-rockchip |
| Current NPU | rknpu 0.9.7, `/dev/dri/renderD129` |
| Target OS | Armbian edge, kernel 6.19+ |

## Pre-flight Checks

Before testing the DKMS module, verify the target system:

```bash
# 1. Check kernel version (must be 6.19+)
uname -r

# 2. Check SoC compatibility
cat /proc/device-tree/compatible

# 3. Check if NPU node already exists (it shouldn't on mainline)
ls /proc/device-tree/npu@fdab0000/ 2>/dev/null && echo "NPU node exists" || echo "NPU node missing (expected)"

# 4. Check SCMI firmware
ls /sys/firmware/scmi_dev/*/

# 5. Check power domains
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | grep -i npu

# 6. Check available DMA/CMA
cat /proc/meminfo | grep -i cma
```

## Test 1: Compile DT Overlay

```bash
dtc -@ -I dts -O dtb -o rk3588-rknpu.dtbo dts/rk3588-rknpu-overlay.dts
echo "Exit code: $?"
```

Expected: exit code 0, no errors. Warnings about missing phandle targets are expected when compiling without a base DTB.

## Test 2: Build Kernel Module

```bash
cd ref/rknpu-module
make KDIR=/lib/modules/$(uname -r)/build
echo "Exit code: $?"
ls -la rknpu.ko
```

Expected: `rknpu.ko` produced without errors.

## Test 3: Load DT Overlay

```bash
sudo mkdir -p /sys/kernel/config/device-tree/overlays/rknpu
sudo cat rk3588-rknpu.dtbo > /sys/kernel/config/device-tree/overlays/rknpu/dtbo

# Verify node appeared
ls /proc/device-tree/npu@fdab0000/
```

Expected: NPU node appears in `/proc/device-tree/`.

## Test 4: Load Kernel Module

```bash
sudo insmod ref/rknpu-module/rknpu.ko
dmesg | tail -20

# Verify
cat /sys/module/rknpu/version
ls /dev/dri/renderD*
```

Expected: rknpu version `0.9.8`, `/dev/dri/renderD129` present.

## Test 5: RKNN Runtime Smoke Test

Requires `librknnrt.so` from `ref/rknn-llm/rknn-runtime/`.

```bash
# Check if the runtime can open the device
LD_LIBRARY_PATH=ref/rknn-llm/rknn-runtime/Linux/librknn_api/aarch64/ \
  scripts/test-rknn.sh
```

Expected: Runtime reports NPU device with 3 cores, 6 TOPS.

## Test 6: IOMMU (Optional, Advanced)

Only attempt after Tests 1-5 pass with IOMMU disabled.

1. Edit the overlay: change IOMMU `status` from `"disabled"` to `"okay"`.
2. Recompile and reload the overlay.
3. Load the module and check dmesg for IOMMU errors.
4. Run Test 5 again.

Watch for: bus errors, page table allocation failures, DMA mapping errors in dmesg.

## Results Log

| Test | Date | Kernel | Board | Result | Notes |
|------|------|--------|-------|--------|-------|
| -- | -- | -- | -- | -- | No tests performed yet |
