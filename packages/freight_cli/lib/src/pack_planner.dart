import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'pack_config.dart';

/// A pack with its source files resolved.
final class PackPlan {
  const PackPlan({
    required this.config,
    required this.rootDirectory,
    required this.files,
  });

  final PackConfig config;

  /// The absolute directory `ba-package` must run in.
  final String rootDirectory;

  /// Logical paths relative to [rootDirectory], sorted.
  ///
  /// These are exactly the paths the app reads back through `Freight.read`.
  final List<String> files;

  /// Total size on disk of [files].
  int get sizeInBytes => files.fold(
    0,
    (total, file) => total + File(p.join(rootDirectory, file)).lengthSync(),
  );
}

/// Resolves a pack's globs against the filesystem.
///
/// [projectRoot] is the directory `freight.yaml` lives in; a pack's `root` is
/// relative to it.
PackPlan planPack(PackConfig pack, {required String projectRoot}) {
  final rootDirectory = p.normalize(p.join(projectRoot, pack.root));

  if (!Directory(rootDirectory).existsSync()) {
    throw FreightConfigException(
      'root "${pack.root}" does not exist (looked in $rootDirectory)',
      pack: pack.id,
    );
  }

  final matched = <String>{};
  for (final pattern in pack.files) {
    matched.addAll(_expand(pattern, rootDirectory));
  }
  for (final pattern in pack.exclude) {
    matched.removeAll(_expand(pattern, rootDirectory));
  }

  // Sorted so an unchanged pack produces a byte-identical manifest, which is
  // what lets a build skip repackaging.
  final files = matched.toList()..sort();

  return PackPlan(config: pack, rootDirectory: rootDirectory, files: files);
}

Iterable<String> _expand(String pattern, String rootDirectory) {
  return Glob(pattern)
      .listSync(root: rootDirectory, followLinks: false)
      .whereType<File>()
      // POSIX separators: these become logical paths inside the archive, and
      // the app reads them back with the same spelling on every platform.
      .map(
        (file) => p.posix.joinAll(
          p.split(p.relative(file.path, from: rootDirectory)),
        ),
      );
}
