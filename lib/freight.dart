/// Ship large assets outside your app bundle.
///
/// Wraps iOS Managed Background Assets and, from 0.3, Google Play Asset
/// Delivery behind one API. See `README.md` for setup and `PLAN.md` for the
/// design.
library;

export 'src/asset_pack.dart' show AssetPack;
export 'src/exceptions.dart'
    show
        DownloadFailedException,
        FreightException,
        MissingAppGroupException,
        MissingExtensionException,
        PackNotFoundException,
        PathNotFoundException,
        UnsupportedPlatformException;
export 'src/freight_base.dart' show Freight;
export 'src/freight_bundle.dart' show FreightBundle;
export 'src/freight_image.dart' show FreightImage;
export 'src/pack_status.dart'
    show
        PackDownloading,
        PackFailed,
        PackFlags,
        PackNotDownloaded,
        PackPaused,
        PackReady,
        PackStatus;
export 'src/platform_channel.dart' show PackInfo, UpdateCheck;
