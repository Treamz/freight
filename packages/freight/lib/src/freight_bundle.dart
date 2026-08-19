import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'platform_channel.dart';

/// Reads a file from a downloaded asset pack. Injectable so [FreightBundle] can
/// be tested without a live `AssetPackManager`.
@visibleForTesting
typedef PackFileReader =
    Future<Uint8List> Function(String path, {String? inPack});

/// An [AssetBundle] backed by downloaded asset packs.
///
/// Asset packs address files by the logical path they had when the pack was
/// built, which is exactly what an asset key is — so a downloaded pack can be
/// read through the same API as a bundled asset, and widgets that take a key
/// need not know where the bytes came from:
///
/// ```dart
/// DefaultAssetBundle(
///   bundle: Freight.bundle(),
///   child: const MapScreen(),
/// )
/// ```
///
/// Keys that no downloaded pack contains fall through to [fallback], which
/// defaults to [rootBundle], so one bundle serves both bundled and downloaded
/// assets. Every such miss costs a platform round trip before the fallback is
/// tried, so prefer scoping this to the subtree that needs packs rather than
/// installing it at the root of a large app.
///
/// Only a genuine miss falls through. If Managed Background Assets is not
/// configured — no app group, no downloader extension — that error propagates
/// instead, because silently serving bundled assets would make a broken setup
/// look like a working one.
///
/// One Android caveat: Play merges an install-time pack into the app, where it
/// loses its identity, so a bundle scoped with [pack] cannot read one. An
/// unscoped bundle finds those assets through the fallback.
final class FreightBundle extends CachingAssetBundle {
  /// A bundle that reads from downloaded packs and falls back to [fallback],
  /// or to [rootBundle] when none is given.
  ///
  /// Pass [pack] to restrict lookups to a single pack, which matters when the
  /// same logical path exists in more than one.
  FreightBundle({
    this.pack,
    AssetBundle? fallback,
    @visibleForTesting PackFileReader? reader,
  }) : _fallback = fallback ?? rootBundle,
       _read = reader ?? FreightPlatform.instance.read;

  /// A bundle that reads only from packs, with no fallback.
  ///
  /// A key that no downloaded pack contains throws rather than resolving to a
  /// bundled asset — useful when a silent fallback would hide that a pack was
  /// never downloaded.
  FreightBundle.packsOnly({
    this.pack,
    @visibleForTesting PackFileReader? reader,
  }) : _fallback = null,
       _read = reader ?? FreightPlatform.instance.read;

  /// The pack lookups are restricted to, or null to search every pack.
  final String? pack;

  final AssetBundle? _fallback;
  final PackFileReader _read;

  @override
  Future<ByteData> load(String key) async {
    try {
      final bytes = await _read(key, inPack: pack);
      return ByteData.sublistView(bytes);
    } on PathNotFoundException {
      final fallback = _fallback;
      if (fallback == null) rethrow;
      return fallback.load(key);
    } on PackNotFoundException {
      // Scoped to a pack the system has never heard of. Treated as a miss
      // rather than an error so a not-yet-published pack degrades to whatever
      // shipped in the bundle.
      final fallback = _fallback;
      if (fallback == null) rethrow;
      return fallback.load(key);
    }
  }

  @override
  String toString() =>
      '${objectRuntimeType(this, 'FreightBundle')}'
      '(${pack ?? 'all packs'}'
      '${_fallback == null ? ', no fallback' : ''})';
}
