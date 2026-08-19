import 'dart:io';

import 'package:args/args.dart';
import 'package:freight_cli/src/ba_package.dart';
import 'package:freight_cli/src/builder.dart';
import 'package:freight_cli/src/doctor.dart';
import 'package:freight_cli/src/pack_config.dart';
import 'package:freight_cli/src/android/asset_packs.dart';
import 'package:freight_cli/src/pack_planner.dart';
import 'package:freight_cli/src/setup.dart';
import 'package:freight_cli/src/xcode/extension_target.dart';
import 'package:freight_cli/src/xcode/pbxproj.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser =
      ArgParser()
        ..addCommand('build', _buildParser())
        ..addCommand('doctor', _doctorParser())
        ..addCommand('setup', _setupParser())
        ..addFlag(
          'help',
          abbr: 'h',
          negatable: false,
          help: 'Print this usage information.',
        );

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    _printUsage(parser);
    exit(64);
  }

  final command = args.command;
  if (args.flag('help') || command == null) {
    _printUsage(parser);
    exit(command == null ? 64 : 0);
  }

  try {
    switch (command.name) {
      case 'build':
        await _build(command);
      case 'doctor':
        await _doctor(command);
      case 'setup':
        await _setup(command);
      default:
        _printUsage(parser);
        exit(64);
    }
  } on FreightConfigException catch (e) {
    stderr.writeln(e);
    exit(65);
  } on BaPackageException catch (e) {
    stderr.writeln(e);
    exit(70);
  } on AndroidSetupException catch (e) {
    stderr.writeln(e);
    exit(65);
  } on UnsupportedProjectException catch (e) {
    stderr.writeln(e);
    exit(65);
  } on PbxprojException catch (e) {
    stderr.writeln(e);
    exit(65);
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exit(66);
  }
}

ArgParser _buildParser() =>
    ArgParser()
      ..addOption(
        'config',
        defaultsTo: 'freight.yaml',
        help: 'The pack configuration to build.',
      )
      ..addOption(
        'output',
        defaultsTo: 'build/packs',
        help: 'Where to write archives and generated manifests.',
      )
      ..addOption(
        'platform',
        allowed: ['all', 'ios', 'android'],
        defaultsTo: 'all',
        help:
            'Which platforms to build for. "all" does whichever the project '
            'has.',
      )
      ..addOption(
        'base-url',
        help:
            'Also write a download manifest for self-hosting, with pack URLs '
            'under this base. Omit for Apple-hosted packs.',
      );

ArgParser _setupParser() =>
    ArgParser()
      ..addOption(
        'target',
        defaultsTo: 'FreightDownloader',
        help: 'Name for the generated downloader extension target.',
      )
      ..addOption(
        'app-target',
        defaultsTo: 'Runner',
        help: 'The app target to embed the extension in.',
      )
      ..addOption(
        'app-group',
        help: 'App group id. Defaults to "group." plus the app\'s bundle id.',
      )
      ..addOption(
        'config',
        defaultsTo: 'freight.yaml',
        help: 'Pack configuration, used to generate the Android modules.',
      );

Future<void> _setup(ArgResults args) async {
  final projectRoot = Directory.current.path;

  if (_has(projectRoot, 'ios')) {
    final result = await setUpIos(
      projectRoot: projectRoot,
      appTargetName: args.option('app-target')!,
      targetName: args.option('target')!,
      appGroup: args.option('app-group'),
    );

    if (result.target.alreadyPresent) {
      stdout.writeln(
        'iOS: the project already has a "${result.target.targetName}" target.',
      );
    } else {
      for (final path in result.created) {
        stdout.writeln('created  $path');
      }
      for (final path in result.modified) {
        stdout.writeln('modified $path');
      }
      stdout
        ..writeln()
        ..writeln(
          'iOS: added the "${result.target.targetName}" extension target',
        )
        ..writeln('  bundle id: ${result.target.bundleId}')
        ..writeln('  app group: ${result.target.appGroup}')
        ..writeln();
    }
  }

  if (_has(projectRoot, 'android')) {
    final configFile = File(args.option('config')!);
    if (!configFile.existsSync()) {
      // Unlike iOS, the Android modules cannot be generated without knowing
      // which packs exist and how each is delivered.
      stdout.writeln(
        'Android: skipped, no ${args.option('config')}. Declare your packs and '
        'run setup again.',
      );
    } else {
      final modules = setUpAndroid(
        projectRoot: projectRoot,
        config: FreightConfig.parse(configFile.readAsStringSync()),
      );
      for (final path in modules.created) {
        stdout.writeln('created  $path');
      }
      for (final path in modules.modified) {
        stdout.writeln('modified $path');
      }
      if (modules.created.isEmpty && modules.modified.isEmpty) {
        stdout.writeln('Android: asset pack modules already wired up.');
      } else {
        stdout
          ..writeln()
          ..writeln('Android: generated the asset pack modules');
      }
    }
  }

  stdout
    ..writeln()
    ..writeln('Run "freight doctor" to check the result.');
}

