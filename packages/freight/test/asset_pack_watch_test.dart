import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight/freight.dart';
import 'package:freight/src/platform_channel.dart';

/// A bridge that reports whatever the test says, with no platform behind it.
final class _FakePlatform extends FreightPlatform {
  _FakePlatform() : super.forTesting();

  final updates = StreamController<PackStatus>.broadcast();

  PackStatus current = const PackNotDownloaded(
    packId: 'maps',
    flags: PackFlags(0),
  );
  Object? statusThrows;
  var statusCalls = 0;

  @override
  Future<PackStatus> status(String packId) async {
    statusCalls++;
    if (statusThrows case final error?) throw error;
    return current;
  }

  @override
  Stream<PackStatus> watch(String packId) => updates.stream;
}

void main() {
  late _FakePlatform platform;
  final original = FreightPlatform.instance;

  setUp(() {
    platform = _FakePlatform();
    FreightPlatform.instance = platform;
  });

  tearDown(() {
    FreightPlatform.instance = original;
    platform.updates.close();
  });

  group('AssetPack.watch', () {
    test('emits the current state before any change arrives', () async {
      // Without this a pack that is simply sitting there downloaded looks
      // unknown to a StreamBuilder until something happens to it — which for an
      // already-downloaded pack may be never. Found on a device, where the UI
      // offered to download a pack that was already present.
      platform.current = const PackReady(
        packId: 'maps',
        flags: PackFlags(1 << 6),
        version: 3,
        sizeBytes: 1024,
      );

      final first = await Freight.pack('maps').watch().first;

      expect(first, isA<PackReady>());
      expect((first as PackReady).version, 3);
    });

    test('then follows changes', () async {
      final seen = <PackStatus>[];
      final subscription = Freight.pack('maps').watch().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      platform.updates.add(
        const PackDownloading(
          packId: 'maps',
          flags: PackFlags(1 << 5),
          completedBytes: 10,
          totalBytes: 100,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      expect(seen.first, isA<PackNotDownloaded>());
      expect(seen.last, isA<PackDownloading>());
      await subscription.cancel();
    });

    test('still streams when the pack is unknown to the system', () async {
      // A pack the device has never heard of may appear once a manifest
      // arrives, so the subscription must survive the failed first read.
      platform.statusThrows = const PackNotFoundException('maps');

      final seen = <PackStatus>[];
      final subscription = Freight.pack('maps').watch().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
      platform.updates.add(
        const PackReady(
          packId: 'maps',
          flags: PackFlags(1 << 6),
          version: 1,
          sizeBytes: 8,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen.single, isA<PackReady>());
      await subscription.cancel();
    });

    test('reads the current state once per subscription', () async {
      final subscription = Freight.pack('maps').watch().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(platform.statusCalls, 1);
      await subscription.cancel();
    });
  });
}
