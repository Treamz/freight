import 'dart:io';

/// Runs a subprocess. Injectable so argument construction can be tested
/// without Xcode, which is where the mistakes actually live — a wrong working
/// directory silently changes every logical path in the pack.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

/// A failure from Apple's `ba-package` tool, or from not finding it.
final class BaPackageException implements Exception {
  const BaPackageException(this.message, {this.details});

  final String message;

  /// The tool's own output, when it produced any.
  final String? details;

  @override
  String toString() =>
      details == null || details!.trim().isEmpty
          ? 'ba-package: $message'
          : 'ba-package: $message\n${details!.trim()}';
}

/// Apple's asset-pack packaging tool, shipped inside Xcode.
///
/// Reached through `xcrun` rather than an absolute path so it follows whichever
/// Xcode is selected.
final class BaPackage {
  const BaPackage({ProcessRunner runner = _runProcess}) : _run = runner;

  final ProcessRunner _run;

  static const _xcrun = 'xcrun';

  /// Checks the tool is reachable, returning its version.
  ///
  /// Called before doing any work so a missing or too-old Xcode is reported as
  /// one clear line rather than as a packaging failure halfway through.
  Future<String> version() async {
    final ProcessResult result;
    try {
      result = await _run(_xcrun, ['ba-package', '--version']);
    } on ProcessException catch (e) {
      throw BaPackageException(
        'could not be run. It ships with Xcode 26 and later; '
        'check that Xcode is installed and selected',
        details: e.message,
      );
    }

    if (result.exitCode != 0) {
      throw BaPackageException(
        'was not found. It ships with Xcode 26 and later. If Xcode is '
        'installed, "sudo xcode-select -s /Applications/Xcode.app/Contents/'
        'Developer" may be needed',
        details: '${result.stdout}${result.stderr}',
      );
    }

    return (result.stdout as String).trim();
  }

  /// Packages one asset pack.
  ///
  /// [workingDirectory] must be the pack's root: `ba-package` resolves the
  /// manifest's file selectors against it, and the paths it records are the
  /// logical paths the app reads back.
  Future<void> package({
    required String manifestPath,
    required String outputPath,
    required String workingDirectory,
  }) async {
    if (!outputPath.endsWith('.aar')) {
      throw BaPackageException(
        'requires an output path ending in ".aar" (got "$outputPath")',
      );
    }

    await _expectSuccess(
      ['ba-package', 'package', manifestPath, '--output-path', outputPath],
      workingDirectory: workingDirectory,
      what: 'failed to package "$manifestPath"',
    );
  }

  /// Writes the download manifest a self-hosting server must serve.
  ///
  /// Each pack's URL becomes [baseUrl] plus the pack id, with no file
  /// extension, so the server serves the archive at `/<base>/<id>`.
  Future<void> createDownloadManifest({
    required List<String> packPaths,
    required String baseUrl,
    required String outputPath,
    List<String> platforms = const ['ios'],
  }) async {
    if (packPaths.isEmpty) {
      throw const BaPackageException(
        'cannot build a download manifest with no packs',
      );
    }

    await _expectSuccess([
      'ba-package',
      'download-manifest',
      'create',
      ...packPaths,
      for (final platform in platforms) '--$platform',
      '--download-base-url',
      baseUrl,
      '--output-path',
      outputPath,
    ], what: 'failed to build the download manifest');
  }

  Future<void> _expectSuccess(
    List<String> arguments, {
    required String what,
    String? workingDirectory,
  }) async {
    final ProcessResult result;
    try {
      result = await _run(
        _xcrun,
        arguments,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (e) {
      throw BaPackageException(what, details: e.message);
    }

    if (result.exitCode != 0) {
      throw BaPackageException(
        what,
        details: '${result.stdout}${result.stderr}',
      );
    }
  }
}
