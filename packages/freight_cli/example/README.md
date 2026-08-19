# freight_cli example

A `freight.yaml` describing two asset packs, with sources to build them from.

```
example/
├── freight.yaml
└── assets/
    ├── tutorial/          welcome.txt, steps.json
    └── maps/europe/       berlin.tiles, index.txt, draft_wip.tiles
```

## Check the setup

```bash
cd example
dart run freight_cli:freight doctor
```

Without an `ios/` or `android/` directory it reports the configuration and says
there is no platform project to check — which is the point of running it from a
real app instead.

## Build the packs

```bash
dart run freight_cli:freight build --platform ios
```

`tutorial` gets `welcome.txt` and `steps.json`. `maps_europe` gets
`berlin.tiles` and `index.txt` but not `draft_wip.tiles`, because `exclude`
removes it after the globs match.

Those are the paths the app reads back:

```dart
await Freight.pack('maps_europe').ensureDownloaded();
final tiles = await Freight.read('berlin.tiles');
```

Note what is *not* in them: nothing says `assets/maps/europe`. The declared
`root` is what keeps this directory layout out of the app's paths.

## Set a project up

Run from a Flutter app rather than here, since there is no `ios/` or `android/`
directory to modify:

```bash
dart run freight_cli:freight setup
```

On iOS that adds the Background Assets downloader extension target; on Android
it generates a Gradle asset pack module per pack.
