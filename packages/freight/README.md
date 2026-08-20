# freight

Ship large assets outside your app bundle — iOS Managed Background Assets and
Google Play Asset Delivery behind one Dart API.

> **Status: early development.** Published, but the API is not stable — expect
> it to move before 1.0. See
> [PLAN.md](https://github.com/Treamz/freight/blob/main/PLAN.md) for the design
> and release plan.

> **iOS 26+ only.** `freight` targets Managed Background Assets, introduced in
> iOS 26. Apps supporting iOS 25 and earlier need the legacy
> `BADownloaderExtension` path, which this package deliberately does not
> implement.
>
> **iOS is proven end to end**, on an iPhone: a pack declared in `freight.yaml`,
> packaged with `ba-package`, downloaded by the device, read back through
> `Freight.read`, and drawn from the pack with `FreightImage`.
>
> **Android is not.** The runtime reads and downloads Play Asset Delivery packs
> through the same API, and `freight_cli` generates the Gradle asset pack
> modules — an app bundle built from the example carries both packs with the
> right paths and delivery types — but none of it has run against Play services.

## The problem

Games, offline maps and on-device ML models do not fit in an app bundle. Both
stores solve this and neither is reachable from Flutter: iOS 26 replaced the old
downloader-extension dance with declarative asset packs, and Android has had Play
Asset Delivery for years. As of iOS 26 the two work the same way — declare a pack,
let the store host it, request it at runtime — which is what makes one API
possible.

## Install

```yaml
dependencies:
  freight: ^0.1.0

dev_dependencies:
  freight_cli: ^0.1.0
```

`freight_cli` builds the packs and sets the project up; it is a dev dependency
so that nothing an app ships carries a YAML parser it never runs.

## Usage

Declare packs once:

```yaml
# freight.yaml
packs:
  tutorial:
    delivery: essential      # downloaded during install
    root: assets/tutorial    # logical paths are relative to this
    files: ["**"]
  maps_europe:
    delivery: onDemand       # downloaded when you ask
    root: assets/maps/europe
    files: ["**"]
```

`root` decides what the app reads back: a file at `<root>/berlin.tiles` is read
as `berlin.tiles`, wherever the sources sit in your repository.

Build them with [`freight_cli`](https://pub.dev/packages/freight_cli), a separate dev dependency so
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

Set the platform projects up once, and check them:

```bash
dart run freight_cli:freight setup
dart run freight_cli:freight doctor
```

`setup` adds the Background Assets downloader extension on iOS and a Gradle
asset pack module per pack on Android. `doctor` then looks for the mistakes both
stores otherwise report late — iOS by crashing on a device, Android by failing a
bundle build.

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

**[The setup guide](https://github.com/Treamz/freight/blob/main/packages/freight/doc/ios-setup.md) walks through all of it**, including
building packs with `ba-package`, self-hosting, and what each failure message
actually means.

Note that Background Assets does not work on the iOS Simulator — it needs a real
signing identity. Test asset packs on a device.

## Android setup

`freight setup` generates a Gradle asset pack module per pack, declares the
`com.android.asset-pack` plugin, includes each module in `settings.gradle.kts`
and lists them on the app. `freight build` then stages each pack's files into
its module, which is the only place Play reads them from.

Asset packs only exist in an app bundle, so `flutter build appbundle` is what
carries them — an APK has none.

Two differences from iOS are worth knowing rather than discovering:

* `Freight.allPacks` lists only packs already on the device. Play has no API for
  the ones an app merely declares.
* `requireLatest` does nothing. Play versions asset packs with the app, so there
  is never a newer one for the installed build.

## Requirements

* Flutter 3.29+, Dart 3.7+
* iOS 26.0+ (26.4+ recommended; the 26.0 APIs are already deprecated by Apple)
* For building iOS packs: Xcode 26, or the Managed Background Assets developer
  tools for Linux. The Android half needs neither.

## License

MIT
