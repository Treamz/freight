# Changelog

## Unreleased

* `freight setup` now generates the Gradle asset pack modules for Android as
  well, and `freight build` gained `--platform`, staging each pack's files into
  its module under the same logical paths the iOS archive records. Pack ids are
  validated against Play's rule for module names — letters, numbers and
  underscores, starting with a letter — because one id has to be valid on both
  platforms.

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
