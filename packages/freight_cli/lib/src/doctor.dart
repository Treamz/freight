import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'android/asset_packs.dart';
import 'android/limits.dart';
import 'ba_package.dart';
import 'pack_config.dart';
import 'pack_planner.dart';

/// The extension point a Background Assets downloader extension declares.
const backgroundAssetsExtensionPoint =
    'com.apple.background-assets.content-request';

/// Reads a property list. Injectable so the checks can be tested without
/// macOS — the default shells out to `plutil`, which also handles binary
/// plists, rather than pulling in an XML parser for one command.
typedef PlistReader = Future<Map<String, Object?>?> Function(String path);

Future<Map<String, Object?>?> _readPlist(String path) async {
  if (!File(path).existsSync()) return null;
  final result = await Process.run('plutil', [
    '-convert',
    'json',
    '-o',
    '-',
    path,
  ]);
  if (result.exitCode != 0) return null;
  final decoded = jsonDecode(result.stdout as String);
  return decoded is Map<String, Object?> ? decoded : null;
}

enum CheckStatus { pass, warn, fail }

/// One diagnostic.
final class Check {
  const Check.pass(this.title, {this.detail})
    : status = CheckStatus.pass,
      fix = null;
  const Check.warn(this.title, {this.detail, this.fix})
    : status = CheckStatus.warn;
  const Check.fail(this.title, {this.detail, this.fix})
    : status = CheckStatus.fail;

  final String title;
  final CheckStatus status;

  /// What was found.
  final String? detail;

  /// What to do about it.
  final String? fix;
}

/// Checks a project for the things that otherwise fail late.
///
/// Every iOS check here corresponds to something the platform reports only at
/// runtime, on a device, and mostly by trapping rather than returning an error.
Future<List<Check>> runDoctor({
  required String projectRoot,
  String configPath = 'freight.yaml',
  BaPackage tool = const BaPackage(),
  PlistReader readPlist = _readPlist,
}) async {
  final checks = <Check>[];
  final hasIos = Directory(p.join(projectRoot, 'ios')).existsSync();
  final hasAndroid = Directory(p.join(projectRoot, 'android')).existsSync();

  // ba-package builds iOS packs and ships with Xcode, so an Android-only
  // project has no business being told to install it.
  if (hasIos) checks.addAll(await _checkTooling(tool));

  final (config, configChecks, plans) = _checkConfiguration(
    projectRoot,
    configPath,
  );
  checks.addAll(configChecks);

  for (final warning in checkPlayLimits(plans)) {
    checks.add(
      Check.warn(warning.title, detail: warning.detail, fix: warning.fix),
    );
  }

  if (hasIos) checks.addAll(await _checkIosProject(projectRoot, readPlist));
  if (hasAndroid && config != null) {
    checks.addAll(_checkAndroidProject(projectRoot, config));
  }

  if (!hasIos && !hasAndroid) {
    checks.add(
      Check.warn(
        'Platform projects',
        detail: 'neither ios/ nor android/ is present',
        fix: 'Run doctor from the directory holding your pubspec.yaml.',
      ),
    );
  }

  return checks;
}

