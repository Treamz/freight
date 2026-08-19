import 'dart:convert';
import 'dart:io';

import 'package:freight_cli/src/xcode/pbxproj.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A real project.pbxproj from `flutter create`, with the tree plutil parses
/// out of it. Committed together so the tests run where plutil does not.
Pbxproj loadFixture() {
  // Relative to the package root, which is where `dart test` runs.
  const directory = 'test/fixtures';
  final text =
      File(p.join(directory, 'flutter_clean.pbxproj')).readAsStringSync();
  final parsed =
      jsonDecode(
            File(p.join(directory, 'flutter_clean.json')).readAsStringSync(),
          )
          as Map<String, Object?>;
  return Pbxproj.fromParsed('project.pbxproj', text, parsed);
}

void main() {
  late Pbxproj project;

  setUp(() => project = loadFixture());

  group('reading', () {
    test('finds the targets flutter create makes', () {
      expect(project.targetNamed('Runner'), isNotNull);
      expect(project.targetNamed('RunnerTests'), isNotNull);
      expect(project.targetNamed('FreightDownloader'), isNull);
    });
  });

  group('generateId', () {
    test('is stable for a seed, so re-running produces no diff', () {
      expect(project.generateId('a'), loadFixture().generateId('a'));
    });

    test('differs between seeds', () {
      expect(project.generateId('a'), isNot(project.generateId('b')));
    });

    test('produces ids of the shape Xcode uses', () {
      expect(project.generateId('a'), matches(RegExp(r'^[0-9A-F]{24}$')));
    });

    test('avoids an id already in the file', () {
      // Not a theoretical concern: reusing an id silently reassigns whatever
      // object already owned it.
      final existing = project.targetNamed('Runner')!;
      expect(project.containsId(existing), isTrue);
      for (var i = 0; i < 50; i++) {
        expect(project.generateId('seed$i'), isNot(existing));
      }
    });
  });

  group('addObject', () {
    test('inserts before the section end marker', () {
      project.addObject(
        section: 'PBXFileReference',
        body: '\t\tDEADBEEF /* marker */ = {isa = PBXFileReference; };',
      );

      final text = project.text;
      final inserted = text.indexOf('DEADBEEF');
      final end = text.indexOf('/* End PBXFileReference section */');
      expect(inserted, greaterThan(0));
      expect(inserted, lessThan(end));
    });

    test('creates a section the project does not have', () {
      expect(project.text, isNot(contains('PBXAggregateTarget')));

      project.addObject(
        section: 'PBXAggregateTarget',
        body: '\t\tDEADBEEF /* marker */ = {isa = PBXAggregateTarget; };',
      );

      expect(project.text, contains('/* Begin PBXAggregateTarget section */'));
      expect(project.text, contains('/* End PBXAggregateTarget section */'));
      expect(project.text, contains('DEADBEEF'));
    });
  });

  group('addToList', () {
    test('adds to a list inside the right object', () {
      project.addToList(
        objectId: project.rootObjectId,
        key: 'targets',
        entry: '\t\t\t\tDEADBEEF /* marker */,',
      );

      expect(project.text, contains('DEADBEEF /* marker */,'));
    });

    test('places an entry after a named one', () {
      // Build phase order is not cosmetic: an embed phase after Flutter's
      // "Thin Binary" script produces a dependency cycle.
      final runnerId = project.targetNamed('Runner')!;
      final runner = project.object(runnerId)!;
      final phases = (runner['buildPhases'] as List<Object?>).cast<String>();
      final resources = phases.firstWhere(
        (id) => project.object(id)?['isa'] == 'PBXResourcesBuildPhase',
      );

      project.addToList(
        objectId: runnerId,
        key: 'buildPhases',
        entry: '\t\t\t\tDEADBEEF /* marker */,',
        afterEntryContaining: resources,
      );

      final text = project.text;
      final marker = text.indexOf('DEADBEEF /* marker */,');
      final resourcesEntry = text.indexOf(
        resources,
        text.indexOf('buildPhases = (', text.indexOf(runnerId)),
      );
      final thinBinary = text.indexOf('Thin Binary */,');
      expect(marker, greaterThan(resourcesEntry));
      expect(marker, lessThan(thinBinary));
    });

    test('reports a list that is not there', () {
      expect(
        () => project.addToList(
          objectId: project.rootObjectId,
          key: 'nonexistent',
          entry: 'x',
        ),
        throwsA(isA<PbxprojException>()),
      );
    });
  });

  group('setBuildSetting', () {
    String someConfigurationId() {
      final runner = project.object(project.targetNamed('Runner')!)!;
      final list = project.object(runner['buildConfigurationList']! as String)!;
      return (list['buildConfigurations'] as List<Object?>)
          .cast<String>()
          .first;
    }

    test('adds a setting that is absent', () {
      final id = someConfigurationId();
      expect(
        project.setBuildSetting(
          configurationId: id,
          key: 'CODE_SIGN_ENTITLEMENTS',
          value: 'Runner/Runner.entitlements',
        ),
        isTrue,
      );
      expect(
        project.text,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'),
      );
    });

    test('leaves a setting the project already made alone', () {
      final id = someConfigurationId();
      expect(
        project.setBuildSetting(
          configurationId: id,
          key: 'PRODUCT_BUNDLE_IDENTIFIER',
          value: 'com.example.hijacked',
        ),
        isFalse,
      );
      expect(project.text, isNot(contains('com.example.hijacked')));
    });
  });
}
