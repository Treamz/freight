import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight/src/cli/ba_package.dart';

/// Records what would have been executed.
final class _FakeProcess {
  final List<({List<String> arguments, String? workingDirectory})> calls = [];

  ProcessResult result = ProcessResult(0, 0, '', '');
  Object? throwOnRun;

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add((arguments: arguments, workingDirectory: workingDirectory));
    if (throwOnRun case final error?) throw error;
    return result;
  }
}

void main() {
  late _FakeProcess process;
  late BaPackage tool;

  setUp(() {
    process = _FakeProcess();
    tool = BaPackage(runner: process.run);
  });

  group('version', () {
    test('returns what the tool reports', () async {
      process.result = ProcessResult(0, 0, '1.2\n', '');
      expect(await tool.version(), '1.2');
      expect(process.calls.single.arguments, ['ba-package', '--version']);
    });

    test('explains where the tool comes from when it is absent', () async {
      process.result = ProcessResult(0, 72, '', 'unable to find utility');

      await expectLater(
        tool.version(),
        throwsA(
          isA<BaPackageException>().having(
            (e) => e.message,
            'message',
            contains('Xcode 26'),
          ),
        ),
      );
    });

    test('reports a failure to launch xcrun at all', () async {
      process.throwOnRun = const ProcessException('xcrun', [], 'not found');

      await expectLater(tool.version(), throwsA(isA<BaPackageException>()));
    });
  });

  group('package', () {
    test(
      'runs in the pack root, which is what fixes the logical paths',
      () async {
        await tool.package(
          manifestPath: '/out/manifests/maps.json',
          outputPath: '/out/maps.aar',
          workingDirectory: '/project/assets/maps',
        );

        final call = process.calls.single;
        expect(call.arguments, [
          'ba-package',
          'package',
          '/out/manifests/maps.json',
          '--output-path',
          '/out/maps.aar',
        ]);
        expect(call.workingDirectory, '/project/assets/maps');
      },
    );

    test('rejects an output path the tool would refuse', () async {
      await expectLater(
        tool.package(
          manifestPath: '/m.json',
          outputPath: '/out/maps.zip',
          workingDirectory: '/root',
        ),
        throwsA(
          isA<BaPackageException>().having(
            (e) => e.message,
            'message',
            contains('.aar'),
          ),
        ),
      );
      expect(process.calls, isEmpty);
    });

    test('surfaces the tool output when packaging fails', () async {
      process.result = ProcessResult(0, 1, '', 'no such file');

      await expectLater(
        tool.package(
          manifestPath: '/m.json',
          outputPath: '/out/maps.aar',
          workingDirectory: '/root',
        ),
        throwsA(
          isA<BaPackageException>().having(
            (e) => e.details,
            'details',
            contains('no such file'),
          ),
        ),
      );
    });
  });

  group('createDownloadManifest', () {
    test('passes every pack, the platform and the base url', () async {
      await tool.createDownloadManifest(
        packPaths: ['/out/tutorial.aar', '/out/maps.aar'],
        baseUrl: 'https://cdn.example.com/packs',
        outputPath: '/out/download-manifest.json',
      );

      expect(process.calls.single.arguments, [
        'ba-package',
        'download-manifest',
        'create',
        '/out/tutorial.aar',
        '/out/maps.aar',
        '--ios',
        '--download-base-url',
        'https://cdn.example.com/packs',
        '--output-path',
        '/out/download-manifest.json',
      ]);
    });

    test('refuses to build a manifest describing nothing', () async {
      await expectLater(
        tool.createDownloadManifest(
          packPaths: const [],
          baseUrl: 'https://cdn.example.com/packs',
          outputPath: '/out/download-manifest.json',
        ),
        throwsA(isA<BaPackageException>()),
      );
      expect(process.calls, isEmpty);
    });
  });
}
