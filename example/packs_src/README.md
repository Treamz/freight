# Example asset pack sources

Each directory here is one asset pack's root. Logical paths inside a pack are
relative to that root, so `tutorial/nested/deep.txt` is read back as
`nested/deep.txt`.

The fixtures are small on purpose — enough to prove packaging and path handling
without carrying binary data in git. To watch a download take real time, inflate
one before packaging:

```bash
dd if=/dev/urandom of=maps_europe/berlin.tiles bs=1m count=200
```

Building the packs, until the `freight` CLI does it (see PLAN.md, 0.2):

```bash
cd tutorial && xcrun ba-package package /path/to/manifest.json -o ../../build/packs/tutorial.aar
```

Apple's `xcrun ba-serve` serves them for development; note that Background
Assets does not work on the Simulator.
