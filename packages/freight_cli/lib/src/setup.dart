import 'dart:io';

import 'package:path/path.dart' as p;

import 'android/asset_packs.dart';
import 'pack_config.dart';
import 'xcode/extension_target.dart';
import 'xcode/pbxproj.dart';

/// Generates the Gradle asset pack modules for the packs in [config].
///
/// Separate from the iOS half because the two need different things: iOS needs
/// nothing but the project, while Android needs to know which packs exist and
/// how each is delivered.
AssetPackModules setUpAndroid({
  required String projectRoot,
  required FreightConfig config,
}) => generateAssetPackModules(projectRoot: projectRoot, config: config);

/// What `freight setup` did.
final class SetupResult {
  const SetupResult({
    required this.target,
    required this.created,
    required this.modified,
  });

  final ExtensionTargetResult target;

  /// Files written that did not exist.
  final List<String> created;

  /// Existing files that were changed.
  final List<String> modified;
}

/// Adds a Background Assets downloader extension to a Flutter iOS project.
///
/// Handles the shape `flutter create` produces and refuses anything else. That
/// narrowness is the point: a wrong edit to project.pbxproj costs far more to
/// recover from than adding the target by hand, and Xcode's own Background
/// Download Extension template is always available as the fallback.
///
/// Running it twice changes nothing the second time.
Future<SetupResult> setUpIos({
  required String projectRoot,
  String appTargetName = 'Runner',
  String targetName = 'FreightDownloader',
  String? appGroup,
  String deploymentTarget = '26.0',
}) async {
  final iosDirectory = p.join(projectRoot, 'ios');
  final projectPath = p.join(
    iosDirectory,
    '$appTargetName.xcodeproj',
    'project.pbxproj',
  );

  if (!File(projectPath).existsSync()) {
    throw UnsupportedProjectException(
      'no Xcode project at $projectPath',
      fix:
          'Run this from the directory holding your pubspec.yaml, in a project '
          'with iOS support.',
    );
  }

  final project = await Pbxproj.read(projectPath);
  final created = <String>[];
  final modified = <String>[];

  final target = addExtensionTarget(
    project,
    appTargetName: appTargetName,
    targetName: targetName,
    appGroup: appGroup ?? 'group.${_bundleIdOf(project, appTargetName)}',
    deploymentTarget: deploymentTarget,
  );

  if (target.alreadyPresent) {
    return SetupResult(target: target, created: const [], modified: const []);
  }

  // --- The extension's files ------------------------------------------------
  final extensionDirectory = p.join(iosDirectory, targetName);
  Directory(extensionDirectory).createSync(recursive: true);

  created.addAll([
    _write(
      p.join(extensionDirectory, '$targetName.swift'),
      _extensionSource(targetName),
    ),
    _write(
      p.join(extensionDirectory, 'Info.plist'),
      _extensionInfoPlist(target.appGroup),
    ),
    _write(
      p.join(extensionDirectory, '$targetName.entitlements'),
      _entitlements(target.appGroup),
    ),
  ]);

  // --- The app's app group ---------------------------------------------------
  final appEntitlements = p.join(
    iosDirectory,
    appTargetName,
    '$appTargetName.entitlements',
  );
  if (File(appEntitlements).existsSync()) {
    if (await _addAppGroup(appEntitlements, target.appGroup)) {
      modified.add(appEntitlements);
    }
  } else {
    created.add(_write(appEntitlements, _entitlements(target.appGroup)));
  }

  // Three keys, all on the app target. Managed Background Assets refuses to
  // start without them, and it refuses by trapping rather than returning an
  // error, so a project missing one crashes on first use.
  final appInfoPlist = p.join(iosDirectory, appTargetName, 'Info.plist');
  var plistChanged = await _setPlistString(
    appInfoPlist,
    'BAAppGroupID',
    target.appGroup,
  );
  plistChanged =
      await _setPlistBool(appInfoPlist, 'BAHasManagedAssetPacks', true) ||
      plistChanged;
  // Apple hosting by default: it also turns off the info-dictionary checks
  // that a self-hosted app must otherwise satisfy in full, and self-hosting
  // needs a manifest URL this tool cannot invent.
  plistChanged =
      await _setPlistBool(appInfoPlist, 'BAUsesAppleHosting', true) ||
      plistChanged;
  if (plistChanged) modified.add(appInfoPlist);

  // --- Point the app target at its entitlements ------------------------------
  final appTargetId = project.targetNamed(appTargetName)!;
  final appTarget = project.object(appTargetId)!;
  final configurationList =
      project.object(appTarget['buildConfigurationList']! as String)!;
  for (final configurationId
      in (configurationList['buildConfigurations'] as List<Object?>)
          .cast<String>()) {
    project.setBuildSetting(
      configurationId: configurationId,
      key: 'CODE_SIGN_ENTITLEMENTS',
      value: '$appTargetName/$appTargetName.entitlements',
    );
  }

  project.save();
  modified.add(projectPath);

  return SetupResult(target: target, created: created, modified: modified);
}

