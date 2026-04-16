# Contributing to rknpu-rk3588

## License

All contributions must be licensed under **GPL-2.0-only** (SPDX: `GPL-2.0-only`). This matches the Linux kernel license and the upstream RKNPU driver.

Do not use GPL-2.0-or-later. The Linux kernel is explicitly GPL-2.0-only.

## Developer Certificate of Origin (DCO)

By contributing to this project, you certify that your contribution is your own work (or you have the right to submit it) and you agree to license it under GPL-2.0-only. Sign off your commits:

```bash
git commit -s -m "feat: add RK3588 clock bindings"
```

This adds a `Signed-off-by` line to your commit message, certifying compliance with the [DCO](https://developercertificate.org/).

## Commit Style

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature or hardware support
- `fix:` — bug fix
- `docs:` — documentation changes
- `chore:` — build, CI, tooling changes
- `test:` — test additions or changes

Reference upstream sources in commit messages when applicable.

## What to Contribute

### High-value contributions

- **Testing on RK3588 hardware**: The DT overlay is currently untested. Reports from any RK3588/RK3588S board are valuable.
- **DT overlay fixes**: Corrections to register addresses, clock bindings, or power domain mappings.
- **Board-specific overlays**: If your RK3588 board needs different pin configurations or has different hardware.
- **Documentation**: Porting notes, testing procedures, kernel version compatibility.

### Before submitting

1. Read `CLAUDE.md` for project context and known issues.
2. Test on real hardware if possible. Note kernel version, board, and dmesg output.
3. For DT overlay changes, include the source of your register values (vendor DTS line number, datasheet page, etc.).

## Testing

See `docs/testing.md` for test procedures. At minimum:

1. Compile the DT overlay without errors: `dtc -@ -I dts -O dtb -o test.dtbo dts/rk3588-rknpu-overlay.dts`
2. Build the kernel module: `cd ref/rknpu-module && make KDIR=/lib/modules/$(uname -r)/build`
3. If on RK3588 hardware: load the overlay and module, verify `/dev/dri/renderD129` appears.

## Code Style

- DT overlays: follow kernel DTS coding style (tabs for indentation, lowercase hex addresses).
- Shell scripts: POSIX-compatible where possible, use `shellcheck`.
- Documentation: GitHub-flavored markdown.
