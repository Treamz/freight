import 'package:flutter_test/flutter_test.dart';
import 'package:freight/freight.dart';

void main() {
  group('PackFlags', () {
    test('decodes each bit independently', () {
      expect(const PackFlags(1 << 0).downloadAvailable, isTrue);
      expect(const PackFlags(1 << 1).updateAvailable, isTrue);
      expect(const PackFlags(1 << 2).upToDate, isTrue);
      expect(const PackFlags(1 << 3).outOfDate, isTrue);
      expect(const PackFlags(1 << 4).obsolete, isTrue);
      expect(const PackFlags(1 << 5).downloading, isTrue);
      expect(const PackFlags(1 << 6).downloaded, isTrue);
    });

    test('reads combined states, because the platform is an OptionSet', () {
      // iOS reports a pack that is present but superseded as downloaded and
      // outOfDate at once; neither may mask the other.
      const flags = PackFlags((1 << 6) | (1 << 3));
      expect(flags.downloaded, isTrue);
      expect(flags.outOfDate, isTrue);
      expect(flags.upToDate, isFalse);
    });

    test('reports nothing set for zero', () {
      const flags = PackFlags(0);
      expect(flags.downloaded, isFalse);
      expect(flags.downloading, isFalse);
      expect(flags.downloadAvailable, isFalse);
    });
  });

  group('PackDownloading', () {
    PackDownloading downloading(int completed, int total) => PackDownloading(
      packId: 'maps',
      flags: const PackFlags(1 << 5),
      completedBytes: completed,
      totalBytes: total,
    );

    test('computes a fraction from byte counts', () {
      expect(downloading(50, 200).fraction, 0.25);
    });

    test('returns null while the total size is unknown', () {
      // The first update can arrive before the size is known; a caller showing
      // an indeterminate spinner needs to tell that apart from zero progress.
      expect(downloading(0, 0).fraction, isNull);
    });

    test('clamps a total the platform under-reports', () {
      expect(downloading(300, 200).fraction, 1.0);
    });
  });

  group('PackReady', () {
    PackReady ready(PackFlags flags) =>
        PackReady(packId: 'maps', flags: flags, version: 3, sizeBytes: 1024);

    test('reports an update from either flag the platform may set', () {
      expect(ready(const PackFlags(1 << 1)).hasUpdate, isTrue);
      expect(ready(const PackFlags(1 << 3)).hasUpdate, isTrue);
    });

    test('reports no update when up to date', () {
      expect(ready(const PackFlags((1 << 6) | (1 << 2))).hasUpdate, isFalse);
    });
  });
}
