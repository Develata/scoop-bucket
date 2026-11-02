# Develata's Scoop bucket

[![Tests](https://github.com/Develata/scoop-bucket/actions/workflows/ci.yml/badge.svg)](https://github.com/Develata/scoop-bucket/actions/workflows/ci.yml) [![Excavator](https://github.com/Develata/scoop-bucket/actions/workflows/excavator.yml/badge.svg)](https://github.com/Develata/scoop-bucket/actions/workflows/excavator.yml)

[Scoop](https://scoop.sh) manifests for software published by Develata.

## Install

```pwsh
scoop bucket add develata https://github.com/Develata/scoop-bucket
scoop install develata/rss-reader
```

## Manifests

| Manifest | Software | Provides |
| --- | --- | --- |
| [`rss-reader`](bucket/rss-reader.json) | [RSS-Reader](https://github.com/Develata/RSS-Reader) | Start menu shortcut `RSS-Reader`, command `rssr` |

RSS-Reader keeps its library in a `RSS-Reader` folder next to the executables. The manifest persists that whole folder, so the desktop app and `rssr` share one library and it survives `scoop update` and `scoop uninstall` (without `--purge`). Quit both before updating.

## Updates

The [Excavator](.github/workflows/excavator.yml) workflow runs every four hours: it reads each manifest's `checkver` (the latest GitHub release), rewrites the version, URLs and hashes from `autoupdate`, and commits the change. A new release is therefore picked up within about four hours without editing this repository.

## Adding a manifest

Copy `bucket/app-name.json.template` to `bucket/<name>.json`, fill it in, and include `checkver` and `autoupdate` so Excavator can keep it current. The [CI](.github/workflows/ci.yml) workflow validates manifests on every push and pull request.
