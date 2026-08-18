import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'platform_channel.dart';

/// An [ImageProvider] that reads from a downloaded asset pack.
///
/// ```dart
/// Image(image: FreightImage('maps/pin.png'))
/// ```
///
/// The pack must already be downloaded. This deliberately does not fetch one:
/// an image widget is the wrong place to start a transfer that can be hundreds
/// of megabytes, and it would happen during layout with nowhere to show
/// progress. Call [AssetPack.ensureDownloaded] first and build the image once
/// it completes.
///
/// Unlike [AssetImage] there is no resolution-aware variant selection. Packs
/// are addressed by exact logical path, so `2x` and `3x` variants have to be
/// chosen explicitly if a pack ships them.
@immutable
final class FreightImage extends ImageProvider<FreightImage> {
  /// Reads [path] from any downloaded pack, or from [pack] when given.
  const FreightImage(this.path, {this.pack, this.scale = 1.0});

  /// The logical path of the image inside the pack.
  final String path;

  /// The pack to read from, or null to search every downloaded pack.
  final String? pack;

  /// The linear scale factor of the image, as with [AssetImage.scale].
  final double scale;

  @override
  Future<FreightImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FreightImage>(this);

  @override
  ImageStreamCompleter loadImage(
    FreightImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode),
      scale: key.scale,
      debugLabel: key.path,
      informationCollector:
          () => <DiagnosticsNode>[
            ErrorDescription('Path: ${key.path}'),
            ErrorDescription('Pack: ${key.pack ?? 'any downloaded pack'}'),
          ],
    );
  }

  Future<ui.Codec> _decode(
    FreightImage key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await FreightPlatform.instance.read(
      key.path,
      inPack: key.pack,
    );
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is FreightImage &&
      other.path == path &&
      other.pack == pack &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(path, pack, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'FreightImage')}'
      '("$path", pack: ${pack ?? 'any'}, scale: $scale)';
}
