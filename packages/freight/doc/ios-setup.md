# Setting up an iOS project for freight

Managed Background Assets needs two things from the host app: an **app group**
to store packs in, and an embedded **downloader extension**. Both are one-time
setup, and until 0.2 ships the `freight` CLI you do them by hand.

Read the first section even if you skim the rest — the failure mode is a crash,
not an error.

## Why this is worth getting exactly right

`AssetPackManager` calls `fatalError` when either precondition is missing:

```
BackgroundAssets/AssetPackManager.swift:218: Fatal error: The app couldn't be
validated: The bundle's info dictionary lacks a string value for the key "BAAppGroupID".

BackgroundAssets/AssetPackManager.swift:218: Fatal error: The app couldn't be
validated: The app lacks a Background Assets downloader extension.
```

There is no way to catch that. `freight` checks both before it touches the
platform and throws `MissingAppGroupException` or `MissingExtensionException`
instead, so a misconfigured app gets something readable — but it still cannot
download anything until you finish the steps below.

## 1. Add the downloader extension

In Xcode: **File → New → Target → Background Download Extension**.

Choose the extension type when prompted:

| Option | Use it when | Supported by freight |
|---|---|---|
| Apple-Hosted, Managed | Packs uploaded to App Store Connect | yes |
| Self-Hosted, Managed | Packs served from your own server | yes |
| Self-Hosted, Unmanaged | You want to drive downloads yourself | **no** |

Pick one of the **Managed** options. `freight` is built on `AssetPackManager`,
which only exists for managed asset packs; the unmanaged path is the old
`BADownloaderExtension` API and is deliberately out of scope.

The template generates everything the target needs, including an entitlements
file with an app group and the four lines of Swift that are the whole extension:

```swift
import BackgroundAssets
import ExtensionFoundation

@main
struct DownloaderExtension: ManagedDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool { true }
}
```

Every protocol requirement has a default implementation, so you can delete
`shouldDownload` unless you want to skip particular packs on particular devices.

## 2. Give the app the same app group

The extension writes packs into an app group container and your app reads them
back out, so both targets need the same group.

1. Select the **app** target → Signing & Capabilities → **+ Capability** →
   **App Groups**, and add the same group the extension template created —
   typically `group.<your.bundle.identifier>`.
2. Add the group id to the **app's** `Info.plist`:

   ```xml
   <key>BAAppGroupID</key>
   <string>group.com.example.app</string>
   ```

Set `BAAppGroupID` in the app's `Info.plist`, not the extension's. Both targets
need the entitlement; only the app needs the key.

## 3. Point the app at your packs

**Apple-hosted:** nothing to configure. Upload the packs to App Store Connect
separately from the build.

**Self-hosted:** add the manifest URL to the app's `Info.plist`:

```xml
<key>BAManifestURL</key>
<string>https://cdn.example.com/download-manifest.json</string>
```

The device appends a platform query parameter when it fetches this.

## 4. Build the packs

Declare them in `freight.yaml` beside your `pubspec.yaml`:

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
    files: ["**/*.tiles", "index.txt"]
    exclude: ["**/draft_*.tiles"]
```

`root` is the field that matters most. A file at `<root>/nested/deep.txt` is
read back as `nested/deep.txt`, so the root is what keeps your repository
layout out of the paths your app uses.

Delivery policies:

| `delivery`  | Behaviour                                                       |
|-------------|-----------------------------------------------------------------|
| `essential` | Downloaded during install; the app cannot open until it finishes |
| `prefetch`  | Starts during install, may finish afterwards                     |
| `onDemand`  | Never automatic — the app asks                                   |

`essential` and `prefetch` also take `events`, any of `firstInstallation` and
`subsequentUpdate`. An `onDemand` pack has no installation event, so declaring
`events` on one is an error rather than something quietly ignored.

Then:

```bash
dart run freight_cli:freight build
```

Archives land in `build/packs`, with the generated manifests beside them in
`build/packs/manifests` — worth reading when a pack does not contain what you
expected.

If you self-host, pass the base URL to also write the server's download
manifest:

```bash
dart run freight_cli:freight build --base-url https://cdn.example.com/packs
```

Each pack's URL is that base plus the pack id **with no file extension**, so
serve the archive at `/packs/maps_europe`, not `/packs/maps_europe.aar`.

## 5. Test on a device

**Background Assets does not work on the iOS Simulator.** It requires a real
signing identity, and Apple's local server cannot redirect a simulator. An app
that is configured correctly still traps there.

Apple ships a development server:

```bash
xcrun ba-serve serve build/packs
xcrun ba-serve url-override        # point a device at it
```

## Reading packs from Dart

Asset packs are a virtual filesystem, not a folder — there is no "pack
directory" API on the platform. Address the logical paths you packaged:

```dart
await Freight.pack('maps_europe').ensureDownloaded();
final bytes = await Freight.read('berlin.tiles');
```

## Checking the setup

```bash
dart run freight_cli:freight doctor
```

Every check corresponds to something the platform otherwise reports late, on a
device, and mostly by trapping rather than throwing:

```
[ok] ba-package: 1.2
[ok] freight.yaml: 2 packs
[ok] pack "tutorial": 3 files, 72 bytes
[ok] BAAppGroupID: group.com.example.app
[ok] App Groups capability: 2 targets grant "group.com.example.app"
[ok] Downloader extension: FreightDownloader
```

It warns when only one target holds the app group, which builds cleanly and then
does nothing: the extension writes packs into the container the app reads from,
so both need it.

## When something goes wrong

These are the messages this setup actually produces, and what each one means.

| Message | Cause |
|---|---|
| `MissingAppGroupException` | Step 2 — `BAAppGroupID` is absent from the app's `Info.plist` |
| `MissingExtensionException` | Step 1 — no downloader extension is embedded in the app |
| `The app lacks a Background Assets downloader extension` (crash) | The extension exists but the system rejected it — unsigned, or you are on the Simulator |
| `Embedded binary's bundle identifier is not prefixed with the parent app's` | The extension's `Info.plist` has no `CFBundleIdentifier`. Misleading: the identifiers are usually fine, the key is simply missing |
| `Cycle inside <YourApp>` | The embed phase runs too late. It must come before Flutter's "Thin Binary" script and the CocoaPods embed step |
| `PackNotFoundException` | The id is absent from the manifest the device fetched. Try `Freight.checkForUpdates()` |

## Adding the target without the template

The `freight` CLI will generate this target, and `example/ios` shows the result
— it was assembled by script rather than by the Xcode template, which is why the
details below are written down. You only need them if you are doing the same.

* Product type is `com.apple.product-type.extensionkit-extension`, not
  `app-extension`. The output is a Mach-O executable, not a bundle, and it is
  embedded in `YourApp.app/Extensions/` rather than `PlugIns/`.
* The extension's `Info.plist` needs the ordinary bundle keys —
  `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundleName`,
  `CFBundlePackageType` set to `XPC!` — plus:

  ```xml
  <key>EXAppExtensionAttributes</key>
  <dict>
    <key>EXExtensionPointIdentifier</key>
    <string>com.apple.background-assets.content-request</string>
  </dict>
  ```

  With `GENERATE_INFOPLIST_FILE = NO` nothing is injected for you.
* The embed phase belongs immediately after "Resources".
* Leave code signing on. An unsigned extension builds and embeds, but
  `extensionkitd` never registers it and the app crashes as though it had none.
