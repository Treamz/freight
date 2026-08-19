/// Build-time tooling for the `freight` package.
///
/// Kept separate from `freight` itself so an app depending on the plugin does
/// not carry a YAML parser, a glob matcher and an argument parser it never
/// runs. Nothing here imports the plugin — the two share a file format, not
/// code.
library;

export 'src/ba_package.dart' show BaPackage, BaPackageException, ProcessRunner;
export 'src/builder.dart' show BuildResult, BuiltPack, buildPacks;
export 'src/doctor.dart'
    show
        Check,
        CheckStatus,
        PlistReader,
        backgroundAssetsExtensionPoint,
        runDoctor;
export 'src/manifest.dart' show buildAssetPackManifest;
export 'src/pack_config.dart'
    show
        DeliveryPolicy,
        FreightConfig,
        FreightConfigException,
        InstallationEvent,
        PackConfig;
export 'src/pack_planner.dart' show PackPlan, planPack;
