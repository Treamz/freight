/// Base class for every error `freight` reports.
sealed class FreightException implements Exception {
  const FreightException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No asset pack with the requested id is known to the system.
///
/// On iOS this means the id is absent from the download manifest the device
/// fetched; it does not necessarily mean the pack was never declared.
final class PackNotFoundException extends FreightException {
  const PackNotFoundException(this.packId)
      : super('No asset pack with id "$packId"');

  final String packId;
}

/// A logical path could not be resolved in any downloaded pack.
final class PathNotFoundException extends FreightException {
  const PathNotFoundException(this.path, {this.packId})
      : super(packId == null
            ? 'No file at "$path" in any downloaded asset pack'
            : 'No file at "$path" in asset pack "$packId"');

  final String path;

  /// Set when the lookup was scoped to a single pack.
  final String? packId;
}

/// The download failed — no network, server error, or out of disk space.
final class DownloadFailedException extends FreightException {
  const DownloadFailedException(this.packId, String reason)
      : super('Download of "$packId" failed: $reason');

  final String packId;
}

/// The host app has no `BAAppGroupID` in its Info.plist.
///
/// Managed Background Assets keeps packs in an app group container. Without the
/// key the system traps rather than returning an error, so `freight` checks for
/// it before touching the platform and reports this instead.
final class MissingAppGroupException extends FreightException {
  const MissingAppGroupException(super.message);
}

/// The host app embeds no Background Assets downloader extension.
///
/// Managed Background Assets removes the need to *write* one, but the extension
/// target must still exist and ship inside the app. As with
/// [MissingAppGroupException], the system traps rather than returning an error,
/// so `freight` checks first.
final class MissingExtensionException extends FreightException {
  const MissingExtensionException(super.message);
}

/// The running OS is too old for Managed Background Assets.
final class UnsupportedPlatformException extends FreightException {
  const UnsupportedPlatformException(super.message);
}
