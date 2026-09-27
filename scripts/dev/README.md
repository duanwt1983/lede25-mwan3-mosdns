# Dev scripts

Firmware changes belong in `files/`, `patches/`, and `diy-part2.sh`. A full image build installs everything; **no hotfix or hot-deploy step is required after flashing**.

`lede-lansec` (局域网安全) is part of that overlay: backend, init, LuCI page, menu, ACL, and uci-defaults. New images must get it from source, not from `deploy-lansec.sh`.

`diy-part2.sh` ends with **LEDE overlay compile self-check**, which verifies the same assets that used to be pushed by hotfix scripts.

## Optional router tools

Run these on macOS. They need `curl`, `jq`, and `python3`. The first argument is the router address and the second is the password (default `password`, the firmware's first-boot password).

```sh
./scripts/dev/topology-pull-from-router.sh 192.168.9.1
```

| Script | Purpose |
|--------|---------|
| `topology-pull-from-router.sh` | Pull topology layout JSON from a live router for editing |

Other `scripts/dev/*.sh` files are the old on-router diagnostics and hot-deploy helpers. They use the same two arguments. `diag-wan2-count.sh` is the script that runs on the router; `run-diag-wan2-count.sh` sends it there.

## Removed hotfix scripts

These were deleted because their content is baked into the firmware build:

- `hotfix-all-81.ps1`, `hotfix-brand-css-81.ps1`, `hotfix-mwan3-menu-81.ps1`
- `hotfix-fullwidth-pages.ps1`, `hotfix-mwan3-globals.ps1`, `hotfix-brand-title-font.ps1`
- `hotfix-interfaces-encoding.ps1`, `hotfix-iface-bw.ps1`, `deploy-interfaces-js.ps1`
- `check-mwan3-menu-81.ps1`, `fetch-*-81.ps1`, `read-mwan3-menu-81.ps1`, `verify-hotfix-81.ps1`

To test on an **old** firmware without reflashing, copy files from `files/` manually or use `scp`/`ubus file write` — do not rely on removed scripts.
