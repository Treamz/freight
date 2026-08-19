# freight_cli

Build-time tooling for [`freight`](../freight): resolves asset pack globs,
generates the manifests and packages them with Apple's `ba-package`.

It is a separate package so an app depending on `freight` does not carry a YAML
parser, a glob matcher and an argument parser it never runs. Nothing here
imports `freight` — the two share a file format, not code.

## Install

```yaml
dev_dependencies:
  freight_cli: ^0.1.0
```

```bash
dart run freight_cli:freight doctor
```

Or globally, which gives a plain `freight` command:

```bash
dart pub global activate freight_cli
freight doctor
```

## Commands

### `freight build`

Reads `freight.yaml`, resolves each pack's globs, writes the manifests and
packages them.

```bash
dart run freight_cli:freight build
dart run freight_cli:freight build --base-url https://cdn.example.com/packs
```

`--base-url` also writes the download manifest a self-hosting server must
serve. Each pack's URL is that base plus the pack id **with no file extension**.

Archives land in `build/packs`, with the generated manifests beside them in
`build/packs/manifests` — worth reading when a pack does not hold what you
expected.

### `freight doctor`

Managed Background Assets reports most misconfiguration by crashing on a device
rather than returning an error, so `doctor` looks for those problems on the
machine that can still fix them cheaply.

```
[ok] ba-package: 1.2
[ok] freight.yaml: 2 packs
[ok] pack "tutorial": 3 files, 72 bytes
[ok] BAAppGroupID: group.com.example.app
[ok] App Groups capability: 2 targets grant "group.com.example.app"
[ok] Downloader extension: FreightDownloader
```

It exits non-zero if any check fails.

## `freight.yaml`

```yaml
packs:
  tutorial:
    delivery: prefetch           # essential | prefetch | onDemand
    events: [firstInstallation]  # automatic policies only
    root: assets/tutorial        # logical paths are relative to this
    files: ["**"]                # globs, relative to root
  maps_europe:
    delivery: onDemand
    root: assets/maps/europe
    files: ["**/*.tiles"]
    exclude: ["**/draft_*.tiles"]
```

`root` is the field that matters most. `ba-package` records each file's path
relative to the directory it runs in, so without a declared root the repository
layout would leak into the paths the app reads back. A file at
`<root>/nested/deep.txt` is read as `nested/deep.txt`.

## Requirements

Xcode 26 or newer, which is where `ba-package` ships. macOS only.

## License

MIT
