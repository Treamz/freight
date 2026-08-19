import 'dart:io';

import 'package:freight_cli/src/android/asset_packs.dart';
import 'package:freight_cli/src/pack_config.dart';
import 'package:freight_cli/src/pack_planner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('freight_android_test');
  });

  tearDown(() => project.deleteSync(recursive: true));

  void write(String relativePath, String contents) {
    final file = File(p.join(project.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String read(String relativePath) =>
      File(p.join(project.path, relativePath)).readAsStringSync();

  void flutterAndroidProject() {
    write('android/settings.gradle.kts', '''
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
''');
    write('android/app/build.gradle.kts', '''
android {
    namespace = "com.example.app"
}
''');
  }

  FreightConfig config([String? yaml]) => FreightConfig.parse(
    yaml ??
        '''
packs:
  tutorial:
    delivery: prefetch
    root: assets/tutorial
  maps_europe:
    delivery: onDemand
    root: assets/maps
''',
  );

  group('deliveryTypeOf', () {
    test('maps each policy to the Play name', () {
      // These three are why one freight.yaml can describe both platforms.
      expect(deliveryTypeOf(DeliveryPolicy.essential), 'install-time');
      expect(deliveryTypeOf(DeliveryPolicy.prefetch), 'fast-follow');
      expect(deliveryTypeOf(DeliveryPolicy.onDemand), 'on-demand');
    });
  });

  group('generateAssetPackModules', () {
    test('writes a module per pack with its delivery type', () {
      flutterAndroidProject();
      generateAssetPackModules(projectRoot: project.path, config: config());

      final tutorial = read('android/tutorial/build.gradle.kts');
      expect(tutorial, contains('id("com.android.asset-pack")'));
      expect(tutorial, contains('packName.set("tutorial")'));
      expect(tutorial, contains('deliveryType.set("fast-follow")'));

      expect(
        read('android/maps_europe/build.gradle.kts'),
        contains('deliveryType.set("on-demand")'),
      );
    });

    test('declares the plugin once, at the version AGP already uses', () {
      // Picking a version here rather than reusing the project's would be a
      // second source of truth that drifts.
      flutterAndroidProject();
      generateAssetPackModules(projectRoot: project.path, config: config());

      final settings = read('android/settings.gradle.kts');
      expect(
        settings,
        contains('id("com.android.asset-pack") version "9.0.1" apply false'),
      );
      expect(
        'apply false apply false'.allMatches(settings).length,
        0,
        reason: 'the existing "apply false" must not be duplicated',
      );
    });

    test('includes every module and lists them on the app', () {
      flutterAndroidProject();
      generateAssetPackModules(projectRoot: project.path, config: config());

      expect(
        read('android/settings.gradle.kts'),
        contains('include(":tutorial")'),
      );
      expect(
        read('android/settings.gradle.kts'),
        contains('include(":maps_europe")'),
      );
      expect(
        read('android/app/build.gradle.kts'),
        contains('assetPacks += listOf(":tutorial", ":maps_europe")'),
      );
    });

    test('ignores the staged assets, which are build output', () {
      flutterAndroidProject();
      generateAssetPackModules(projectRoot: project.path, config: config());

      expect(read('android/tutorial/.gitignore'), contains('src/main/assets/'));
    });

    test('changes nothing on a second run', () {
      flutterAndroidProject();
      generateAssetPackModules(projectRoot: project.path, config: config());
      final settings = read('android/settings.gradle.kts');
      final app = read('android/app/build.gradle.kts');

      final second = generateAssetPackModules(
        projectRoot: project.path,
        config: config(),
      );

      expect(second.created, isEmpty);
      expect(second.modified, isEmpty);
      expect(read('android/settings.gradle.kts'), settings);
      expect(read('android/app/build.gradle.kts'), app);
    });

    test('reports a project with no android directory', () {
      expect(
        () => generateAssetPackModules(
          projectRoot: project.path,
          config: config(),
        ),
        throwsA(isA<AndroidSetupException>()),
      );
    });
  });

  group('stageAssetPacks', () {
    PackPlan plan(String id, String root) => planPack(
      PackConfig(id: id, delivery: DeliveryPolicy.onDemand, root: root),
      projectRoot: project.path,
    );

    test('copies files under the logical paths the app reads back', () {
      // The same strings the iOS archive records, which is the whole point of
      // declaring a root.
      write('assets/tutorial/welcome.txt', 'hi');
      write('assets/tutorial/nested/deep.txt', 'deep');
      flutterAndroidProject();
      generateAssetPackModules(projectRoot: project.path, config: config());

      stageAssetPacks(
        projectRoot: project.path,
        plans: [plan('tutorial', 'assets/tutorial')],
      );

      expect(read('android/tutorial/src/main/assets/welcome.txt'), 'hi');
      expect(read('android/tutorial/src/main/assets/nested/deep.txt'), 'deep');
    });

    test('drops a file the globs no longer match', () {
      // Staging into the source tree means yesterday's file would otherwise
      // keep shipping.
      write('assets/tutorial/welcome.txt', 'hi');
      flutterAndroidProject();
      generateAssetPackModules(projectRoot: project.path, config: config());
      write('android/tutorial/src/main/assets/stale.txt', 'old');

      stageAssetPacks(
        projectRoot: project.path,
        plans: [plan('tutorial', 'assets/tutorial')],
      );

      expect(
        File(
          p.join(project.path, 'android/tutorial/src/main/assets/stale.txt'),
        ).existsSync(),
        isFalse,
      );
      expect(read('android/tutorial/src/main/assets/welcome.txt'), 'hi');
    });
  });

  group('pack ids', () {
    test('rejects an id Play would refuse as a module name', () {
      // A hyphen is fine on iOS and fatal on Android; catching it in the parser
      // keeps one id valid on both.
      expect(
        () => FreightConfig.parse('''
packs:
  maps-europe:
    delivery: onDemand
    root: assets/maps
'''),
        throwsA(
          isA<FreightConfigException>().having(
            (e) => e.message,
            'message',
            contains('letters, numbers and underscores'),
          ),
        ),
      );
    });

    test('accepts the shape Play allows', () {
      expect(
        FreightConfig.parse('''
packs:
  maps_europe2:
    delivery: onDemand
    root: assets/maps
''').packs.single.id,
        'maps_europe2',
      );
    });
  });
}
