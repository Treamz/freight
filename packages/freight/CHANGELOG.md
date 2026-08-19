# Changelog

## Unreleased

* Added the Android runtime, backed by Play Asset Delivery, behind the same API
  as iOS: `ensureDownloaded`, the status stream, `read` and `resolve` all work
  against downloaded asset packs, and install-time packs fall back to the
  ordinary asset manager. Two differences are worth knowing rather than
  discovering: `allPacks` lists only packs already on the device, because Play
  has no API for the ones an app merely declares, and `requireLatest` does
  nothing, because Play versions asset packs with the app. Generating the Gradle
  asset pack modules is handled by `freight_cli`.
* Added a consumer ProGuard rule, so apps do not have to discover it themselves:
  the Play Asset Delivery Kotlin extensions reference a Play Services annotation
  that is not on the classpath, and R8 fails a release build over the missing
  class.

* Moved the `freight build` and `freight doctor` commands into a separate
  `freight_cli` package, so an app depending on `freight` no longer carries
  `args`, `glob`, `path` and `yaml` for tooling it never runs. This package now
  depends on nothing but Flutter. Add `freight_cli` as a dev dependency to build
  packs.

* Added the `freight doctor` command. Managed Background Assets reports most
  misconfiguration by crashing on a device rather than returning an error, so
  `doctor` looks for those problems locally instead: a missing `BAAppGroupID`,
  an app group only one target holds, no downloader extension embedded, a pack
  whose globs match nothing, and an unusable `ba-package`.

* Added the `freight build` command. It reads `freight.yaml`, resolves each
  pack's globs, generates the asset-pack manifests and packages them with
  Apple's `ba-package`, and with `--base-url` also writes the download manifest
  a self-hosting server must serve. Each pack declares a `root`, which is what
  decides the logical paths the app reads back: a file at
  `<root>/nested/deep.txt` is read as `nested/deep.txt` regardless of where the
  sources sit in the repository.

* Added `FreightBundle`, an `AssetBundle` backed by downloaded asset packs, and
  `Freight.bundle()` to build one. A pack addresses files by the logical path
  they had when it was built, which is what an asset key already is, so widgets
  taking a key can read from packs without knowing where the bytes came from.
  Keys no pack contains fall through to the app's own assets, so a single bundle
  serves both; `FreightBundle.packsOnly` opts out of that when a silent fallback
  would hide a pack that was never downloaded.
* Added `FreightImage`, an `ImageProvider` reading from a downloaded pack. It
  does not download one — an image widget is the wrong place to begin a transfer
  that may be hundreds of megabytes, with nowhere to report progress.

* Fixed detection of the Background Assets downloader extension, which looked
  only in the app's `PlugIns/` directory. ExtensionKit embeds extensions in
  `Extensions/` instead, so a correctly configured app was still told it had no
  extension. Both locations are now searched.
* Added `doc/ios-setup.md`, a walkthrough of the iOS project configuration
  Managed Background Assets requires: adding the downloader extension with
  Xcode's Background Download Extension template, wiring the app group, building
  packs with `ba-package`, self-hosting, and a table mapping each failure message
  to its actual cause. Several of those messages point at the wrong problem —
  a missing `CFBundleIdentifier` in the extension reports a bundle identifier
  prefix mismatch, for instance.
* Documented the iOS setup Managed Background Assets requires — the app group,
  `BAAppGroupID`, and the downloader extension target — along with the fact that
  the system crashes rather than returning an error when either is missing.
  `freight` checks both before touching the platform and throws
  `MissingAppGroupException` or `MissingExtensionException`.
