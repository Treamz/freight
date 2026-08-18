import 'dart:typed_data';

import 'asset_pack.dart';
import 'pack_status.dart';
import 'platform_channel.dart';

/// Entry point for asset packs delivered outside the app bundle.
///
/// Asset packs are a virtual filesystem rather than a set of folders: a file is
/// addressed by the logical path it had when the pack was built, and the system
/// resolves that path across every downloaded pack. This is why reads take
/// paths, and why there is no API returning "the pack's directory" — the
/// platform does not have one.
///
/// ```dart
/// final maps = Freight.pack('maps_europe');
/// await maps.ensureDownloaded();
/// final tiles = await Freight.read('maps/berlin.mbtiles');
/// ```
abstract final class Freight {
  /// A handle to the pack with this id.
  ///
  /// Does not verify that the pack exists — call [AssetPack.info] for that.
  static AssetPack pack(String id) => AssetPack(id);

  /// Every pack the system knows about, downloaded or not.
  ///
  /// On iOS this reflects the download manifest the device last fetched, so a
  /// newly published pack may be absent until [checkForUpdates] runs.
  static Future<List<PackInfo>> allPacks() =>
      FreightPlatform.instance.allPacks();

  /// Reads a file from any downloaded pack.
  ///
  /// Pass [inPack] to scope the lookup when the same path exists in more than
  /// one pack. Throws [PathNotFoundException] when nothing matches.
  static Future<Uint8List> read(String path, {String? inPack}) =>
      FreightPlatform.instance.read(path, inPack: inPack);

  /// Resolves a logical path to a file on disk.
  ///
  /// Prefer [read]; reach for this only when something outside Dart needs a
  /// real path, such as a video player or a native database.
  static Future<String> resolve(String path, {String? inPack}) =>
      FreightPlatform.instance.resolve(path, inPack: inPack);

  /// Follows state changes for every pack.
  ///
  /// The system downloads and removes packs on its own schedule, so updates
  /// arrive without this app asking. Use [AssetPack.watch] to follow just one.
  static Stream<PackStatus> watchAll() => FreightPlatform.instance.watchAll();

  /// Asks the server what changed, starting any updates it finds.
  ///
  /// Returns which packs began updating and which are no longer offered.
  /// Rarely needed — the system checks periodically on its own — but useful
  /// after publishing new packs and wanting them without waiting.
  static Future<UpdateCheck> checkForUpdates() =>
      FreightPlatform.instance.checkForUpdates();
}
