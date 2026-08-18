import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight/src/cli/ba_package.dart';
import 'package:freight/src/cli/builder.dart';
import 'package:freight/src/cli/pack_config.dart';
import 'package:path/path.dart' as p;

final class _FakeProcess {
  final List<({List<String> arguments, String? workingDirectory})> calls = [];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add((arguments: arguments, workingDirectory: workingDirectory));
    return ProcessResult(0, 0, '1.2\n', '');
  }

  Iterable<List<String>> get packageCalls => calls
      .map((c) => c.arguments)
      .where((a) => a.elementAtOrNull(1) == 'package');
}

void main() {
  late Directory project;
  late _FakeProcess process;

  setUp(() {
    project = Directory.systemTemp.createTempSync('freight_builder_test');
    process = _FakeProcess();
  });

  tearDown(() => project.deleteSync(recursive: true));

  void write(String relativePath) {
    final file = File(p.join(project.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('x');
  }

  Future<BuildResult> build({String? baseUrl, String? yaml}) => buildPacks(
    config: FreightConfig.parse(
      yaml ??
          '''
packs:
  tutorial:
    delivery: prefetch
    root: packs/tutorial
  maps:
    delivery: onDemand
    root: packs/maps
''',
    ),
    projectRoot: project.path,
    outputDirectory: p.join(project.path, 'build/packs'),
    downloadBaseUrl: baseUrl,
    tool: BaPackage(runner: process.run),
    log: (_) {},
  );

  test('packages each pack from its own root', () async {
    write('packs/tutorial/welcome.txt');
    write('packs/maps/berlin.tiles');

    final result = await build();

    expect(result.packs.map((b) => b.plan.config.id), ['tutorial', 'maps']);
    // The working directory is the whole reason logical paths come out clean;
    // getting it wrong would prefix every path with the source layout.
    expect(
      process.calls
          .where((c) => c.workingDirectory != null)
          .map((c) => c.workingDirectory),
      [
        p.join(project.path, 'packs/tutorial'),
        p.join(project.path, 'packs/maps'),
      ],
    );
  });

  test('checks the tool before doing any work', () async {
    write('packs/tutorial/welcome.txt');
    write('packs/maps/berlin.tiles');

    await build();

    expect(process.calls.first.arguments, ['ba-package', '--version']);
  });

  test('leaves the generated manifest on disk to be read', () async {
    write('packs/tutorial/nested/deep.txt');
    write('packs/maps/berlin.tiles');

    final result = await build();
    final manifest = File(result.packs.first.manifestPath);

    expect(manifest.existsSync(), isTrue);
    final decoded =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    expect(decoded['assetPackID'], 'tutorial');
    expect(decoded['fileSelectors'], [
      {'file': 'nested/deep.txt'},
    ]);
  });

  test('writes a download manifest only when self-hosting', () async {
    write('packs/tutorial/welcome.txt');
    write('packs/maps/berlin.tiles');

    expect((await build()).downloadManifestPath, isNull);
    expect(
      process.calls.any((c) => c.arguments.contains('download-manifest')),
      isFalse,
    );

    process.calls.clear();
    final hosted = await build(baseUrl: 'https://cdn.example.com/packs');

    expect(hosted.downloadManifestPath, isNotNull);
    final call = process.calls.last.arguments;
    expect(call, contains('download-manifest'));
    expect(call, contains('https://cdn.example.com/packs'));
  });

  test('stops on a pack that would ship empty', () async {
    Directory(
      p.join(project.path, 'packs/tutorial'),
    ).createSync(recursive: true);
    write('packs/maps/berlin.tiles');

    await expectLater(build(), throwsA(isA<FreightConfigException>()));
    expect(process.packageCalls, isEmpty);
  });

  test('reports a root that is missing before packaging anything', () async {
    write('packs/maps/berlin.tiles');

    await expectLater(build(), throwsA(isA<FreightConfigException>()));
    expect(process.packageCalls, isEmpty);
  });
}
