# Dev scripts

Firmware changes belong in `files/`, `patches/`, and `diy-part2.sh`. A full image build installs everything; **no hotfix step is required after flashing**.

`diy-part2.sh` ends with **LEDE overlay compile self-check**, which verifies the same assets that used to be pushed by PowerShell hotfix scripts.

## Optional router tools

| Script | Purpose |
|--------|---------|
| `topology-pull-from-router.ps1` | Pull topology layout JSON from a live router for editing |

## Removed hotfix scripts

These were deleted because their content is baked into the firmware build:

- `hotfix-all-81.ps1`, `hotfix-brand-css-81.ps1`, `hotfix-mwan3-menu-81.ps1`
- `hotfix-fullwidth-pages.ps1`, `hotfix-mwan3-globals.ps1`, `hotfix-brand-title-font.ps1`
- `hotfix-interfaces-encoding.ps1`, `hotfix-iface-bw.ps1`, `deploy-interfaces-js.ps1`
- `check-mwan3-menu-81.ps1`, `fetch-*-81.ps1`, `read-mwan3-menu-81.ps1`, `verify-hotfix-81.ps1`

To test on an **old** firmware without reflashing, copy files from `files/` manually or use `scp`/`ubus file write` — do not rely on removed scripts.