ArgParser _doctorParser() =>
    ArgParser()..addOption(
      'config',
      defaultsTo: 'freight.yaml',
      help: 'The pack configuration to check.',
    );

Future<void> _doctor(ArgResults args) async {
  final checks = await runDoctor(
    projectRoot: Directory.current.path,
    configPath: args.option('config')!,
  );

  for (final check in checks) {
    final marker = switch (check.status) {
      CheckStatus.pass => '[ok]',
      CheckStatus.warn => '[warn]',
      CheckStatus.fail => '[fail]',
    };
    final sink = check.status == CheckStatus.fail ? stderr : stdout;
    sink.writeln(
      '$marker ${check.title}'
      '${check.detail == null ? '' : ': ${check.detail}'}',
    );
    if (check.fix case final fix?) sink.writeln('       $fix');
  }

  final failures = checks.where((c) => c.status == CheckStatus.fail).length;
  if (failures > 0) {
    stderr.writeln();
    stderr.writeln(
      '$failures check${failures == 1 ? '' : 's'} failed. Each of these fails '
      'at runtime on a device, mostly by crashing rather than throwing.',
    );
    exit(1);
  }
}

Future<void> _build(ArgResults args) async {
  final configPath = args.option('config')!;
  final file = File(configPath);
  if (!file.existsSync()) {
    stderr.writeln('No configuration at "$configPath".');
    exit(66);
  }

  final config = FreightConfig.parse(file.readAsStringSync());
  // A pack's root is relative to the configuration, not to wherever the command
  // happened to be run from.
  final projectRoot = p.dirname(p.absolute(configPath));
  final platform = args.option('platform')!;

  final wantsIos =
      platform == 'ios' || (platform == 'all' && _has(projectRoot, 'ios'));
  final wantsAndroid =
      platform == 'android' ||
      (platform == 'all' && _has(projectRoot, 'android'));

  if (!wantsIos && !wantsAndroid) {
    stderr.writeln(
      'Nothing to build: the project has neither an ios/ nor an android/ '
      'directory. Pass --platform to force one.',
    );
    exit(66);
  }

  if (wantsIos) {
    await buildPacks(
      config: config,
      projectRoot: projectRoot,
      outputDirectory: args.option('output')!,
      downloadBaseUrl: args.option('base-url'),
    );
  }

  if (wantsAndroid) {
    // Play reads assets only from the module's src/main/assets, so the files
    // are staged there under the same logical paths the iOS archive records.
    final plans = [
      for (final pack in config.packs) planPack(pack, projectRoot: projectRoot),
    ];
    for (final plan in plans) {
      if (plan.files.isEmpty) {
        throw FreightConfigException(
          'matched no files, so it would ship empty',
          pack: plan.config.id,
        );
      }
    }
    for (final staged in stageAssetPacks(
      projectRoot: projectRoot,
      plans: plans,
    )) {
      stdout.writeln('staged   $staged');
    }
  }
}

bool _has(String projectRoot, String directory) =>
    Directory(p.join(projectRoot, directory)).existsSync();

void _printUsage(ArgParser parser) {
  stdout
    ..writeln('Build asset packs declared in freight.yaml.')
    ..writeln()
    ..writeln('Usage: dart run freight <command> [options]')
    ..writeln()
    ..writeln('Commands:')
    ..writeln('  build   Package every asset pack in the configuration.')
    ..writeln('  doctor  Check the configuration and the iOS project setup.')
    ..writeln(
      '  setup   Add the downloader extension target to the iOS project.',
    )
    ..writeln()
    ..writeln('Options for "build":')
    ..writeln(parser.commands['build']!.usage)
    ..writeln()
    ..writeln('Global options:')
    ..writeln(parser.usage);
}
