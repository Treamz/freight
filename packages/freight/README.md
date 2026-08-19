# freight

Ship large assets outside your app bundle — iOS Managed Background Assets and
Google Play Asset Delivery behind one Dart API.

> **Status: early development.** The API is not stable and the package is not yet
> published. See [PLAN.md](PLAN.md) for the design and release plan.

> **iOS 26+ only.** `freight` targets Managed Background Assets, introduced in
> iOS 26. Apps supporting iOS 25 and earlier need the legacy
> `BADownloaderExtension` path, which this package deliberately does not
> implement.
>
> **Android is not yet proven on a device.** The runtime reads and downloads
> Play Asset Delivery packs through the same API, and `freight_cli` generates
> the Gradle asset pack modules, but none of it has run against Play services.

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

Build them with [`freight_cli`](../freight_cli), a separate dev dependency so
this package carries no build-time tooling of its own:

```yaml
dev_dependencies:
  freight_cli: ^0.1.0
```

```bash
dart run freight_cli:freight build
```

That resolves each pack's globs, generates the manifests and packages them with
Apple's `ba-package`. Add `--base-url https://cdn.example.com/packs` to also
write the download manifest a self-hosting server needs.

Set up the iOS project once, and check it:

```bash
dart run freight_cli:freight setup
dart run freight_cli:freight doctor
```

Managed Background Assets reports most misconfiguration by crashing on a device
rather than returning an error, so `doctor` looks for those problems on your
machine instead — a missing app group, an app group only one target holds, no
downloader extension, a pack whose globs match nothing.

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

A pack's logical path is exactly what an asset key is, so downloaded assets can
behave like ordinary Flutter assets:

```dart
Image(image: FreightImage('maps/pin.png'))
```

Install `FreightBundle` and widgets that take an asset key work against packs
without knowing it. Keys no pack contains fall through to the app's own assets,
so one bundle serves both:

```dart
DefaultAssetBundle(
  bundle: Freight.bundle(),
  child: const MapScreen(),
)
```

## Delivery policies

| `delivery`  | iOS          | Android      | Behaviour                                             |
|-------------|--------------|--------------|-------------------------------------------------------|
| `essential` | essential    | install-time | Downloaded during install; app cannot open until done |
| `prefetch`  | prefetch     | fast-follow  | Starts during install, may finish afterwards          |
| `onDemand`  | onDemand     | on-demand    | Never automatic — the app requests it                 |

## iOS setup

Managed Background Assets needs an app group and an embedded downloader
extension, and the system *crashes* rather than returning an error when either
is missing. `freight` checks both first and throws `MissingAppGroupException` or
`MissingExtensionException` instead, but the app still has to provide them:

1. **File → New → Target → Background Download Extension** in Xcode, choosing
   one of the **Managed** options. The template writes the whole extension — four
   lines of Swift.
2. **Add the App Groups capability to the app target** with the same group, and
   set `BAAppGroupID` in the app's `Info.plist`.

**[doc/ios-setup.md](doc/ios-setup.md) walks through all of it**, including
building packs with `ba-package`, self-hosting, and what each failure message
actually means.

Note that Background Assets does not work on the iOS Simulator — it needs a real
signing identity. Test asset packs on a device.

## Requirements

* Flutter 3.29+, Dart 3.7+
* iOS 26.0+ (26.4+ recommended; the 26.0 APIs are already deprecated by Apple)
* Xcode 26 or the Managed Background Assets developer tools for Linux, for
  building packs

## License

MIT
