# RK3588 NPU Kernel Landscape

A comparison of all kernel options for running the NPU on RK3588/RK3588S boards.

## Kernel Options

| Option | Kernel | NPU Driver | RKNN SDK Compatible | Status |
|--------|--------|-----------|---------------------|--------|
| Rockchip BSP 5.10 | 5.10.x | RKNPU 0.9.6 in-tree | Yes | Stable, EOL |
| Rockchip BSP 6.1 | 6.1.99 | RKNPU 0.9.8 in-tree | Yes | Stable, EOL |
| [Joshua Riek Noble](https://github.com/Joshua-Riek/ubuntu-rockchip) | 6.1.0-1026 | RKNPU 0.9.7 in-tree | Yes | Stale (~67 weeks behind) |
| [Armbian vendor](https://www.armbian.com/) | 6.1.x | RKNPU in-tree | Yes | Stable |
| [Joshua Riek Oracular](https://github.com/Joshua-Riek/ubuntu-rockchip) | 6.11 | None | No | No NPU support |
| [Armbian current](https://www.armbian.com/) | 6.12 | None | No | No NPU support |
| [Armbian edge](https://www.armbian.com/) | 6.18+ | Rocket (`accel/rocket`) | No (Mesa/Teflon only) | Different stack |
| **This project** | **6.18+** | **RKNPU 0.9.8 (DKMS)** | **Yes** | **Validated on Armbian 6.18.22 (RK3588S)** |

## The Two NPU Stacks

### Vendor RKNN Stack
- **Driver**: `rknpu` kernel module (out-of-tree for mainline)
- **Userspace**: librknnrt, rknn-toolkit2, rkllama
- **Models**: `.rknn`, `.rkllm` (converted from PyTorch, TensorFlow, ONNX)
- **Maturity**: Production-ready, used by all RK3588 NPU applications today
- **Limitation**: Only ships in BSP kernels (5.10, 6.1)

### Mainline Rocket Stack
- **Driver**: `accel/rocket` (merged in Linux 6.18)
- **Userspace**: Mesa Teflon, TFLite delegate
- **Models**: `.tflite` only
- **Maturity**: Early stage, limited model support
- **Advantage**: In-tree, will be maintained long-term

### Why Both Exist

Rockchip developed the RKNPU driver as a proprietary out-of-tree module. The mainline community independently developed the Rocket driver with a clean-room approach using the Mesa/Teflon stack. They are mutually exclusive -- you cannot run both simultaneously.

For users who need RKNN SDK compatibility (rkllama, rknn-toolkit2, existing .rknn models), the vendor RKNPU driver is the only option. This project makes that possible on modern kernels.

## The Gap

```
Kernel 5.10  --- BSP (RKNPU in-tree) -------- RKNN SDK works
Kernel 6.1   --- BSP (RKNPU in-tree) -------- RKNN SDK works
Kernel 6.2   |
  ...         |-- No NPU support ------------ Nothing works
Kernel 6.17  |
Kernel 6.18  --- Rocket (in-tree) ----------- TFLite only
             \-- RKNPU (DKMS, this project) - RKNN SDK works
Kernel 6.19+ --- RKNPU (DKMS, this project) - RKNN SDK works
```

This project deliberately coexists with the Rocket driver on mainline
6.18+: our DT overlay deletes the Rocket NPU nodes so only our combined
vendor-compat node remains, and the Rocket driver quietly never binds.
Users who want TFLite via Rocket instead of RKNN don't install this repo
(and get Rocket's default behavior).

## Key Resources

- [w568w/rknpu-module](https://github.com/w568w/rknpu-module) -- Proved the DKMS approach on RK3566 + kernel 6.19.3. We carry one patch against it (`patches/0001-devfreq-governor-conditional.patch`) to handle `<linux/devfreq-governor.h>` becoming private in 6.16+; candidate for upstreaming once the [pre-upstream audit](https://github.com/antonioacg/rknpu-rk3588/issues/2) is complete.
- [airockchip/rknn-toolkit2](https://github.com/airockchip/rknn-toolkit2) -- Official RKNN runtime (`librknnrt.so`) + SDK + sample models. `scripts/test-inference.sh` fetches `librknnrt.so` and `mobilenet_v1.rknn` from this repo on demand.
- [airockchip/rknn-llm](https://github.com/airockchip/rknn-llm) -- Official RKNN-LLM runtime (`librkllmrt.so`) and rkllm-toolkit. Downstream consumers targeting on-device LLM inference depend on this; see the planned `gemma-rk3588` repo.
- [rockchip-linux/kernel](https://github.com/rockchip-linux/kernel) -- Vendor BSP kernel source (branches: develop-5.10, develop-6.1, develop-6.6). Authoritative `rk3588s.dtsi`.
- [Armbian](https://www.armbian.com/) -- Community Linux distributions for ARM boards. `current` (6.18.x) is what this project is validated on.
- [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) -- Ubuntu images for RK3588 boards.
