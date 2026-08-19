import 'dart:io';

import 'package:freight_cli/src/android/limits.dart';
import 'package:freight_cli/src/pack_config.dart';
import 'package:freight_cli/src/pack_planner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('freight_limits_test');
  });

  tearDown(() => project.deleteSync(recursive: true));

  /// Creates a sparse file of [bytes], so a 600 MB pack costs no disk.
  void sparse(String relativePath, int bytes) {
    final file = File(p.join(project.path, relativePath));
    file.parent.createSync(recursive: true);
    file.openSync(mode: FileMode.write)
      ..truncateSync(bytes)
      ..closeSync();
  }

  PackPlan plan(String id, DeliveryPolicy delivery) => planPack(
    PackConfig(id: id, delivery: delivery, root: 'assets/$id'),
    projectRoot: project.path,
  );

  test('the sparse fixture really has the length it claims', () {
    // Without this the size tests could pass against empty files and prove
    // nothing at all.
    sparse('assets/probe/big.bin', perPackDownloadLimit + 1);
    final length =
        File(p.join(project.path, 'assets/probe/big.bin')).lengthSync();

    expect(length, perPackDownloadLimit + 1);
    expect(plan('probe', DeliveryPolicy.onDemand).sizeInBytes, length);
  });

  group('per-pack limit', () {
    test('warns about an on-demand pack over 512 MB', () {
      sparse('assets/maps/big.bin', perPackDownloadLimit + 1);

      final warnings = checkPlayLimits([plan('maps', DeliveryPolicy.onDemand)]);

      expect(warnings, hasLength(1));
      expect(warnings.single.title, contains('maps'));
      expect(warnings.single.detail, contains('on-demand'));
    });

    test('warns about a fast-follow pack too', () {
      sparse('assets/maps/big.bin', perPackDownloadLimit + 1);

      expect(
        checkPlayLimits([plan('maps', DeliveryPolicy.prefetch)]),
        hasLength(1),
      );
    });

    test('stays quiet exactly at the limit', () {
      sparse('assets/maps/big.bin', perPackDownloadLimit);

      expect(checkPlayLimits([plan('maps', DeliveryPolicy.onDemand)]), isEmpty);
    });

    test('does not apply the per-pack limit to install-time packs', () {
      // Install-time delivery is bounded by a different, larger total, so
      // applying the download limit here would be a false alarm.
      sparse('assets/maps/big.bin', perPackDownloadLimit + 1);

      expect(
        checkPlayLimits([plan('maps', DeliveryPolicy.essential)]),
        isEmpty,
      );
    });
  });

  group('install-time total', () {
    test('warns when the install-time packs together exceed 1 GB', () {
      // Each is individually fine; only the total is not.
      sparse('assets/one/big.bin', installTimeTotalLimit ~/ 2);
      sparse('assets/two/big.bin', installTimeTotalLimit ~/ 2 + 1);

      final warnings = checkPlayLimits([
        plan('one', DeliveryPolicy.essential),
        plan('two', DeliveryPolicy.essential),
      ]);

      expect(warnings, hasLength(1));
      expect(warnings.single.title, 'install-time total');
    });

    test('ignores packs that are not install-time when totalling', () {
      sparse('assets/one/big.bin', installTimeTotalLimit ~/ 2);
      sparse('assets/two/big.bin', installTimeTotalLimit ~/ 2 + 1);

      final warnings = checkPlayLimits([
        plan('one', DeliveryPolicy.essential),
        plan('two', DeliveryPolicy.prefetch),
      ]);

      expect(
        warnings.map((w) => w.title),
        isNot(contains('install-time total')),
      );
    });
  });

  test('says nothing about packs that fit', () {
    sparse('assets/maps/small.bin', 1024);

    expect(checkPlayLimits([plan('maps', DeliveryPolicy.onDemand)]), isEmpty);
  });
}
