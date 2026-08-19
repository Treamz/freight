import 'dart:io';

import 'package:path/path.dart' as p;

import 'ba_package.dart';
import 'manifest.dart';
import 'pack_config.dart';
import 'pack_planner.dart';

/// One packaged asset pack.
final class BuiltPack {
  const BuiltPack({
    required this.plan,
    required this.manifestPath,
    required this.archivePath,
  });

  final PackPlan plan;

  /// The generated manifest, kept on disk rather than in a temporary
  /// directory: when a pack contains the wrong files, this is the first thing
  /// worth looking at.
  final String manifestPath;

  final String archivePath;
}

/// The outcome of a build.
final class BuildResult {
  const BuildResult({required this.packs, this.downloadManifestPath});

  final List<BuiltPack> packs;

  /// Written only when a base URL was given, for self-hosted delivery.
  final String? downloadManifestPath;
}

/// Builds every pack in [config].
///
/// [projectRoot] is the directory `freight.yaml` lives in. Archives and
/// manifests are written under [outputDirectory].
///
/// Pass [downloadBaseUrl] to also write the download manifest a self-hosting
/// server must serve; Apple-hosted packs do not need one.
Future<BuildResult> buildPacks({
  required FreightConfig config,
  required String projectRoot,
  required String outputDirectory,
  String? downloadBaseUrl,
  BaPackage tool = const BaPackage(),
  void Function(String message) log = print,
}) async {
  // Checked before any work, so a missing or too-old Xcode is one clear line
  // rather than a failure partway through a long build.
  log('ba-package ${await tool.version()}');

  final manifestDirectory = p.join(outputDirectory, 'manifests');
  Directory(manifestDirectory).createSync(recursive: true);

  final packs = <BuiltPack>[];
  for (final packConfig in config.packs) {
    final plan = planPack(packConfig, projectRoot: projectRoot);
    final manifest = buildAssetPackManifest(packConfig, plan.files);

    final manifestPath = p.join(manifestDirectory, '${packConfig.id}.json');
    File(manifestPath).writeAsStringSync(manifest);

    final archivePath = p.join(outputDirectory, '${packConfig.id}.aar');
    await tool.package(
      manifestPath: p.absolute(manifestPath),
      outputPath: p.absolute(archivePath),
      // The pack root, which is what makes the recorded paths come out as
      // planned rather than carrying the source layout.
      workingDirectory: plan.rootDirectory,
    );

    log(
      '${packConfig.id}: ${plan.files.length} file'
      '${plan.files.length == 1 ? '' : 's'}, '
      '${_formatBytes(plan.sizeInBytes)} -> $archivePath',
    );

    packs.add(
      BuiltPack(
        plan: plan,
        manifestPath: manifestPath,
        archivePath: archivePath,
      ),
    );
  }

  String? downloadManifestPath;
  if (downloadBaseUrl != null) {
    downloadManifestPath = p.join(outputDirectory, 'download-manifest.json');
    await tool.createDownloadManifest(
      packPaths: [for (final pack in packs) p.absolute(pack.archivePath)],
      baseUrl: downloadBaseUrl,
      outputPath: p.absolute(downloadManifestPath),
    );
    log('download manifest -> $downloadManifestPath');
    log(
      'serve each archive at $downloadBaseUrl/<pack id>, with no file '
      'extension',
    );
  }

  return BuildResult(packs: packs, downloadManifestPath: downloadManifestPath);
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
