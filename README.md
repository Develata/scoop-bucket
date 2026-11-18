# Develata's Scoop bucket

[![Tests](https://github.com/Develata/scoop-bucket/actions/workflows/ci.yml/badge.svg)](https://github.com/Develata/scoop-bucket/actions/workflows/ci.yml) [![Excavator](https://github.com/Develata/scoop-bucket/actions/workflows/excavator.yml/badge.svg)](https://github.com/Develata/scoop-bucket/actions/workflows/excavator.yml)

[Scoop](https://scoop.sh) manifests for software published by Develata.

## Install

```pwsh
scoop bucket add develata https://github.com/Develata/scoop-bucket
scoop install develata/rss-reader
scoop install develata/stickymd
```

## Manifests

| Manifest | Software | Provides |
| --- | --- | --- |
| [`rss-reader`](bucket/rss-reader.json) | [RSS-Reader](https://github.com/Develata/RSS-Reader) | Start menu shortcut `RSS-Reader`, command `rssr` |
| [`stickymd`](bucket/stickymd.json) | [StickyMD](https://github.com/Develata/StickyMD) | Start menu shortcut `StickyMD` |

RSS-Reader keeps its library in a `RSS-Reader` folder next to the executables. The manifest persists that whole folder, so the desktop app and `rssr` share one library and it survives `scoop update` and `scoop uninstall` (without `--purge`). Quit both before updating.

StickyMD keeps its note, settings and images in a `note` folder next to `StickyMD.exe` and refuses to start if that folder is a junction, so its manifest does not use `persist`. Instead, whenever `scoop update` or `scoop uninstall` removes a version, `pre_uninstall` copies the folder to `persist\stickymd\note` (the copy before it stays in `note.previous`), and `pre_install` copies it into the next version. Quit StickyMD from its tray menu first: the hook refuses to copy while StickyMD runs. The [StickyMD workflow](.github/workflows/stickymd.yml) checks this with real releases, including failing hooks.

## Updates

The [Excavator](.github/workflows/excavator.yml) workflow runs every four hours: it reads each manifest's `checkver` (the latest GitHub release), rewrites the version, URLs and hashes from `autoupdate`, and commits the change. A new release is therefore picked up within about four hours without editing this repository.

## Adding a manifest

Copy `bucket/app-name.json.template` to `bucket/<name>.json`, fill it in, and include `checkver` and `autoupdate` so Excavator can keep it current. The [CI](.github/workflows/ci.yml) workflow validates manifests on every push and pull request.