/// Checks the Gradle wiring `freight setup` generates.
///
/// Everything here fails the app bundle rather than the app, and often only in
/// release, which is a slow way to find out that a module was never included.
List<Check> _checkAndroidProject(String projectRoot, FreightConfig config) {
  final android = p.join(projectRoot, 'android');
  final checks = <Check>[];

  final settingsFile = File(p.join(android, 'settings.gradle.kts'));
  final appFile = File(p.join(android, 'app', 'build.gradle.kts'));
  if (!settingsFile.existsSync() || !appFile.existsSync()) {
    return [
      Check.warn(
        'Android project',
        detail: 'no settings.gradle.kts or app/build.gradle.kts under android/',
        fix: 'freight expects the layout flutter create produces.',
      ),
    ];
  }

  final settings = settingsFile.readAsStringSync();
  final app = appFile.readAsStringSync();

  checks.add(
    settings.contains('com.android.asset-pack')
        ? const Check.pass('Asset pack plugin')
        : const Check.fail(
          'Asset pack plugin',
          detail: 'settings.gradle.kts does not declare com.android.asset-pack',
          fix: 'Run "freight setup".',
        ),
  );

  for (final pack in config.packs) {
    final module = File(p.join(android, pack.id, 'build.gradle.kts'));
    if (!module.existsSync()) {
      checks.add(
        Check.fail(
          'module "${pack.id}"',
          detail: 'no android/${pack.id}/build.gradle.kts',
          fix: 'Run "freight setup".',
        ),
      );
      continue;
    }

    final problems = <String>[];
    if (!settings.contains('include(":${pack.id}")')) {
      problems.add('not included in settings.gradle.kts');
    }
    if (!app.contains('":${pack.id}"')) {
      problems.add('not listed in the app\'s assetPacks');
    }

    // Drift: changing delivery in freight.yaml does nothing until setup runs
    // again, and the build succeeds either way with the old policy.
    final expected = deliveryTypeOf(pack.delivery);
    final declared = RegExp(
      r'deliveryType\.set\("([^"]+)"\)',
    ).firstMatch(module.readAsStringSync())?.group(1);
    if (declared != expected) {
      problems.add(
        'declares "${declared ?? 'nothing'}" but freight.yaml says '
        '"$expected"',
      );
    }

    checks.add(
      problems.isEmpty
          ? Check.pass('module "${pack.id}"', detail: expected)
          : Check.fail(
            'module "${pack.id}"',
            detail: problems.join('; '),
            fix: 'Run "freight setup" to regenerate the Gradle wiring.',
          ),
    );
  }

  return checks;
}

Future<List<Check>> _checkTooling(BaPackage tool) async {
  try {
    return [Check.pass('ba-package', detail: await tool.version())];
  } on BaPackageException catch (e) {
    return [
      Check.fail(
        'ba-package',
        detail: e.message,
        fix: 'Install Xcode 26 or newer and select it with xcode-select.',
      ),
    ];
  }
}

(FreightConfig?, List<Check>, List<PackPlan>) _checkConfiguration(
  String projectRoot,
  String configPath,
) {
  final file = File(p.join(projectRoot, configPath));
  if (!file.existsSync()) {
    return (
      null,
      [
        Check.fail(
          'freight.yaml',
          detail: 'not found at ${file.path}',
          fix:
              'Declare your asset packs in freight.yaml. See doc/ios-setup.md.',
        ),
      ],
      const [],
    );
  }

  final FreightConfig config;
  try {
    config = FreightConfig.parse(file.readAsStringSync());
  } on FreightConfigException catch (e) {
    return (null, [Check.fail('freight.yaml', detail: e.toString())], const []);
  }

  final checks = <Check>[
    Check.pass(
      'freight.yaml',
      detail:
          '${config.packs.length} pack'
          '${config.packs.length == 1 ? '' : 's'}',
    ),
  ];
  final plans = <PackPlan>[];

  for (final pack in config.packs) {
    try {
      final plan = planPack(pack, projectRoot: projectRoot);
      plans.add(plan);
      if (plan.files.isEmpty) {
        checks.add(
          Check.fail(
            'pack "${pack.id}"',
            detail: 'its globs match no files under ${pack.root}',
            fix:
                'An empty pack packages and publishes cleanly, then fails at '
                'runtime as a missing asset. Check the "files" globs.',
          ),
        );
      } else {
        checks.add(
          Check.pass(
            'pack "${pack.id}"',
            detail: '${plan.files.length} files, ${plan.sizeInBytes} bytes',
          ),
        );
      }
    } on FreightConfigException catch (e) {
      checks.add(Check.fail('pack "${pack.id}"', detail: e.message));
    }
  }

  return (config, checks, plans);
}

