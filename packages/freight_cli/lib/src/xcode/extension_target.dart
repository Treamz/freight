import 'pbxproj.dart';

/// Why a project could not be set up automatically.
final class UnsupportedProjectException implements Exception {
  const UnsupportedProjectException(this.message, {this.fix});

  final String message;
  final String? fix;

  @override
  String toString() => fix == null ? message : '$message\n$fix';
}

/// What adding the target changed.
final class ExtensionTargetResult {
  const ExtensionTargetResult({
    required this.targetName,
    required this.bundleId,
    required this.appGroup,
    required this.alreadyPresent,
  });

  final String targetName;
  final String bundleId;
  final String appGroup;

  /// True when the project already had a downloader extension and nothing was
  /// changed.
  final bool alreadyPresent;
}

/// Adds a Background Assets downloader extension target to [project].
///
/// Deliberately narrow. It handles the shape `flutter create` produces — one
/// app target, one configuration list — and refuses anything else rather than
/// guessing, because a wrong edit to project.pbxproj is far more expensive to
/// recover from than doing it by hand.
ExtensionTargetResult addExtensionTarget(
  Pbxproj project, {
  required String appTargetName,
  required String targetName,
  required String appGroup,
  String deploymentTarget = '26.0',
}) {
  final appTargetId = project.targetNamed(appTargetName);
  if (appTargetId == null) {
    throw UnsupportedProjectException(
      'no target named "$appTargetName" in ${project.path}',
      fix:
          'freight expects the layout flutter create produces. Add the '
          'extension with Xcode: File > New > Target > Background Download '
          'Extension.',
    );
  }

  if (project.targetNamed(targetName) != null) {
    final bundleId = _appBundleId(project, appTargetId);
    return ExtensionTargetResult(
      targetName: targetName,
      bundleId: '$bundleId.$targetName',
      appGroup: appGroup,
      alreadyPresent: true,
    );
  }

  final appTarget = project.object(appTargetId)!;
  final appBundleId = _appBundleId(project, appTargetId);
  final bundleId = '$appBundleId.$targetName';
  final configurationNames = _configurationNames(project, appTargetId);

  String id(String role) => project.generateId('$targetName.$role');

  final appexRef = id('appex');
  final swiftRef = id('swift');
  final plistRef = id('plist');
  final entitlementsRef = id('entitlements');
  final groupId = id('group');
  final swiftBuildFile = id('buildFile.swift');
  final appexBuildFile = id('buildFile.appex');
  final sourcesPhase = id('phase.sources');
  final frameworksPhase = id('phase.frameworks');
  final resourcesPhase = id('phase.resources');
  final embedPhase = id('phase.embed');
  final configurationList = id('configurationList');
  final nativeTarget = id('target');
  final proxy = id('proxy');
  final dependency = id('dependency');

  // --- File references -----------------------------------------------------
  project
    ..addObject(
      section: 'PBXFileReference',
      body:
          '\t\t$appexRef /* $targetName.appex */ = {isa = PBXFileReference; '
          'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
          'path = $targetName.appex; sourceTree = BUILT_PRODUCTS_DIR; };',
    )
    ..addObject(
      section: 'PBXFileReference',
      body:
          '\t\t$swiftRef /* $targetName.swift */ = {isa = PBXFileReference; '
          'lastKnownFileType = sourcecode.swift; path = $targetName.swift; '
          'sourceTree = "<group>"; };',
    )
    ..addObject(
      section: 'PBXFileReference',
      body:
          '\t\t$plistRef /* Info.plist */ = {isa = PBXFileReference; '
          'lastKnownFileType = text.plist.xml; path = Info.plist; '
          'sourceTree = "<group>"; };',
    )
    ..addObject(
      section: 'PBXFileReference',
      body:
          '\t\t$entitlementsRef /* $targetName.entitlements */ = '
          '{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; '
          'path = $targetName.entitlements; sourceTree = "<group>"; };',
    );

  // --- Build files ---------------------------------------------------------
  project
    ..addObject(
      section: 'PBXBuildFile',
      body:
          '\t\t$swiftBuildFile /* $targetName.swift in Sources */ = '
          '{isa = PBXBuildFile; fileRef = $swiftRef /* $targetName.swift */; };',
    )
    ..addObject(
      section: 'PBXBuildFile',
      body:
          '\t\t$appexBuildFile /* $targetName.appex in Embed Foundation '
          'Extensions */ = {isa = PBXBuildFile; fileRef = $appexRef '
          '/* $targetName.appex */; settings = {ATTRIBUTES = '
          '(RemoveHeadersOnCopy, ); }; };',
    );

  // --- Group ---------------------------------------------------------------
  project.addObject(
    section: 'PBXGroup',
    body: '''
\t\t$groupId /* $targetName */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t$swiftRef /* $targetName.swift */,
\t\t\t\t$plistRef /* Info.plist */,
\t\t\t\t$entitlementsRef /* $targetName.entitlements */,
\t\t\t);
\t\t\tpath = $targetName;
\t\t\tsourceTree = "<group>";
\t\t};''',
  );
  project.addToList(
    objectId: project.rootObject['mainGroup']! as String,
    key: 'children',
    entry: '\t\t\t\t$groupId /* $targetName */,',
  );

  // --- The extension's own build phases ------------------------------------
  project
    ..addObject(
      section: 'PBXSourcesBuildPhase',
      body: '''
\t\t$sourcesPhase /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t$swiftBuildFile /* $targetName.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};''',
    )
    ..addObject(
      section: 'PBXFrameworksBuildPhase',
      body: '''
\t\t$frameworksPhase /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};''',
    )
    ..addObject(
      section: 'PBXResourcesBuildPhase',
      body: '''
\t\t$resourcesPhase /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};''',
    );

  // --- Build configurations, mirroring the app's -----------------------------
  final configurationIds = <String, String>{};
  for (final name in configurationNames) {
    final configurationId = id('configuration.$name');
    configurationIds[name] = configurationId;
    project.addObject(
      section: 'XCBuildConfiguration',
      body: '''
\t\t$configurationId /* $name */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = $targetName/$targetName.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = $targetName/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = $deploymentTarget;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleId;
\t\t\t\tPRODUCT_NAME = "\$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = $name;
\t\t};''',
    );
  }

  project.addObject(
    section: 'XCConfigurationList',
    body: '''
\t\t$configurationList /* Build configuration list for PBXNativeTarget "$targetName" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
${configurationNames.map((n) => '\t\t\t\t${configurationIds[n]} /* $n */,').join('\n')}
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = ${configurationNames.contains('Release') ? 'Release' : configurationNames.first};
\t\t};''',
  );

  // --- The target itself ---------------------------------------------------
  project.addObject(
    section: 'PBXNativeTarget',
    body: '''
\t\t$nativeTarget /* $targetName */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = $configurationList /* Build configuration list for PBXNativeTarget "$targetName" */;
\t\t\tbuildPhases = (
\t\t\t\t$sourcesPhase /* Sources */,
\t\t\t\t$frameworksPhase /* Frameworks */,
\t\t\t\t$resourcesPhase /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = $targetName;
\t\t\tproductName = $targetName;
\t\t\tproductReference = $appexRef /* $targetName.appex */;
\t\t\tproductType = "com.apple.product-type.extensionkit-extension";
\t\t};''',
  );
  project.addToList(
    objectId: project.rootObjectId,
    key: 'targets',
    entry: '\t\t\t\t$nativeTarget /* $targetName */,',
  );

  // --- Embed it in the app -------------------------------------------------
  project.addObject(
    section: 'PBXCopyFilesBuildPhase',
    body: '''
\t\t$embedPhase /* Embed Foundation Extensions */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "\$(EXTENSIONS_FOLDER_PATH)";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = (
\t\t\t\t$appexBuildFile /* $targetName.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};''',
  );

  // The appex has to be inside the wrapper before Flutter's "Thin Binary"
  // script and the CocoaPods embed step run over it. Appended at the end, those
  // steps depend on a bundle that does not exist yet and Xcode reports a
  // dependency cycle rather than a missing file.
  final resourcesPhaseId = _phaseIdOfType(
    project,
    appTarget,
    'PBXResourcesBuildPhase',
  );
  project.addToList(
    objectId: appTargetId,
    key: 'buildPhases',
    entry: '\t\t\t\t$embedPhase /* Embed Foundation Extensions */,',
    afterEntryContaining: resourcesPhaseId,
  );

  // --- Build order ---------------------------------------------------------
  project
    ..addObject(
      section: 'PBXContainerItemProxy',
      body: '''
\t\t$proxy /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = ${project.rootObjectId} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = $nativeTarget;
\t\t\tremoteInfo = $targetName;
\t\t};''',
    )
    ..addObject(
      section: 'PBXTargetDependency',
      body: '''
\t\t$dependency /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = $nativeTarget /* $targetName */;
\t\t\ttargetProxy = $proxy /* PBXContainerItemProxy */;
\t\t};''',
    )
    ..addToList(
      objectId: appTargetId,
      key: 'dependencies',
      entry: '\t\t\t\t$dependency /* PBXTargetDependency */,',
    );

  return ExtensionTargetResult(
    targetName: targetName,
    bundleId: bundleId,
    appGroup: appGroup,
    alreadyPresent: false,
  );
}

