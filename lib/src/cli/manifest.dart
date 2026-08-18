import 'dart:convert';

import 'pack_config.dart';

/// Builds the asset-pack manifest `ba-package` consumes.
///
/// [files] are logical paths relative to the pack's root, in the order they
/// should appear. They are emitted as explicit `file` selectors rather than a
/// `directory` selector on purpose: `ba-package` records each path relative to
/// the directory it is invoked from, so a directory selector bakes the source
/// layout into the logical paths the app later reads back — and a selector of
/// `"."` fails outright. Explicit selectors, packaged with the pack root as the
/// working directory, give exactly the paths declared here.
String buildAssetPackManifest(PackConfig pack, List<String> files) {
  if (files.isEmpty) {
    throw FreightConfigException(
      'matched no files. An empty pack builds and publishes cleanly, then '
      'fails at runtime as a missing asset, so it is rejected here',
      pack: pack.id,
    );
  }

  return const JsonEncoder.withIndent('  ').convert({
    'assetPackID': pack.id,
    'downloadPolicy': _downloadPolicy(pack),
    'fileSelectors': [
      for (final file in files) {'file': file},
    ],
    'platforms': pack.platforms,
  });
}

Map<String, Object?> _downloadPolicy(PackConfig pack) {
  if (!pack.delivery.isAutomatic) {
    // The tool requires an empty object here, not null and not a list.
    return {pack.delivery.name: <String, Object?>{}};
  }

  // Emitted in declaration order rather than set order so the manifest is
  // reproducible; an unstable manifest would repackage identical content.
  final ordered = InstallationEvent.values
      .where(pack.events.contains)
      .map((event) => event.name)
      .toList(growable: false);

  return {
    pack.delivery.name: {'installationEventTypes': ordered},
  };
}
