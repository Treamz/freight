# Changelog

## Unreleased

* Added the `freight setup` command, which adds the Background Assets downloader
  extension target to a Flutter iOS project: the extension's source, its
  `Info.plist` and entitlements, the app group on both targets, `BAAppGroupID`,
  and the `project.pbxproj` edits that add the target and embed it in a build
  phase early enough not to produce a dependency cycle. It is idempotent, and it
  refuses projects that do not match the layout `flutter create` produces rather
  than guessing.

* Split out of `freight`, so an app depending on the plugin no longer carries
  `args`, `glob`, `path` and `yaml` for tooling it never runs. Nothing in this
  package imports `freight`; the two share the `freight.yaml` format, not code.
