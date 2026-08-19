# freight — plan

One Dart API over iOS Managed Background Assets and Google Play Asset Delivery,
for shipping large assets outside the app bundle.

## Why this exists

Apps that need more than a few hundred megabytes — games, offline maps, on-device
ML models — cannot ship them in the bundle. Both stores solve this, and both
solutions are invisible from Flutter:

* **iOS 26** replaced the old `BADownloaderExtension` dance with *Managed
  Background Assets*: declarative manifests, a packaging tool, Apple-side hosting,
  and a small runtime API. No extension *code* — but see below, the extension
  *target* is still mandatory.
* **Android** has had Play Asset Delivery for years: asset packs as Gradle
  modules, Play-side hosting, `AssetPackManager` at runtime.

As of iOS 26 the two converged into the same shape — *declare a pack, the store
hosts it, ask for it at runtime, read files* — which is what makes a single
abstraction possible. Before iOS 26 it was not.

On pub.dev today: nothing for iOS, and two Android-only wrappers
(`asset_delivery`, `flutter_play_asset_delivery`) that hand back a raw path and
stop there.

## Ground truth

Verified locally against Xcode 26.5 (`ba-package` 1.2) and the iOS 26.5 SDK
`BackgroundAssets.swiftinterface` — not from documentation prose.

### Download policies map 1:1 across platforms

| freight        | iOS `downloadPolicy` | Android delivery | behaviour                                            |
|----------------|----------------------|------------------|------------------------------------------------------|
| `essential`    | `essential`          | install-time     | downloaded during install; app cannot open until done |
| `prefetch`     | `prefetch`           | fast-follow      | starts during install, may finish afterwards          |
| `onDemand`     | `onDemand`           | on-demand        | never automatic; the app asks                         |

iOS policies additionally take `installationEventTypes`
(`firstInstallation`, `subsequentUpdate`).

### There is no pack directory

The single most important API constraint. `AssetPackManager` exposes:

```swift
func url(for path: FilePath) throws -> URL
func contents(at path: FilePath, searchingInAssetPackWithID: String?, options:) throws -> Data
func descriptor(for path: FilePath, searchingInAssetPackWithID: String?) throws -> FileDescriptor
```

Packs are a *virtual filesystem*: you address a logical path, and the manager
resolves it — across every downloaded pack, or scoped to one. There is no
"give me this pack's folder".

This is why the public API is path-shaped rather than directory-shaped, and why
`FreightBundle` is the centre of the design rather than a convenience: a Flutter
asset key already *is* a logical path.

Android does expose a real directory (`AssetPackLocation.assetsPath()`), so the
Android implementation resolves logical paths beneath it. The asymmetry stays
inside the plugin.

### Runtime surface actually available

```swift
actor AssetPackManager {
  static let shared
  var allAssetPacks: Set<AssetPack> { get async throws }
  func assetPack(withID:) async throws -> AssetPack
  let statusUpdates: AsyncSequence<DownloadStatusUpdate, Never>
  func statusUpdates(forAssetPackWithID:) -> AsyncSequence<...>   // nonisolated
  func ensureLocalAvailability(of:requireLatestVersion:) async throws   // iOS 26.4+
  func assetPackIsAvailableLocally(withID:) -> Bool                     // iOS 26.4+, sync
  func localStatus(ofAssetPackWithID:) async -> AssetPack.Status        // iOS 26.4+
  func checkForUpdates() async throws -> (updatingIDs: Set<String>, removedIDs: Set<String>)
  func remove(assetPackWithID:) async throws
}

enum DownloadStatusUpdate { case began, paused, downloading(_, Progress), finished, failed(_, Error) }
struct AssetPack { let id: String; let downloadSize: Int; let version: Int; let userInfo: Data? }
struct AssetPack.Status: OptionSet { downloadAvailable, updateAvailable, upToDate,
                                     outOfDate, obsolete, downloading, downloaded }
enum ManagedBackgroundAssetsError { case assetPackNotFound(withID:), fileNotFound(at:) }
```

`AssetPack.Status` is an **OptionSet**, not an enum — states combine. The Dart
side flattens it into a sealed `PackStatus` for ergonomics and keeps the raw bits
available.

### Two preconditions that crash rather than throw

Found by running the plugin, not by reading documentation. `AssetPackManager.shared`
calls `fatalError` — it does not throw — when either is missing:

```
BackgroundAssets/AssetPackManager.swift:218: Fatal error: The app couldn't be
validated: The bundle's info dictionary lacks a string value for the key "BAAppGroupID".

BackgroundAssets/AssetPackManager.swift:218: Fatal error: The app couldn't be
validated: The app lacks a Background Assets downloader extension.
```

1. **`BAAppGroupID` in the app's Info.plist**, plus the App Groups capability.
   Packs live in an app group container.
