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

### `freight setup`

Adds the downloader extension target to the iOS project, so you do not have to
click through Xcode's template and match up the app group by hand.

```bash
dart run freight_cli:freight setup
```

On **iOS** it writes the extension's source, `Info.plist` and entitlements, gives
the app the same app group, sets `BAAppGroupID`, and edits `project.pbxproj` to
add the target and embed it in the right build phase.

On **Android** it generates a Gradle asset pack module per pack, declares the
`com.android.asset-pack` plugin at whatever version the project already uses for
AGP, includes each module in `settings.gradle.kts` and lists them on the app.

Running it twice does nothing the second time.

It is deliberately narrow: it handles the layout `flutter create` produces and
**refuses anything else** rather than guessing, because a wrong edit to
`project.pbxproj` costs far more to recover from than adding the target by hand.
Xcode's own **Background Download Extension** template is always the fallback —
see [the setup guide](../freight/doc/ios-setup.md).

### `freight build`

Reads `freight.yaml`, resolves each pack's globs, writes the manifests and
packages them.

```bash
dart run freight_cli:freight build
dart run freight_cli:freight build --base-url https://cdn.example.com/packs
dart run freight_cli:freight build --platform android
```

By default it builds for whichever platforms the project has. On **iOS** that
means packaging each pack into an `.aar` with `ba-package`; on **Android** it
stages each pack's files into its module's `src/main/assets`, which is the only
place Play reads them from, under the same logical paths the iOS archive
records.

`--base-url` also writes the download manifest a self-hosting server must
serve. Each pack's URL is that base plus the pack id **with no file extension**.

Archives land in `build/packs`, with the generated manifests beside them in
`build/packs/manifests` — worth reading when a pack does not hold what you
expected.

### `freight doctor`

Both stores report misconfiguration late — iOS by crashing on a device, Android
by failing a bundle build, often only in release — so `doctor` looks for those
problems on the machine that can still fix them cheaply.

```
[ok] ba-package: 1.2
[ok] freight.yaml: 2 packs
[ok] pack "tutorial": 3 files, 72 bytes
[ok] BAAppGroupID: group.com.example.app
[ok] App Groups capability: 2 targets grant "group.com.example.app"
[ok] Downloader extension: FreightDownloader
[ok] Asset pack plugin
[ok] module "tutorial": fast-follow
[ok] module "maps_europe": on-demand
```

It checks whichever platforms the project has, and asks for `ba-package` only
when there is an `ios/` directory. Beyond the wiring it catches drift: changing
a pack's `delivery` in `freight.yaml` does nothing until `freight setup` runs
again, and the bundle builds happily with the stale policy.

It exits non-zero if any check fails.

### Size limits

Both `doctor` and `build` warn when a pack is over what Play accepts — 512 MB
for a fast-follow or on-demand pack, and 1 GB across all install-time packs
together. Warnings, not errors: a project that never ships to Android is
entitled to ignore them, and the store rejection they predict comes long after
the build.

Apple documents its own limits; they are not checked here, because warning about
numbers that were never verified would be worse than staying quiet.

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

For iOS packs: Xcode 26 or newer, which is where `ba-package` ships, so macOS
only. The Android half needs neither.

## License

MIT