String _bundleIdOf(Pbxproj project, String appTargetName) {
  final targetId = project.targetNamed(appTargetName);
  if (targetId == null) {
    throw UnsupportedProjectException('no target named "$appTargetName"');
  }
  final target = project.object(targetId)!;
  final list = project.object(target['buildConfigurationList']! as String)!;
  for (final id
      in (list['buildConfigurations'] as List<Object?>).cast<String>()) {
    final settings =
        project.object(id)?['buildSettings'] as Map<String, Object?>?;
    final bundleId = settings?['PRODUCT_BUNDLE_IDENTIFIER'];
    if (bundleId is String &&
        bundleId.isNotEmpty &&
        !bundleId.contains(r'$(')) {
      return bundleId;
    }
  }
  throw const UnsupportedProjectException(
    'the app target has no plain PRODUCT_BUNDLE_IDENTIFIER',
    fix: 'Pass --app-group explicitly, or add the extension with Xcode.',
  );
}

String _write(String path, String contents) {
  File(path).writeAsStringSync(contents);
  return path;
}

/// Sets a string key with PlistBuddy.
///
/// Targeted rather than round-tripping the file through plutil, which would
/// rewrite every line of a plist the project already owns.
Future<bool> _setPlistString(String path, String key, String value) async {
  if (!File(path).existsSync()) return false;
  final add = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    'Add :$key string $value',
    path,
  ]);
  if (add.exitCode == 0) return true;
  // Already present: leave whatever the project chose.
  return false;
}

Future<bool> _setPlistBool(String path, String key, bool value) async {
  if (!File(path).existsSync()) return false;
  final add = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    'Add :$key bool ${value ? 'true' : 'false'}',
    path,
  ]);
  return add.exitCode == 0;
}

Future<bool> _addAppGroup(String path, String group) async {
  const key = 'com.apple.security.application-groups';
  final existing = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    'Print :$key',
    path,
  ]);
  if (existing.exitCode == 0 && (existing.stdout as String).contains(group)) {
    return false;
  }
  if (existing.exitCode != 0) {
    await Process.run('/usr/libexec/PlistBuddy', [
      '-c',
      'Add :$key array',
      path,
    ]);
  }
  final added = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    'Add :$key: string $group',
    path,
  ]);
  return added.exitCode == 0;
}

String _extensionSource(String targetName) => '''
// Generated by freight.
//
// ManagedDownloaderExtension supplies a default implementation for every
// requirement, so this target needs no logic — but it must exist: without an
// embedded downloader extension, AssetPackManager traps at first use.
//
// Implement shouldDownload(_:) to skip particular packs on particular devices.

import BackgroundAssets
import ExtensionFoundation

@main
struct ${targetName}Extension: ManagedDownloaderExtension {}
''';

String _extensionInfoPlist(String appGroup) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>\$(DEVELOPMENT_LANGUAGE)</string>
\t<key>CFBundleExecutable</key>
\t<string>\$(EXECUTABLE_NAME)</string>
\t<key>CFBundleIdentifier</key>
\t<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
\t<key>CFBundleInfoDictionaryVersion</key>
\t<string>6.0</string>
\t<key>CFBundleName</key>
\t<string>\$(PRODUCT_NAME)</string>
\t<key>CFBundlePackageType</key>
\t<string>XPC!</string>
\t<key>CFBundleShortVersionString</key>
\t<string>1.0</string>
\t<key>CFBundleVersion</key>
\t<string>1</string>
\t<key>EXAppExtensionAttributes</key>
\t<dict>
\t\t<key>EXExtensionPointIdentifier</key>
\t\t<string>com.apple.background-asset-downloader-extension</string>
\t</dict>
\t<key>BAAppGroupID</key>
\t<string>$appGroup</string>
</dict>
</plist>
''';

String _entitlements(String appGroup) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>$appGroup</string>
\t</array>
</dict>
</plist>
''';