Future<List<Check>> _checkIosProject(
  String projectRoot,
  PlistReader readPlist,
) async {
  final iosDirectory = Directory(p.join(projectRoot, 'ios'));
  if (!iosDirectory.existsSync()) {
    return [
      Check.warn(
        'iOS project',
        detail: 'no ios/ directory at ${iosDirectory.path}',
        fix: 'Run doctor from the directory holding your pubspec.yaml.',
      ),
    ];
  }

  final plists = <String, Map<String, Object?>>{};
  final entitlements = <String, Map<String, Object?>>{};
  for (final file in _projectFiles(iosDirectory)) {
    final name = p.basename(file.path);
    if (name == 'Info.plist') {
      final contents = await readPlist(file.path);
      if (contents != null) plists[file.path] = contents;
    } else if (p.extension(file.path) == '.entitlements') {
      final contents = await readPlist(file.path);
      if (contents != null) entitlements[file.path] = contents;
    }
  }

  final appGroups = {
    for (final entry in entitlements.entries)
      entry.key:
          (entry.value['com.apple.security.application-groups']
                      as List<Object?>? ??
                  const [])
              .whereType<String>()
              .toSet(),
  };

  return [
    ..._checkAppGroup(plists, appGroups),
    ..._checkExtension(plists, appGroups),
  ];
}

/// Directories that hold other projects' files or build output.
///
/// `.symlinks` is the important one: Flutter links every plugin's iOS
/// directory into it, so walking through would read other packages' property
/// lists and could report a plugin's Info.plist as the app's own.
const _skippedDirectories = {
  '.symlinks',
  'Pods',
  'build',
  'DerivedData',
  '.git',
};

/// The project's own files, without following links or descending into build
/// output.
Iterable<File> _projectFiles(Directory directory) sync* {
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is File) {
      yield entity;
    } else if (entity is Directory &&
        !_skippedDirectories.contains(p.basename(entity.path))) {
      yield* _projectFiles(entity);
    }
  }
}

List<Check> _checkAppGroup(
  Map<String, Map<String, Object?>> plists,
  Map<String, Set<String>> appGroups,
) {
  final declaring =
      plists.entries
          .where((entry) => entry.value['BAAppGroupID'] is String)
          .toList();

  if (declaring.isEmpty) {
    return [
      const Check.fail(
        'BAAppGroupID',
        detail: 'no Info.plist under ios/ sets it',
        fix:
            'Add BAAppGroupID to the app target\'s Info.plist. Without it '
            'AssetPackManager traps rather than returning an error.',
      ),
    ];
  }

  final group = declaring.first.value['BAAppGroupID']! as String;
  final checks = <Check>[Check.pass('BAAppGroupID', detail: group)];

  final holders =
      appGroups.entries
          .where((entry) => entry.value.contains(group))
          .map((entry) => entry.key)
          .toList();

  if (holders.isEmpty) {
    checks.add(
      Check.fail(
        'App Groups capability',
        detail: 'no entitlements file grants "$group"',
        fix:
            'Add the App Groups capability to the app target and to the '
            'downloader extension, both with "$group".',
      ),
    );
  } else {
    checks.add(
      Check.pass(
        'App Groups capability',
        detail:
            '${holders.length} target'
            '${holders.length == 1 ? '' : 's'} grant "$group"',
      ),
    );
    if (holders.length == 1) {
      checks.add(
        Check.warn(
          'App group is shared',
          detail: 'only one target grants "$group"',
          fix:
              'The app and the downloader extension both need it — the '
              'extension writes packs into the container the app reads.',
        ),
      );
    }
  }

  return checks;
}

List<Check> _checkExtension(
  Map<String, Map<String, Object?>> plists,
  Map<String, Set<String>> appGroups,
) {
  final extensions =
      plists.entries.where((entry) {
        final attributes = entry.value['EXAppExtensionAttributes'];
        return attributes is Map &&
            attributes['EXExtensionPointIdentifier'] ==
                backgroundAssetsExtensionPoint;
      }).toList();

  if (extensions.isEmpty) {
    return [
      const Check.fail(
        'Downloader extension',
        detail: 'no Info.plist under ios/ declares the extension point',
        fix:
            'Add one with File > New > Target > Background Download Extension, '
            'choosing a Managed option. Without it AssetPackManager traps.',
      ),
    ];
  }

  return [
    Check.pass(
      'Downloader extension',
      detail: p.basename(p.dirname(extensions.first.key)),
    ),
  ];
}