2. **An embedded downloader extension target.** Managed Background Assets removes
   the need to *write* one — `ManagedDownloaderExtension` has a default
   implementation for every requirement, so the whole source file is:

   ```swift
   @main
   struct FreightDownloaderExtension: ManagedDownloaderExtension {}
   ```

   But the target must exist, carry
   `EXExtensionPointIdentifier = com.apple.background-assets.content-request`,
   and be embedded in the app.

Because these trap, the plugin checks both *before* touching `AssetPackManager`
and reports `MissingAppGroupException` / `MissingExtensionException`. An app that
forgets one gets a readable error instead of a crash.

This is also the sharpest possible confirmation of where the value is: four lines
of Swift, wrapped in an Xcode target that nobody wants to create by hand. The CLI
generating that target *is* the product.

### Packaging: logical paths come from the working directory

`ba-package` records the path of each file *relative to the directory it was
invoked from*. A `{"directory": "packs/tutorial"}` selector produces
`Contents/packs/tutorial/welcome.txt` inside the archive, and `{"directory": "."}`
fails outright ("an item with the same name already exists").

So the logical path a caller passes to `Freight.read` is decided at build time by
where the tool ran. The CLI therefore **stages**: expand the pack's globs against
its declared root, emit explicit `{"file": ...}` selectors relative to that root,
and invoke `ba-package` with the root as the working directory. Verified to give
exactly `welcome.txt`, `steps.json`, `nested/deep.txt`.

### Self-hosted download manifest

`ba-package download-manifest create --download-base-url URL` emits:

```json
{ "assetPacks": [ { "id": "tutorial", "url": "URL/tutorial", "version": 0,
                    "downloadSize": 596, "downloadPolicy": {...},
                    "host": { "thirdParty": {} } } ] }
```

The pack URL is the base plus the pack id, **with no file extension** — a server
must serve the `.aar` at `/tutorial`, not `/tutorial.aar`. The device appends a
platform query parameter when fetching the manifest.

For development Apple ships `xcrun ba-serve`, which serves packs over the local
network and has a `url-override` subcommand for pointing a device at it. Prefer
it to a hand-rolled static server.

### The extension target, precisely

Assembled and built successfully in `packages/freight/example/ios`; these are the parts that
matter, and each one was a failure first:

* Product type is `com.apple.product-type.extensionkit-extension`, not
  `app-extension`. The `xcodeproj` gem has no symbol for it, so the type is set
  literally. The binary is a Mach-O **executable**, not a bundle.
* The built extension lands in `YourApp.app/Extensions/`, **not** `PlugIns/`.
  Code detecting it must look in both.
* `Info.plist` needs the full set of bundle keys, not just
  `EXAppExtensionAttributes`. With `GENERATE_INFOPLIST_FILE = NO` nothing is
  injected, and an appex without `CFBundleIdentifier` fails the build with
  "Embedded binary's bundle identifier is not prefixed with the parent app's" —
  a misleading message for a missing key. `CFBundlePackageType` is `XPC!`.
* The embed phase must run **before** Flutter's "Thin Binary" script and the
  CocoaPods embed step. Appended last, Xcode reports a dependency cycle rather
  than a missing file.
* The extension must be signed. `CODE_SIGNING_ALLOWED = NO` produces an appex
  that `extensionkitd` never registers.

### Simulator does not run Background Assets

The end-to-end download is **not yet proven**. With a correctly built and
embedded extension, `AssetPackManager` still traps with "The app lacks a
Background Assets downloader extension" on the iOS 26.5 simulator, and no
`FreightDownloader` registration appears in the system log.

This matches Apple's own guidance: Background Assets checks for a real signing
identity, and the `ba-serve` URL override is known not to work in the simulator.
Physical-device testing is the documented path.

Consequence for the plan: **0.2 cannot be finished on the simulator.** The next
step is a device run with `ba-serve` and `ba-serve url-override`, and the CLI
should not be written until the logical paths and policies are confirmed against
one.

### Deployment target

`AssetPackManager` is iOS 26.0+, but the good methods
(`ensureLocalAvailability(of:requireLatestVersion:)`, `assetPackIsAvailableLocally`,
`localStatus`) landed in **26.4**. The 26.0 spellings are already deprecated.

Decision: **minimum iOS 26.0**, with `if #available(iOS 26.4, *)` for the modern
paths and the deprecated overloads as fallback. Apps supporting iOS ≤ 25 are out
of scope — the legacy `BADownloaderExtension` path would triple the work for a
shrinking audience. This is stated in the README's first paragraph.

### Self-hosting removes the App Store Connect dependency

`ba-package download-manifest create --download-base-url <url>` generates the
manifest a self-hosting server must serve; the device appends a platform query
parameter when requesting it.

This is the development and CI story: a static file server is enough. Apple-hosted
packs (upload to App Store Connect, TestFlight-only for testing) come later.

