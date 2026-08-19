import 'dart:convert';
import 'dart:io';

import 'package:freight_cli/src/xcode/extension_target.dart';
import 'package:freight_cli/src/xcode/pbxproj.dart';
import 'package:test/test.dart';

Pbxproj loadFixture({
  Map<String, Object?> Function(Map<String, Object?>)? patch,
}) {
  const directory = 'test/fixtures';
  final text = File('$directory/flutter_clean.pbxproj').readAsStringSync();
  var parsed =
      jsonDecode(File('$directory/flutter_clean.json').readAsStringSync())
          as Map<String, Object?>;
  if (patch != null) parsed = patch(parsed);
  return Pbxproj.fromParsed('project.pbxproj', text, parsed);
}

void main() {
  ExtensionTargetResult add(Pbxproj project, {String target = 'Downloader'}) =>
      addExtensionTarget(
        project,
        appTargetName: 'Runner',
        targetName: target,
        appGroup: 'group.com.example.cleanapp',
      );

  group('addExtensionTarget', () {
    test('adds an ExtensionKit target, not a plain app extension', () {
      final project = loadFixture();
      add(project);

      // The distinction is load-bearing: an app-extension product type builds a
      // bundle that lands in PlugIns/, where the system never finds it.
      expect(
        project.text,
        contains(
          'productType = "com.apple.product-type.extensionkit-extension"',
        ),
      );
      expect(project.text, contains('name = Downloader;'));
    });

    test('embeds it after Resources and before Thin Binary', () {
      // Appended at the end instead, Xcode reports a dependency cycle.
      final project = loadFixture();
      add(project);

      final runnerId = project.targetNamed('Runner')!;
      // The target's own declaration, not the first mention of its id — an id
      // also appears in the project's targets list and in proxies.
      final declaration = project.text.indexOf('\n\t\t$runnerId ');
      final phasesStart = project.text.indexOf('buildPhases = (', declaration);
      final phasesEnd = project.text.indexOf(');', phasesStart);
      final phases = project.text.substring(phasesStart, phasesEnd);

      expect(phases, contains('Embed Foundation Extensions'));
      expect(
        phases.indexOf('Embed Foundation Extensions'),
        lessThan(phases.indexOf('Thin Binary')),
      );
      expect(
        phases.indexOf('Resources */,'),
        lessThan(phases.indexOf('Embed Foundation Extensions')),
      );
    });

    test('derives the bundle id from the app target', () {
      final project = loadFixture();
      final result = add(project);

      expect(result.bundleId, 'com.example.cleanapp.Downloader');
      expect(
        project.text,
        contains(
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.cleanapp.Downloader;',
        ),
      );
    });

    test('mirrors the configurations the app has', () {
      final project = loadFixture();
      add(project);

      // A project with a Profile configuration and an extension without one
      // fails to build in profile mode, and only in profile mode.
      for (final name in ['Debug', 'Release', 'Profile']) {
        expect(
          RegExp('name = $name;').allMatches(project.text).length,
          greaterThanOrEqualTo(2),
          reason: 'expected an extension configuration named $name',
        );
      }
    });

    test('registers the target, its group and the dependency', () {
      final project = loadFixture();
      add(project);

      expect(project.text, contains('/* Downloader */,'));
      expect(project.text, contains('path = Downloader;'));
      expect(project.text, contains('isa = PBXTargetDependency'));
      expect(project.text, contains('isa = PBXContainerItemProxy'));
    });

    test('gives every generated object a distinct id', () {
      final project = loadFixture();
      add(project);

      final ids =
          RegExp(
            r'\b[0-9A-F]{24}\b',
          ).allMatches(project.text).map((m) => m.group(0)!).toSet();
      final declarations =
          RegExp(
            r'\n\t\t([0-9A-F]{24}) /\*',
          ).allMatches(project.text).map((m) => m.group(1)!).toList();

      expect(
        declarations.toSet().length,
        declarations.length,
        reason: 'an id was declared twice',
      );
      expect(ids, containsAll(declarations));
    });

    test('refuses a project without the named app target', () {
      final project = loadFixture();

      expect(
        () => addExtensionTarget(
          project,
          appTargetName: 'NotThere',
          targetName: 'Downloader',
          appGroup: 'group.com.example.app',
        ),
        throwsA(
          isA<UnsupportedProjectException>().having(
            (e) => e.fix,
            'fix',
            contains('Background Download Extension'),
          ),
        ),
      );
    });

    test('does nothing when the target is already there', () {
      // Refusing would be wrong — running setup twice should be safe — but so
      // would adding a second target with the same name.
      final project = loadFixture(
        patch: (parsed) {
          final objects = parsed['objects']! as Map<String, Object?>;
          final root = objects[parsed['rootObject']]! as Map<String, Object?>;
          objects['AAAABBBBCCCCDDDDEEEEFFFF'] = {
            'isa': 'PBXNativeTarget',
            'name': 'Downloader',
          };
          root['targets'] = [
            ...(root['targets']! as List<Object?>),
            'AAAABBBBCCCCDDDDEEEEFFFF',
          ];
          return parsed;
        },
      );
      final before = project.text;

      final result = add(project);

      expect(result.alreadyPresent, isTrue);
      expect(project.text, before);
    });
  });
}
