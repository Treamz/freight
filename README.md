# freight

Ship large assets outside your app bundle — iOS Managed Background Assets and
Google Play Asset Delivery behind one Dart API.

> **Status: early development.** The API is not stable and the package is not yet
> published. See [PLAN.md](PLAN.md) for the design and release plan.

> **iOS 26+ only.** `freight` targets Managed Background Assets, introduced in
> iOS 26. Apps supporting iOS 25 and earlier need the legacy
> `BADownloaderExtension` path, which this package deliberately does not
> implement. Android support lands in 0.3.

## The problem

Games, offline maps and on-device ML models do not fit in an app bundle. Both
stores solve this and neither is reachable from Flutter: iOS 26 replaced the old
downloader-extension dance with declarative asset packs, and Android has had Play
Asset Delivery for years. As of iOS 26 the two work the same way — declare a pack,
let the store host it, request it at runtime — which is what makes one API
possible.

## Usage

Declare packs once:

```yaml
# freight.yaml
packs:
  tutorial:
    delivery: essential      # downloaded during install
    files: [assets/tutorial/**]
  maps_europe:
    delivery: onDemand       # downloaded when you ask
    files: [assets/maps/europe/**]
```

Then, at runtime:

```dart
final pack = Freight.pack('maps_europe');

await pack.ensureDownloaded();

pack.watch().listen((status) {
  if (status case PackDownloading(:final fraction)) {
    print('${(fraction * 100).round()}%');
  }
});
```

Asset packs are a virtual filesystem, not a folder — you address logical paths:

```dart
final bytes = await Freight.read('maps/berlin.mbtiles');
final file  = await Freight.resolve('maps/berlin.mbtiles');
```

Which means downloaded assets can behave like ordinary Flutter assets:

```dart
Image(image: FreightImage('maps/pin.png'))
```

## Delivery policies

| `delivery`  | iOS          | Android      | Behaviour                                             |
|-------------|--------------|--------------|-------------------------------------------------------|
| `essential` | essential    | install-time | Downloaded during install; app cannot open until done |
| `prefetch`  | prefetch     | fast-follow  | Starts during install, may finish afterwards          |
| `onDemand`  | onDemand     | on-demand    | Never automatic — the app requests it                 |

## iOS setup

Managed Background Assets has two preconditions, and the system *crashes* rather
than returning an error when either is missing. `freight` checks both first and
throws `MissingAppGroupException` or `MissingExtensionException` instead, but the
app still has to satisfy them:

1. **App group.** Add the App Groups capability and set `BAAppGroupID` in
   `Info.plist` to the group id:

   ```xml
   <key>BAAppGroupID</key>
   <string>group.com.example.app</string>
   ```

2. **A downloader extension target.** Its entire source is four lines — every
   protocol requirement has a default implementation:

   ```swift
   import BackgroundAssets
   import ExtensionFoundation

   @main
   struct FreightDownloaderExtension: ManagedDownloaderExtension {}
   ```

   The target must set
   `EXExtensionPointIdentifier` to `com.apple.background-assets.content-request`
   and be embedded in the app.

From 0.2 the `freight` CLI does both for you. `example/ios` shows the shape of a
correctly configured project in the meantime.

Note that Background Assets does not work on the iOS Simulator — it requires a
real signing identity, and Apple's local mock server (`xcrun ba-serve`) cannot
redirect a simulator. Test asset packs on a device.

## Requirements

* Flutter 3.29+, Dart 3.7+
* iOS 26.0+ (26.4+ recommended; the 26.0 APIs are already deprecated by Apple)
* Xcode 26 or the Managed Background Assets developer tools for Linux, for
  building packs

## License

MIT
