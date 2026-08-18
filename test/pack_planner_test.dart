import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight/src/cli/pack_config.dart';
import 'package:freight/src/cli/pack_planner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('freight_planner_test');
  });

  tearDown(() => project.deleteSync(recursive: true));

  void write(String relativePath, [String contents = 'x']) {
    final file = File(p.join(project.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  PackConfig pack({
    List<String> files = const ['**'],
    List<String> exclude = const [],
    String root = 'assets/maps',
  }) => PackConfig(
    id: 'maps',
    delivery: DeliveryPolicy.onDemand,
    root: root,
    files: files,
    exclude: exclude,
  );

  PackPlan plan(PackConfig config) =>
      planPack(config, projectRoot: project.path);

  group('planPack', () {
    test('returns paths relative to the pack root, sorted', () {
      write('assets/maps/berlin.tiles');
      write('assets/maps/index.txt');
      write('assets/maps/nested/deep/prague.tiles');

      // These are the exact strings the app passes to Freight.read, which is
      // why they must not carry the source layout above the root.
      expect(plan(pack()).files, [
        'berlin.tiles',
        'index.txt',
        'nested/deep/prague.tiles',
      ]);
    });

    test('ignores files outside the pack root', () {
      write('assets/maps/inside.txt');
      write('assets/elsewhere/outside.txt');
      write('outside_entirely.txt');

      expect(plan(pack()).files, ['inside.txt']);
    });

    test('selects with globs', () {
      write('assets/maps/berlin.tiles');
      write('assets/maps/prague.tiles');
      write('assets/maps/notes.md');

      expect(plan(pack(files: ['*.tiles'])).files, [
        'berlin.tiles',
        'prague.tiles',
      ]);
    });

    test('merges several globs without duplicating an overlap', () {
      write('assets/maps/berlin.tiles');
      write('assets/maps/index.txt');

      final files = plan(pack(files: ['**', '*.tiles'])).files;
      expect(files, ['berlin.tiles', 'index.txt']);
    });

    test('subtracts excludes after matching', () {
      write('assets/maps/berlin.tiles');
      write('assets/maps/draft_wip.tiles');
      write('assets/maps/nested/draft_two.tiles');

      expect(plan(pack(exclude: ['**/draft_*.tiles', 'draft_*.tiles'])).files, [
        'berlin.tiles',
      ]);
    });

    test('lists no directories, only files', () {
      write('assets/maps/nested/deep.txt');

      final files = plan(pack()).files;
      expect(files, ['nested/deep.txt']);
      expect(files, isNot(contains('nested')));
    });

    test('reports a root that does not exist', () {
      expect(
        () => plan(pack(root: 'assets/missing')),
        throwsA(
          isA<FreightConfigException>()
              .having((e) => e.pack, 'pack', 'maps')
              .having((e) => e.message, 'message', contains('does not exist')),
        ),
      );
    });

    test(
      'resolves the root to an absolute directory for the packaging step',
      () {
        write('assets/maps/berlin.tiles');

        // ba-package must be invoked with this as its working directory; that is
        // what makes the logical paths come out as planned.
        expect(
          plan(pack()).rootDirectory,
          p.normalize(p.join(project.path, 'assets/maps')),
        );
      },
    );

    test('measures the pack for the store size limits', () {
      write('assets/maps/berlin.tiles', 'a' * 1000);
      write('assets/maps/index.txt', 'b' * 24);

      expect(plan(pack()).sizeInBytes, 1024);
    });

    test(
      'plans an empty pack rather than throwing, leaving that to the manifest',
      () {
        Directory(
          p.join(project.path, 'assets/maps'),
        ).createSync(recursive: true);

        expect(plan(pack()).files, isEmpty);
      },
    );
  });
}
