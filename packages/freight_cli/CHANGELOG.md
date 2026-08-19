# Changelog

## Unreleased

* Split out of `freight`, so an app depending on the plugin no longer carries
  `args`, `glob`, `path` and `yaml` for tooling it never runs. Nothing in this
  package imports `freight`; the two share the `freight.yaml` format, not code.
