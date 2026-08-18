# Changelog

## Unreleased

* Fixed detection of the Background Assets downloader extension, which looked
  only in the app's `PlugIns/` directory. ExtensionKit embeds extensions in
  `Extensions/` instead, so a correctly configured app was still told it had no
  extension. Both locations are now searched.
* Documented the iOS setup Managed Background Assets requires — the app group,
  `BAAppGroupID`, and the downloader extension target — along with the fact that
  the system crashes rather than returning an error when either is missing.
  `freight` checks both before touching the platform and throws
  `MissingAppGroupException` or `MissingExtensionException`.
