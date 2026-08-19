# Changelog

## Unreleased

* `freight setup` now writes `BAHasManagedAssetPacks` and `BAUsesAppleHosting`
  alongside `BAAppGroupID`, and generates the extension with the correct
  extension point identifier. Managed Background Assets enforces all of these by
  trapping rather than returning an error, so a project missing one crashed with
  a message that named neither the key nor the caller.
* `freight doctor` checks the two new keys, failing on a missing
  `BAHasManagedAssetPacks` and warning when `BAUsesAppleHosting` is absent —
  self-hosting is legitimate, but it brings further requirements the framework
  also enforces by trapping.

* Corrected the glob patterns in the documentation and the example. `**/*.tiles`
  matches only files inside a subdirectory, so a pack written that way silently
  dropped everything sitting directly in its root — use `**.tiles`. The
  distinction is now documented with the other glob rules and pinned by a test.
* Added an example, and `freight doctor` no longer asks for `ba-package` in a
  project with no `ios/` directory.

* `freight doctor` now checks the Android side too: that the asset pack plugin
  is declared, that each module exists, is included in `settings.gradle.kts` and
  listed on the app, and that its delivery type still matches `freight.yaml` —
  changing `delivery` does nothing until `freight setup` runs again, and the
  bundle builds happily with the stale policy. It also stops asking for
  `ba-package` in a project with no `ios/` directory, which made it unusable on
  Linux.
* `doctor` and `build` warn about packs over Play's limits: 512 MB for a
  fast-follow or on-demand pack, and 1 GB across all install-time packs.

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
