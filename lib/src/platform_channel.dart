import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'pack_status.dart';

/// Wire format shared with the Swift and Kotlin implementations.
///
/// Kept internal: the platform sides speak these strings, nothing else should.
abstract final class _Wire {
  static const methods = MethodChannel('dev.treamz.freight/methods');
  static const events = EventChannel('dev.treamz.freight/status');

  // Status update kinds emitted on [events].
  static const began = 'began';
  static const downloading = 'downloading';
  static const paused = 'paused';
  static const finished = 'finished';
  static const failed = 'failed';
  // Any other kind, including 'idle', is interpreted from the state flags.
}

/// The bridge to the native asset-pack managers.
///
/// One instance per isolate; the platform channels are inherently singletons.
final class FreightPlatform {
  FreightPlatform._();

  static final FreightPlatform instance = FreightPlatform._();

  Stream<PackStatus>? _allPacksStream;
  final Map<String, Stream<PackStatus>> _packStreams = {};

  Future<List<PackInfo>> allPacks() async {
    final raw = await _invoke<List<Object?>>('allPacks', null);
    return raw!
        .cast<Map<Object?, Object?>>()
        .map(PackInfo._fromMap)
        .toList(growable: false);
  }

  Future<PackInfo?> packInfo(String packId) async {
    final raw = await _invoke<Map<Object?, Object?>>('packInfo', {
      'packId': packId,
    });
    return raw == null ? null : PackInfo._fromMap(raw);
  }

  Future<PackStatus> status(String packId) async {
    final raw = await _invoke<Map<Object?, Object?>>('status', {
      'packId': packId,
    });
    return _statusFromMap(raw!);
  }

  Future<bool> isDownloaded(String packId) async {
    final raw = await _invoke<bool>('isDownloaded', {'packId': packId});
    return raw ?? false;
  }

  Future<void> ensureDownloaded(String packId, {bool requireLatest = false}) {
    return _invoke<void>('ensureDownloaded', {
      'packId': packId,
      'requireLatest': requireLatest,
    });
  }

  Future<void> remove(String packId) {
    return _invoke<void>('remove', {'packId': packId});
  }

  Future<UpdateCheck> checkForUpdates() async {
    final raw = await _invoke<Map<Object?, Object?>>('checkForUpdates', null);
    return UpdateCheck(
      updating: (raw!['updating']! as List<Object?>).cast<String>().toSet(),
      removed: (raw['removed']! as List<Object?>).cast<String>().toSet(),
    );
  }

  Future<Uint8List> read(String path, {String? inPack}) async {
    final raw = await _invoke<Uint8List>('read', {
      'path': path,
      'packId': inPack,
    });
    return raw!;
  }

  Future<String> resolve(String path, {String? inPack}) async {
    final raw = await _invoke<String>('resolve', {
      'path': path,
      'packId': inPack,
    });
    return raw!;
  }

  /// Status for every pack. Broadcast, shared across listeners.
  Stream<PackStatus> watchAll() {
    return _allPacksStream ??=
        _Wire.events
            .receiveBroadcastStream(const <String, Object?>{})
            .map((event) => _statusFromMap(event as Map<Object?, Object?>))
            .asBroadcastStream();
  }

  /// Status for one pack.
  ///
  /// Filtered natively rather than in Dart so an app watching a single pack
  /// does not pay for updates about every other one.
  Stream<PackStatus> watch(String packId) {
    return _packStreams[packId] ??=
        _Wire.events
            .receiveBroadcastStream({'packId': packId})
            .map((event) => _statusFromMap(event as Map<Object?, Object?>))
            .asBroadcastStream();
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?>? arguments) async {
    try {
      return await _Wire.methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw _translate(e, arguments);
    } on MissingPluginException {
      throw const UnsupportedPlatformException(
        'freight has no implementation on this platform. '
        'iOS 26.0 or newer is required; Android support arrives in 0.3.',
      );
    }
  }

  FreightException _translate(
    PlatformException e,
    Map<String, Object?>? arguments,
  ) {
    final packId = arguments?['packId'] as String?;
    final path = arguments?['path'] as String?;
    return switch (e.code) {
      'pack_not_found' => PackNotFoundException(packId ?? '<unknown>'),
      'path_not_found' => PathNotFoundException(
        path ?? '<unknown>',
        packId: packId,
      ),
      'download_failed' => DownloadFailedException(
        packId ?? '<unknown>',
        e.message ?? 'unknown reason',
      ),
      'missing_app_group' => MissingAppGroupException(
        e.message ?? 'Info.plist has no BAAppGroupID',
      ),
      'missing_extension' => MissingExtensionException(
        e.message ?? 'No Background Assets downloader extension is embedded',
      ),
      'unsupported_os' => UnsupportedPlatformException(
        e.message ?? 'Managed Background Assets requires iOS 26.0 or newer',
      ),
      _ => DownloadFailedException(packId ?? '<unknown>', e.message ?? e.code),
    };
  }

  PackStatus _statusFromMap(Map<Object?, Object?> map) {
    final packId = map['packId']! as String;
    final flags = PackFlags((map['flags'] as int?) ?? 0);

    return switch (map['kind'] as String?) {
      _Wire.downloading || _Wire.began => PackDownloading(
        packId: packId,
        flags: flags,
        completedBytes: (map['completedBytes'] as int?) ?? 0,
        totalBytes: (map['totalBytes'] as int?) ?? 0,
      ),
      _Wire.paused => PackPaused(packId: packId, flags: flags),
      _Wire.finished => PackReady(
        packId: packId,
        flags: flags,
        version: (map['version'] as int?) ?? 0,
        sizeBytes: (map['sizeBytes'] as int?) ?? 0,
      ),
      _Wire.failed => PackFailed(
        packId: packId,
        flags: flags,
        error: DownloadFailedException(
          packId,
          (map['error'] as String?) ?? 'unknown reason',
        ),
      ),
      _ =>
        flags.downloaded
            ? PackReady(
              packId: packId,
              flags: flags,
              version: (map['version'] as int?) ?? 0,
              sizeBytes: (map['sizeBytes'] as int?) ?? 0,
            )
            : PackNotDownloaded(packId: packId, flags: flags),
    };
  }
}

/// Static description of a pack, as the system currently knows it.
final class PackInfo {
  const PackInfo({
    required this.id,
    required this.downloadSize,
    required this.version,
    required this.flags,
  });

  factory PackInfo._fromMap(Map<Object?, Object?> map) => PackInfo(
    id: map['id']! as String,
    downloadSize: (map['downloadSize'] as int?) ?? 0,
    version: (map['version'] as int?) ?? 0,
    flags: PackFlags((map['flags'] as int?) ?? 0),
  );

  final String id;

  /// Bytes that would be transferred to download this pack.
  final int downloadSize;

  final int version;
  final PackFlags flags;
}

/// Result of asking the server what changed.
final class UpdateCheck {
  const UpdateCheck({required this.updating, required this.removed});

  /// Packs that started updating as a result of the check.
  final Set<String> updating;

  /// Packs the server no longer offers.
  final Set<String> removed;

  bool get isEmpty => updating.isEmpty && removed.isEmpty;
}
