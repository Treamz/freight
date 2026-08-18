import 'dart:typed_data';

import 'pack_status.dart';
import 'platform_channel.dart';

/// A handle to one asset pack.
///
/// Obtained from [Freight.pack]. Creating a handle costs nothing and does not
/// touch the system — it is a typed name, not a resource.
final class AssetPack {
  const AssetPack(this.id);

  /// The pack id, matching `assetPackID` in the generated manifest.
  final String id;

  /// Whether every file in this pack is on the device right now.
  Future<bool> get isDownloaded =>
      FreightPlatform.instance.isDownloaded(id);

  /// The pack's current state.
  ///
  /// A point-in-time read; use [watch] to follow it.
  Future<PackStatus> status() => FreightPlatform.instance.status(id);

  /// Size, version and state as the system currently knows them.
  ///
  /// Returns `null` when the system has never heard of this pack — most often
  /// a typo in the id, or a download manifest that has not reached the device.
  Future<PackInfo?> info() => FreightPlatform.instance.packInfo(id);

  /// Follows this pack's state until the subscription is cancelled.
  ///
  /// The system downloads packs on its own schedule, so updates arrive whether
  /// or not this app asked for them. Broadcast: listening twice is cheap.
  Stream<PackStatus> watch() => FreightPlatform.instance.watch(id);

  /// Downloads the pack if it is not already present, and completes when its
  /// files are readable.
  ///
  /// Completes immediately when the pack is already available. Progress is
  /// reported through [watch], not here, because the system may also be
  /// downloading this pack for reasons unrelated to this call.
  ///
  /// Set [requireLatest] to also update a pack that is present but superseded.
  ///
  /// Throws [PackNotFoundException] for an unknown id, or
  /// [DownloadFailedException] when the transfer fails.
  Future<void> ensureDownloaded({bool requireLatest = false}) =>
      FreightPlatform.instance
          .ensureDownloaded(id, requireLatest: requireLatest);

  /// Deletes the local copy, freeing its disk space.
  ///
  /// The pack can be downloaded again afterwards. The system may also remove
  /// packs on its own when storage runs low, which is why code should never
  /// assume a previously downloaded pack is still present.
  Future<void> remove() => FreightPlatform.instance.remove(id);

  /// Reads a file from this pack.
  ///
  /// [path] is the logical path the file had when the pack was built, relative
  /// to the packaging root — not an absolute location on disk.
  Future<Uint8List> read(String path) =>
      FreightPlatform.instance.read(path, inPack: id);

  /// Resolves a logical path in this pack to a file on disk.
  ///
  /// Prefer [read] unless something outside Dart needs a real path — a video
  /// player, or a native database that opens files itself.
  Future<String> resolve(String path) =>
      FreightPlatform.instance.resolve(path, inPack: id);

  @override
  String toString() => 'AssetPack($id)';

  @override
  bool operator ==(Object other) => other is AssetPack && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
