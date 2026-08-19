import 'exceptions.dart';

/// Raw state bits for an asset pack.
///
/// iOS models pack state as an `OptionSet`, so states combine: a pack can be
/// [downloaded] and [outOfDate] at the same time. [PackStatus] flattens this
/// into something switchable; these flags stay available for the cases where
/// the distinction matters.
extension type const PackFlags(int bits) {
  static const int _downloadAvailable = 1 << 0;
  static const int _updateAvailable = 1 << 1;
  static const int _upToDate = 1 << 2;
  static const int _outOfDate = 1 << 3;
  static const int _obsolete = 1 << 4;
  static const int _downloading = 1 << 5;
  static const int _downloaded = 1 << 6;

  /// The pack can be downloaded but is not present.
  bool get downloadAvailable => bits & _downloadAvailable != 0;

  /// A newer version exists on the server.
  bool get updateAvailable => bits & _updateAvailable != 0;

  /// The local copy matches the server.
  bool get upToDate => bits & _upToDate != 0;

  /// The local copy is present but superseded.
  bool get outOfDate => bits & _outOfDate != 0;

  /// The pack is no longer offered and should be removed.
  bool get obsolete => bits & _obsolete != 0;

  /// A download is in flight.
  bool get downloading => bits & _downloading != 0;

  /// The pack is present on disk.
  bool get downloaded => bits & _downloaded != 0;
}

/// The state of a single asset pack.
///
/// Use with pattern matching:
///
/// ```dart
/// switch (status) {
///   case PackReady(:final version) => print('v$version ready'),
///   case PackDownloading(:final fraction) => print('${fraction * 100}%'),
///   case _ => null,
/// }
/// ```
sealed class PackStatus {
  const PackStatus({required this.packId, required this.flags});

  final String packId;

  /// The underlying state bits, for cases this sealed hierarchy flattens away.
  final PackFlags flags;
}

/// The pack is not on the device and nothing is in flight.
final class PackNotDownloaded extends PackStatus {
  const PackNotDownloaded({required super.packId, required super.flags});
}

/// A download is in progress.
final class PackDownloading extends PackStatus {
  const PackDownloading({
    required super.packId,
    required super.flags,
    required this.completedBytes,
    required this.totalBytes,
  });

  final int completedBytes;
  final int totalBytes;

  /// Progress in `0.0..1.0`, or `null` when the total size is not yet known.
  double? get fraction =>
      totalBytes > 0 ? (completedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

/// The download was suspended — by the system, or because conditions changed.
///
/// It resumes on its own; this is not a failure.
final class PackPaused extends PackStatus {
  const PackPaused({required super.packId, required super.flags});
}

/// The pack is on the device and its files can be read.
final class PackReady extends PackStatus {
  const PackReady({
    required super.packId,
    required super.flags,
    required this.version,
    required this.sizeBytes,
  });

  final int version;
  final int sizeBytes;

  /// Whether a newer version is available on the server.
  ///
  /// The current files stay readable; call
  /// [AssetPack.ensureDownloaded] with `requireLatest: true` to update.
  bool get hasUpdate => flags.updateAvailable || flags.outOfDate;
}

/// The download failed. The pack may be retried.
final class PackFailed extends PackStatus {
  const PackFailed({
    required super.packId,
    required super.flags,
    required this.error,
  });

  final FreightException error;
}
