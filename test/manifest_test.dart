import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight/src/cli/manifest.dart';
import 'package:freight/src/cli/pack_config.dart';

void main() {
  PackConfig pack({
    String id = 'maps',
    DeliveryPolicy delivery = DeliveryPolicy.onDemand,
    Set<InstallationEvent> events = const {},
  }) => PackConfig(
    id: id,
    delivery: delivery,
    root: 'assets/maps',
    events: events,
  );

  Map<String, Object?> decode(String json) =>
      jsonDecode(json) as Map<String, Object?>;

  group('buildAssetPackManifest', () {
    test('gives an on-demand policy an empty object, as the tool requires', () {
      final manifest = decode(buildAssetPackManifest(pack(), ['a.txt']));

      expect(manifest['downloadPolicy'], {'onDemand': <String, Object?>{}});
    });

    test('lists installation events for an automatic policy', () {
      final manifest = decode(
        buildAssetPackManifest(
          pack(
            delivery: DeliveryPolicy.prefetch,
            events: {InstallationEvent.firstInstallation},
          ),
          ['a.txt'],
        ),
      );

      expect(manifest['downloadPolicy'], {
        'prefetch': {
          'installationEventTypes': ['firstInstallation'],
        },
      });
    });

    test('orders events by declaration, not by set iteration', () {
      // An unstable manifest would differ between runs over identical content
      // and defeat any "has this pack changed" check.
      Object? policyFor(Set<InstallationEvent> events) =>
          decode(
            buildAssetPackManifest(
              pack(delivery: DeliveryPolicy.essential, events: events),
              ['a.txt'],
            ),
          )['downloadPolicy'];

      const forwards = {
        InstallationEvent.firstInstallation,
        InstallationEvent.subsequentUpdate,
      };
      const backwards = {
        InstallationEvent.subsequentUpdate,
        InstallationEvent.firstInstallation,
      };

      expect(policyFor(forwards), policyFor(backwards));
      expect(policyFor(backwards), {
        'essential': {
          'installationEventTypes': ['firstInstallation', 'subsequentUpdate'],
        },
      });
    });

    test('emits explicit file selectors in the order given', () {
      // Explicit selectors, not a directory selector: ba-package records paths
      // relative to its working directory, so a directory selector would bake
      // the source layout into what the app reads back.
      final manifest = decode(
        buildAssetPackManifest(pack(), ['a.txt', 'nested/deep.txt']),
      );

      expect(manifest['fileSelectors'], [
        {'file': 'a.txt'},
        {'file': 'nested/deep.txt'},
      ]);
    });

    test('carries the pack id and platforms through', () {
      final manifest = decode(
        buildAssetPackManifest(pack(id: 'maps_europe'), ['a.txt']),
      );

      expect(manifest['assetPackID'], 'maps_europe');
      expect(manifest['platforms'], ['iOS']);
    });

    test('refuses to build an empty pack', () {
      // It would package and publish cleanly, then fail at runtime as a
      // missing asset — on a device, after a store round trip.
      expect(
        () => buildAssetPackManifest(pack(), const []),
        throwsA(
          isA<FreightConfigException>()
              .having((e) => e.pack, 'pack', 'maps')
              .having(
                (e) => e.message,
                'message',
                contains('matched no files'),
              ),
        ),
      );
    });
  });
}
