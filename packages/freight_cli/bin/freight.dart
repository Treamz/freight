import 'dart:io';

import 'package:args/args.dart';
import 'package:freight_cli/src/ba_package.dart';
import 'package:freight_cli/src/builder.dart';
import 'package:freight_cli/src/doctor.dart';
import 'package:freight_cli/src/pack_config.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser =
      ArgParser()
        ..addCommand('build', _buildParser())
        ..addCommand('doctor', _doctorParser())
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
        'base-url',
        help:
            'Also write a download manifest for self-hosting, with pack URLs '
            'under this base. Omit for Apple-hosted packs.',
      );

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

  await buildPacks(
    config: config,
    // A pack's root is relative to the configuration, not to wherever the
    // command happened to be run from.
    projectRoot: p.dirname(p.absolute(configPath)),
    outputDirectory: args.option('output')!,
    downloadBaseUrl: args.option('base-url'),
  );
}

void _printUsage(ArgParser parser) {
  stdout
    ..writeln('Build asset packs declared in freight.yaml.')
    ..writeln()
    ..writeln('Usage: dart run freight <command> [options]')
    ..writeln()
    ..writeln('Commands:')
    ..writeln('  build   Package every asset pack in the configuration.')
    ..writeln('  doctor  Check the configuration and the iOS project setup.')
    ..writeln()
    ..writeln('Options for "build":')
    ..writeln(parser.commands['build']!.usage)
    ..writeln()
    ..writeln('Global options:')
    ..writeln(parser.usage);
}
