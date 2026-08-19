import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight/src/cli/ba_package.dart';
import 'package:freight/src/cli/doctor.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory project;
  late Map<String, Map<String, Object?>> plists;

  setUp(() {
    project = Directory.systemTemp.createTempSync('freight_doctor_test');
    plists = {};
  });

  tearDown(() => project.deleteSync(recursive: true));

  /// Creates the file on disk and registers what reading it returns.
  void plist(String relativePath, Map<String, Object?> contents) {
    final file = File(p.join(project.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('<plist/>');
    // Keyed by the resolved path: on macOS the temp directory lives under a
    // /var -> /private/var symlink, so an unresolved key would never match
    // what the walk reports and this fixture would silently cover nothing.
    plists[file.resolveSymbolicLinksSync()] = contents;
  }

  void write(String relativePath, [String contents = 'x']) {
    final file = File(p.join(project.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void config([String? yaml]) => write(
    'freight.yaml',
    yaml ??
        '''
packs:
  tutorial:
    delivery: onDemand
    root: assets/tutorial
''',
  );

  void appGroupEntitlement(String path, String group) => plist(path, {
    'com.apple.security.application-groups': [group],
  });

  void wellFormedIosProject({String group = 'group.com.example.app'}) {
    plist('ios/Runner/Info.plist', {'BAAppGroupID': group});
    appGroupEntitlement('ios/Runner/Runner.entitlements', group);
    plist('ios/Downloader/Info.plist', {
      'EXAppExtensionAttributes': {
        'EXExtensionPointIdentifier': backgroundAssetsExtensionPoint,
      },
    });
    appGroupEntitlement('ios/Downloader/Downloader.entitlements', group);
  }

  Future<List<Check>> doctor({int toolExitCode = 0}) => runDoctor(
    projectRoot: project.path,
    tool: BaPackage(
      runner:
          (_, _, {workingDirectory}) async =>
              ProcessResult(0, toolExitCode, '1.2\n', ''),
    ),
    readPlist: (path) async {
      final file = File(path);
      if (!file.existsSync()) return null;
      // Resolved, so a plist reached through a symlink is recognised as the
      // same file — without which a test about symlinks observes nothing.
      return plists[file.resolveSymbolicLinksSync()];
    },
  );

  Check find(List<Check> checks, String title) =>
      checks.firstWhere((c) => c.title == title);

  Matcher hasStatus(CheckStatus status) =>
      isA<Check>().having((c) => c.status, 'status', status);

  group('runDoctor', () {
    test('passes everything on a correctly configured project', () async {
      config();
      write('assets/tutorial/welcome.txt');
      wellFormedIosProject();

      final checks = await doctor();
      expect(
        checks.where((c) => c.status != CheckStatus.pass),
        isEmpty,
        reason: checks
            .where((c) => c.status != CheckStatus.pass)
            .map((c) => '${c.title}: ${c.detail}')
            .join('; '),
      );
    });

    test('does not read other plugins through ios/.symlinks', () async {
      // Flutter links every plugin's iOS directory into .symlinks. Walking in
      // would read other packages' property lists, and a plugin's Info.plist
      // could be taken for the app's own.
      //
      // Nothing in this app declares an app group; the only BAAppGroupID in
      // reach sits behind the symlink, so finding one at all is the bug.
      config();
      write('assets/tutorial/welcome.txt');
      plist('ios/Runner/Info.plist', {});
      plist('ios/Downloader/Info.plist', {
        'EXAppExtensionAttributes': {
          'EXExtensionPointIdentifier': backgroundAssetsExtensionPoint,
        },
      });

      final foreign = Directory(p.join(project.path, 'other_plugin/ios'))
        ..createSync(recursive: true);
      plist('other_plugin/ios/Runner/Info.plist', {
        'BAAppGroupID': 'group.someone.else',
      });
      Link(p.join(project.path, 'ios/.symlinks')).createSync(foreign.path);

      final check = find(await doctor(), 'BAAppGroupID');
      expect(check, hasStatus(CheckStatus.fail));
      expect(check.detail ?? '', isNot(contains('someone.else')));
    });

    test(
      'reports a missing BAAppGroupID, which the platform reports as a crash',
      () async {
        config();
        write('assets/tutorial/welcome.txt');
        plist('ios/Runner/Info.plist', {});
        plist('ios/Downloader/Info.plist', {
          'EXAppExtensionAttributes': {
            'EXExtensionPointIdentifier': backgroundAssetsExtensionPoint,
          },
        });

        expect(
          find(await doctor(), 'BAAppGroupID'),
          hasStatus(CheckStatus.fail),
        );
      },
    );

    test('reports an app group no target actually grants', () async {
      config();
      write('assets/tutorial/welcome.txt');
      plist('ios/Runner/Info.plist', {'BAAppGroupID': 'group.com.example.app'});
      plist('ios/Downloader/Info.plist', {
        'EXAppExtensionAttributes': {
          'EXExtensionPointIdentifier': backgroundAssetsExtensionPoint,
        },
      });

      expect(
        find(await doctor(), 'App Groups capability'),
        hasStatus(CheckStatus.fail),
      );
    });

    test('warns when only one target shares the group', () async {
      // The extension writes packs into the container the app reads from, so
      // one target holding it is a setup that builds and then does nothing.
      config();
      write('assets/tutorial/welcome.txt');
      plist('ios/Runner/Info.plist', {'BAAppGroupID': 'group.com.example.app'});
      appGroupEntitlement(
        'ios/Runner/Runner.entitlements',
        'group.com.example.app',
      );
      plist('ios/Downloader/Info.plist', {
        'EXAppExtensionAttributes': {
          'EXExtensionPointIdentifier': backgroundAssetsExtensionPoint,
        },
      });

      expect(
        find(await doctor(), 'App group is shared'),
        hasStatus(CheckStatus.warn),
      );
    });

    test('reports a missing downloader extension', () async {
      config();
      write('assets/tutorial/welcome.txt');
      plist('ios/Runner/Info.plist', {'BAAppGroupID': 'group.com.example.app'});
      appGroupEntitlement(
        'ios/Runner/Runner.entitlements',
        'group.com.example.app',
      );

      expect(
        find(await doctor(), 'Downloader extension'),
        hasStatus(CheckStatus.fail),
      );
    });

    test('ignores an extension declaring some other extension point', () async {
      config();
      write('assets/tutorial/welcome.txt');
      plist('ios/Share/Info.plist', {
        'EXAppExtensionAttributes': {
          'EXExtensionPointIdentifier': 'com.apple.share-services',
        },
      });

      expect(
        find(await doctor(), 'Downloader extension'),
        hasStatus(CheckStatus.fail),
      );
    });

    test('reports a pack whose globs match nothing', () async {
      config();
      Directory(
        p.join(project.path, 'assets/tutorial'),
      ).createSync(recursive: true);
      wellFormedIosProject();

      expect(
        find(await doctor(), 'pack "tutorial"'),
        hasStatus(CheckStatus.fail),
      );
    });

    test('reports a pack root that does not exist', () async {
      config();
      wellFormedIosProject();

      expect(
        find(await doctor(), 'pack "tutorial"'),
        hasStatus(CheckStatus.fail),
      );
    });

    test('reports a missing configuration', () async {
      wellFormedIosProject();

      expect(find(await doctor(), 'freight.yaml'), hasStatus(CheckStatus.fail));
    });

    test('reports an unusable ba-package', () async {
      config();
      write('assets/tutorial/welcome.txt');
      wellFormedIosProject();

      expect(
        find(await doctor(toolExitCode: 72), 'ba-package'),
        hasStatus(CheckStatus.fail),
      );
    });

    test(
      'warns rather than fails when run outside a Flutter project',
      () async {
        config();
        write('assets/tutorial/welcome.txt');

        expect(
          find(await doctor(), 'iOS project'),
          hasStatus(CheckStatus.warn),
        );
      },
    );
  });
}
