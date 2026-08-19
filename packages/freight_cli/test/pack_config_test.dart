import 'package:test/test.dart';
import 'package:freight_cli/src/pack_config.dart';

void main() {
  FreightConfig parse(String yaml) => FreightConfig.parse(yaml);

  Matcher throwsConfigError(String needle, {String? pack}) => throwsA(
    isA<FreightConfigException>()
        .having((e) => e.message, 'message', contains(needle))
        .having((e) => e.pack, 'pack', pack),
  );

  group('FreightConfig.parse', () {
    test('reads a pack with everything specified', () {
      final config = parse('''
packs:
  maps_europe:
    delivery: prefetch
    events: [firstInstallation]
    root: assets/maps/europe
    files: ["**/*.tiles", "index.txt"]
    exclude: ["**/draft_*.tiles"]
    platforms: [iOS, macOS]
''');

      expect(config.packs, hasLength(1));
      final pack = config.packs.single;
      expect(pack.id, 'maps_europe');
      expect(pack.delivery, DeliveryPolicy.prefetch);
      expect(pack.events, {InstallationEvent.firstInstallation});
      expect(pack.root, 'assets/maps/europe');
      expect(pack.files, ['**/*.tiles', 'index.txt']);
      expect(pack.exclude, ['**/draft_*.tiles']);
      expect(pack.platforms, ['iOS', 'macOS']);
    });

    test('defaults everything optional', () {
      final pack =
          parse('''
packs:
  tutorial:
    delivery: essential
    root: assets/tutorial
''').packs.single;

      expect(pack.files, ['**']);
      expect(pack.exclude, isEmpty);
      expect(pack.platforms, ['iOS']);
      expect(pack.events, {
        InstallationEvent.firstInstallation,
        InstallationEvent.subsequentUpdate,
      });
    });

    test('leaves an on-demand pack with no installation events', () {
      final pack =
          parse('''
packs:
  maps:
    delivery: onDemand
    root: assets/maps
''').packs.single;

      expect(pack.events, isEmpty);
    });

    test('keeps packs in declaration order', () {
      final config = parse('''
packs:
  tutorial:
    delivery: essential
    root: a
  maps:
    delivery: onDemand
    root: b
  voices:
    delivery: prefetch
    root: c
''');

      expect(config.packs.map((p) => p.id), ['tutorial', 'maps', 'voices']);
    });

    test('names the offending pack and the valid values', () {
      expect(
        () => parse('''
packs:
  maps:
    delivery: on_demand
    root: assets/maps
'''),
        throwsConfigError('unknown delivery', pack: 'maps'),
      );
      expect(
        () => parse('''
packs:
  maps:
    delivery: on_demand
    root: assets/maps
'''),
        throwsConfigError('onDemand', pack: 'maps'),
      );
    });

    test('rejects events on an on-demand pack', () {
      // Silently ignoring them would leave someone believing a pack downloads
      // at install time when it never will.
      expect(
        () => parse('''
packs:
  maps:
    delivery: onDemand
    root: assets/maps
    events: [firstInstallation]
'''),
        throwsConfigError(
          'applies only to essential and prefetch',
          pack: 'maps',
        ),
      );
    });

    test('rejects an unknown event', () {
      expect(
        () => parse('''
packs:
  maps:
    delivery: prefetch
    root: assets/maps
    events: [onFirstLaunch]
'''),
        throwsConfigError('unknown event', pack: 'maps'),
      );
    });

    test('requires a root, because it decides the logical paths', () {
      expect(
        () => parse('''
packs:
  maps:
    delivery: onDemand
'''),
        throwsConfigError('has no "root"', pack: 'maps'),
      );
    });

    test('requires a delivery policy', () {
      expect(
        () => parse('''
packs:
  maps:
    root: assets/maps
'''),
        throwsConfigError('has no "delivery"', pack: 'maps'),
      );
    });

    test('rejects empty glob lists', () {
      expect(
        () => parse('''
packs:
  maps:
    delivery: onDemand
    root: assets/maps
    files: []
'''),
        throwsConfigError('must be a non-empty list', pack: 'maps'),
      );
    });

    test('rejects a file with no packs at all', () {
      expect(() => parse('packs:\n'), throwsA(isA<FreightConfigException>()));
      expect(() => parse('other: 1\n'), throwsConfigError('has no "packs"'));
      expect(() => parse('- a\n- b\n'), throwsConfigError('must be a map'));
    });

    test('reports unparseable yaml rather than throwing YamlException', () {
      expect(
        () => parse('packs:\n  maps:\n   - broken\n  bad indent\n'),
        throwsA(isA<FreightConfigException>()),
      );
    });
  });
}
