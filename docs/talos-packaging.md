# Talos Linux packaging (downstream)

This repo is the source of truth for the **driver + DT overlay + DKMS
packaging** for general-purpose Linux (Armbian, Debian, Ubuntu). It is
not the only downstream consumer of the underlying
[`w568w/rknpu-module`](https://github.com/w568w/rknpu-module) source —
a parallel effort wraps the same driver for
[Talos Linux](https://www.talos.dev/) as an immutable, API-driven k8s
node OS.

This doc exists so someone landing on this repo from a Talos context
(or someone here wondering "could I run this on Talos?") gets a clear
map of the relationship without us expanding scope into Talos packaging
ourselves.

## The two active Talos-for-RK3588 efforts

- **[milas/talos-sbc-rk3588](https://github.com/milas/talos-sbc-rk3588)** —
  the Talos installer side. Custom U-Boot + kernel with Collabora's
  RK3588 patches. Current board support: Radxa Rock 5A / 5B. Orange Pi
  5 Pro is not in the tested matrix yet.

- **[schwankner/talos-rk3588-npu](https://github.com/schwankner/talos-rk3588-npu)** —
  the NPU side. Packages `rknpu.ko` (from w568w) and `librknnrt.so` as
  Talos **System Extensions**, plus a Kubernetes **CDI device plugin**
  that exposes the NPU to unprivileged pods (`hostUsers: false` +
  `procMount: Unmasked` + CDI injection — no `privileged: true`).
  Tested on Turing RK1 (RK3588); other RK3588 boards planned.

## How this repo relates

Both repos and the schwankner extension consume **the same
`w568w/rknpu-module` 0.9.8 driver source** we do:

```
                     w568w/rknpu-module (upstream)
                              │
               ┌──────────────┴──────────────┐
               │                             │
     rknpu-rk3588 (this repo)        schwankner/talos-rk3588-npu
     — patches in patches/           — extensions in rockchip-rknpu/
     — DKMS packaging                — Talos extension packaging
     — DT overlay + merge pipeline   — installer via milas/talos-sbc-rk3588
     — Armbian / Ubuntu / Debian     — Talos Linux
```

**Driver-level fixes discovered here are portable.** Our current
`patches/0001-devfreq-governor-conditional.patch` and the in-tree DT
overlay embody several fixes that almost certainly benefit schwankner's
extension too:

- The `devfreq-governor.h` conditional (private in 6.16+, breaks
  out-of-tree builds otherwise)
- The 4-cell GIC interrupt spec (mainline's `#interrupt-cells = 4`
  versus the vendor BSP's 3 — source of the original IRQ blocker,
  see `porting-journal.md`)
- The `rknpu-supply` / `mem-supply` wiring (driver asks for those
  names, mainline DT uses `npu-supply` / `sram-supply`)

When these patches land upstream in `w568w/rknpu-module` (gated by
[issue #2](https://github.com/antonioacg/rknpu-rk3588/issues/2)),
schwankner's extension will pick them up automatically on the next
version bump. Until then, the two packaging paths carry them
independently.

## Developing for Talos when this repo is the driver source

The short version: **develop driver and DT changes here, on Armbian.**
Talos is a deployment target, not a dev environment — it has no
shell, no `apt`, no `insmod`. Iterating on kernel/module code against
a running Talos node means rebuilding an OCI extension image,
publishing it to a registry, and running `talosctl upgrade` on the
node (2–3 minute reboot cycles minimum). That's fine for validation,
painful for inner-loop work.

Our Armbian + DKMS dev loop is seconds: edit, `make`, `insmod`,
observe `dmesg`. Whatever the driver does on Armbian it will do on
Talos — same kernel module, same ioctl surface. Once a change is
stable here, it's mechanical to land in schwankner's extension
packaging.

The Talos-specific surface is genuinely narrow:

| Concern | Home | Needs a Talos node? |
|---|---|---|
| Kernel module source | `w568w/rknpu-module` + our `patches/` | No — Armbian dev loop |
| DT overlay source | `dts/rk3588-rknpu-overlay.dts` (this repo) | No |
| Armbian/Debian/Ubuntu packaging | `scripts/install-dkms.sh` (this repo) | No |
| Talos extension manifest | schwankner's `rockchip-rknpu/manifest.yaml` | No — `bldr` builds on any Linux with Docker |
| CDI device plugin Go code | schwankner's `plugins/` | No — CDI runs on any containerd ≥ 1.30 |
| Talos installer + board variant | `milas/talos-sbc-rk3588/boards/` | Only for the final flash + validation step |

So the typical flow for cross-pollinating between this repo and
Talos:

1. Fix / change lands here (Armbian dev loop, fast).
2. If the change is upstreamable, open PR against `w568w/rknpu-module`.
3. Either before or after upstream merge, the same patch can land in
   schwankner's extension as an equivalent change to their Kbuild
   patch, and they rebuild their OCI images.
4. Talos nodes pick it up on the next `talosctl upgrade`.

## When to pivot vs coexist

There isn't a forced choice. The two packaging paths cover different
consumer profiles:

- **This repo's DKMS path** — the right answer for anyone running a
  general-purpose Linux (Armbian-current, Debian trixie, Ubuntu Noble)
  on RK3588 who wants the vendor RKNN SDK. Ships via `apt + dkms`,
  auto-rebuilds on kernel upgrades.
- **Talos + schwankner** — the right answer for someone specifically
  wanting an immutable, k8s-native node with unprivileged NPU access.
  The CDI plugin solves the "NPU in a pod without `privileged: true`"
  problem more cleanly than any `hostPath`-based approach.

If you want unprivileged NPU pods without leaving Armbian, the CDI
plugin itself is substrate-agnostic — it's a Go DaemonSet + a
containerd config tweak. That's a "lift schwankner's plugin onto
k3s-on-Armbian" project, not a Talos pivot.

## Scope boundary

This repo does **not** ship Talos extensions, installer images, or
`talosctl` tooling — those stay in schwankner's and milas's repos.
What this repo commits to is: the driver and DT overlay stay
well-documented, reproducible, and testable, so downstream packagers
(us for DKMS, schwankner for Talos) can consume the same base without
re-deriving fixes.
