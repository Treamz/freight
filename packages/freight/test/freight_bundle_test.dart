import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freight/freight.dart';

/// Stands in for the app's own assets.
class _FakeFallback extends CachingAssetBundle {
  _FakeFallback(this._contents);

  final Map<String, String> _contents;
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    final value = _contents[key];
    if (value == null) throw Exception('fallback has no asset "$key"');
    return ByteData.sublistView(utf8.encode(value));
  }
}

void main() {
  Uint8List bytes(String value) => utf8.encode(value);

  group('FreightBundle', () {
    test('reads a file from a downloaded pack', () async {
      final bundle = FreightBundle(
        reader: (path, {inPack}) async => bytes('tiles for $path'),
      );

      expect(
        await bundle.loadString('maps/berlin.tiles'),
        'tiles for maps/berlin.tiles',
      );
    });

    test('scopes lookups to one pack when asked', () async {
      String? seen;
      final bundle = FreightBundle(
        pack: 'maps_europe',
        reader: (path, {inPack}) async {
          seen = inPack;
          return bytes('ok');
        },
      );

      await bundle.loadString('index.txt');
      expect(seen, 'maps_europe');
    });

    test('searches every pack when none is named', () async {
      String? seen = 'untouched';
      final bundle = FreightBundle(
        reader: (path, {inPack}) async {
          seen = inPack;
          return bytes('ok');
        },
      );

      await bundle.loadString('index.txt');
      expect(seen, isNull);
    });

    test('falls through to the app assets when no pack has the key', () async {
      final fallback = _FakeFallback({'icons/pin.png': 'bundled bytes'});
      final bundle = FreightBundle(
        fallback: fallback,
        reader: (path, {inPack}) async => throw PathNotFoundException(path),
      );

      expect(await bundle.loadString('icons/pin.png'), 'bundled bytes');
      expect(fallback.requested, ['icons/pin.png']);
    });

    test('falls through when the pack itself is unknown', () async {
      // A pack that has not reached the device yet should degrade to whatever
      // shipped in the bundle rather than failing outright.
      final fallback = _FakeFallback({'icons/pin.png': 'bundled bytes'});
      final bundle = FreightBundle(
        pack: 'not_published_yet',
        fallback: fallback,
        reader: (path, {inPack}) async => throw PackNotFoundException(inPack!),
      );

      expect(await bundle.loadString('icons/pin.png'), 'bundled bytes');
    });

    test('propagates configuration errors instead of falling through', () async {
      // Serving bundled assets here would make an unconfigured app look like a
      // working one, and no pack would ever load.
      final fallback = _FakeFallback({'icons/pin.png': 'bundled bytes'});
      final bundle = FreightBundle(
        fallback: fallback,
        reader:
            (path, {inPack}) async =>
                throw const MissingExtensionException('no extension embedded'),
      );

      await expectLater(
        bundle.loadString('icons/pin.png'),
        throwsA(isA<MissingExtensionException>()),
      );
      expect(fallback.requested, isEmpty);
    });

    test('packsOnly reports the miss rather than hiding it', () async {
      final bundle = FreightBundle.packsOnly(
        reader: (path, {inPack}) async => throw PathNotFoundException(path),
      );

      await expectLater(
        bundle.loadString('icons/pin.png'),
        throwsA(isA<PathNotFoundException>()),
      );
    });

    test('caches strings, so a repeated key costs one read', () async {
      var reads = 0;
      final bundle = FreightBundle(
        reader: (path, {inPack}) async {
          reads++;
          return bytes('welcome');
        },
      );

      await bundle.loadString('welcome.txt');
      await bundle.loadString('welcome.txt');
      expect(reads, 1);

      bundle.evict('welcome.txt');
      await bundle.loadString('welcome.txt');
      expect(reads, 2);
    });
  });

  group('FreightImage', () {
    test('is its own key, resolved synchronously', () async {
      const image = FreightImage('maps/pin.png');
      final key = await image.obtainKey(ImageConfiguration.empty);
      expect(key, same(image));
    });

    test('keys on path, pack and scale together', () {
      const base = FreightImage('maps/pin.png', pack: 'maps', scale: 2);

      expect(base, const FreightImage('maps/pin.png', pack: 'maps', scale: 2));
      expect(
        base.hashCode,
        const FreightImage('maps/pin.png', pack: 'maps', scale: 2).hashCode,
      );

      // The same path in a different pack is a different image; collapsing
      // these would serve one pack's bytes for another's key.
      expect(
        base,
        isNot(const FreightImage('maps/pin.png', pack: 'tutorial', scale: 2)),
      );
      expect(
        base,
        isNot(const FreightImage('maps/other.png', pack: 'maps', scale: 2)),
      );
      expect(base, isNot(const FreightImage('maps/pin.png', pack: 'maps')));
    });
  });
}