## Public API

```dart
// Declared in freight.yaml, not in code.
final pack = Freight.pack('maps_europe');

await pack.ensureDownloaded();
pack.watch().listen((status) => switch (status) {
  PackNotDownloaded()                 => ...,
  PackDownloading(:final fraction)    => ...,
  PackPaused()                        => ...,
  PackReady(:final version)           => ...,
  PackFailed(:final error)            => ...,
});

// Reading — path-shaped, because packs are a virtual filesystem.
final bytes = await Freight.read('maps/berlin.mbtiles');
final file  = await Freight.resolve('maps/berlin.mbtiles');

// The differentiator: downloaded packs behave like ordinary Flutter assets.
Image(image: FreightImage('maps/pin.png'))
DefaultAssetBundle(bundle: Freight.bundle(), child: ...)
```

```yaml
# freight.yaml
packs:
  tutorial:
    delivery: essential          # essential | prefetch | onDemand
    events: [firstInstallation]  # automatic policies only
    root: assets/tutorial        # logical paths are relative to this
    files: ["**"]                # globs, relative to root
  maps_europe:
    delivery: onDemand
    root: assets/maps/europe
    files: ["**/*.tiles", "index.txt"]
    exclude: ["**/draft_*.tiles"]
```

`root` is the load-bearing field. A file at `<root>/nested/deep.txt` is read
back as `nested/deep.txt`, so the root is what decouples the logical paths from
wherever the sources happen to sit in the repository.

## Two packages

`freight` is the plugin and depends on nothing but Flutter. `freight_cli` holds
the build-time tooling and is pure Dart. They are split so an app shipping the
plugin does not also carry a YAML parser, a glob matcher and an argument parser
it never runs, and because a package nested inside another would be swept into
the outer one's published archive.

The split costs nothing in coupling: `freight_cli` does not import `freight`.
The two share the `freight.yaml` format, not code.

## Where the work is

| layer          | size   | note                                                        |
|----------------|--------|-------------------------------------------------------------|
| Swift          | small  | actor bridge, `statusUpdates` → EventChannel, error mapping |
| Kotlin         | small  | Play Core `AssetPackManager`, same EventChannel contract     |
| Dart runtime   | medium | sealed status, `AssetBundle` implementation, caching         |
| **CLI / build**| **large** | `freight.yaml` → `Manifest.json` → `ba-package`; Gradle module generation; `freight doctor` |

The CLI is the moat. Wrapping a platform API is a weekend; keeping an Xcode and a
Gradle project correct across `flutter clean` is what nobody has done.

## Releases

**0.1 — iOS, self-hosted, runtime only.** Packs built by hand following the
README. `ensureDownloaded`, status stream, `read`/`resolve`. Example app against
a local static server. Goal: prove the API against a real device before
automating around it.

**0.2 — `freight.yaml` and the CLI.** Done bar the device run: `freight build`
packages with `ba-package`, `freight setup` generates the downloader extension
target, and `freight doctor` checks a project. What remains is confirming a
download on hardware. Generate `Manifest.json`, drive
`ba-package`, emit the self-hosted download manifest, and — the part that
matters — create the downloader extension target, set `BAAppGroupID`, and add
the App Groups capability. This is where it stops being a wrapper.

**0.3 — Android.** The runtime half is done: Play Asset Delivery behind the same
channel contract, with the asymmetries recorded rather than hidden. Gradle
asset pack module generation in the CLI is what remains before packs can
actually ship to Android.

The abstraction held. Three things did not map cleanly and are handled at the
edge rather than in the shared API: Play cannot enumerate packs an app only
declares, it has no per-pack update notion, and it has no per-pack listener, so
a stream scoped to one pack is filtered natively on Android and by the system on
iOS. None of that reached the Dart surface.

**0.4 — `FreightBundle`, `FreightImage`.** Flutter-native asset integration.
The part that earns likes.

**0.5 — `freight doctor` and CI recipes.** Apple ships Linux packaging tools, so
packs can be built in GitHub Actions — document it; nobody else has.

**1.0 — Apple-hosted packs** (App Store Connect upload, TestFlight) and
localized packs (iOS 27, BCP-47).

## Risks

* **iOS 26+ only.** Narrow today, widening every month. Non-negotiable given the
  cost of the legacy path.
* **Apple-hosted packs need TestFlight to test**, and the developer forums show
  Transporter rejecting first uploads. Deferred to 1.0 precisely for this reason;
  self-hosting carries 0.1–0.5.
* **Android pack size caps**: 1 GB install-time, 512 MB per fast-follow/on-demand
  pack. iOS limits differ. The CLI should warn at build time rather than let the
  store reject.
* **Apple is investing here** — Steam asset converter, a WWDC26 session tying
  Background Assets to StoreKit. Live framework, not a frozen one.