String _appBundleId(Pbxproj project, String appTargetId) {
  for (final name in _configurationNames(project, appTargetId)) {
    final settings = _configuration(project, appTargetId, name);
    final id = settings?['PRODUCT_BUNDLE_IDENTIFIER'];
    if (id is String && id.isNotEmpty && !id.contains(r'$(')) return id;
  }
  throw const UnsupportedProjectException(
    'the app target has no plain PRODUCT_BUNDLE_IDENTIFIER',
    fix:
        'freight derives the extension\'s bundle id from the app\'s. Set one '
        'on the app target, or add the extension with Xcode.',
  );
}

List<String> _configurationNames(Pbxproj project, String targetId) {
  final target = project.object(targetId)!;
  final list = project.object(target['buildConfigurationList']! as String)!;
  final ids = (list['buildConfigurations'] as List<Object?>).cast<String>();
  return [for (final id in ids) project.object(id)!['name']! as String];
}

Map<String, Object?>? _configuration(
  Pbxproj project,
  String targetId,
  String name,
) {
  final target = project.object(targetId)!;
  final list = project.object(target['buildConfigurationList']! as String)!;
  for (final id
      in (list['buildConfigurations'] as List<Object?>).cast<String>()) {
    final configuration = project.object(id)!;
    if (configuration['name'] == name) {
      return configuration['buildSettings'] as Map<String, Object?>?;
    }
  }
  return null;
}

String _phaseIdOfType(
  Pbxproj project,
  Map<String, Object?> target,
  String isa,
) {
  for (final id in (target['buildPhases'] as List<Object?>).cast<String>()) {
    if (project.object(id)?['isa'] == isa) return id;
  }
  throw UnsupportedProjectException(
    'the app target has no $isa',
    fix: 'Add the extension with Xcode instead.',
  );
}
