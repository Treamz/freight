# freight

Ship large assets outside your app bundle — iOS Managed Background Assets and
Google Play Asset Delivery behind one Dart API.

> **Status: early development.** Neither package is published yet. See
> [PLAN.md](PLAN.md) for the design and release plan.
>
> iOS works end to end on hardware — declared, packaged, downloaded and read
> back. Android is built and produces correct app bundles, but has not run
> against Play services.

| Package | What it is |
|---|---|
| [`freight`](packages/freight) | The Flutter plugin. Depends on nothing but Flutter. |
| [`freight_cli`](packages/freight_cli) | Build-time tooling: packaging and setup checks. Pure Dart. |

They are separate so an app carrying the plugin does not also carry a YAML
parser, a glob matcher and an argument parser it never runs. `freight_cli` does
not import `freight` — the two share the `freight.yaml` format, not code.

[Setting up an iOS project](packages/freight/doc/ios-setup.md) walks through
what Managed Background Assets needs from the host app.

## Releasing

Both packages carry their own versions and tags. See
[RELEASING.md](RELEASING.md); the short version is that a workflow names the
version and CHANGELOG entries live under `## Unreleased` until it does.

## License

MIT
