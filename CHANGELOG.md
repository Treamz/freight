# Changelog

## Unreleased

* Fixed detection of the Background Assets downloader extension, which looked
  only in the app's `PlugIns/` directory. ExtensionKit embeds extensions in
  `Extensions/` instead, so a correctly configured app was still told it had no
  extension. Both locations are now searched.
* Added `doc/ios-setup.md`, a walkthrough of the iOS project configuration
  Managed Background Assets requires: adding the downloader extension with
  Xcode's Background Download Extension template, wiring the app group, building
  packs with `ba-package`, self-hosting, and a table mapping each failure message
  to its actual cause. Several of those messages point at the wrong problem —
  a missing `CFBundleIdentifier` in the extension reports a bundle identifier
  prefix mismatch, for instance.
* Documented the iOS setup Managed Background Assets requires — the app group,
  `BAAppGroupID`, and the downloader extension target — along with the fact that
  the system crashes rather than returning an error when either is missing.
  `freight` checks both before touching the platform and throws
  `MissingAppGroupException` or `MissingExtensionException`.
