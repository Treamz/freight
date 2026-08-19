import Flutter
import Foundation

#if canImport(BackgroundAssets)
  import BackgroundAssets
#endif
#if canImport(System)
  import System
#endif

/// Bridges Managed Background Assets (iOS 26+) to the Dart side.
///
/// Everything touching `AssetPackManager` is gated on iOS 26; below that the
/// plugin answers `unsupported_os` so an app can depend on `freight` without
/// raising its own deployment target.
public class FreightPlugin: NSObject, FlutterPlugin {
  /// `AssetPackManager.shared` traps — it does not throw — when the host app's
  /// Info.plist has no `BAAppGroupID`. Every entry point checks this first so a
  /// misconfigured app gets an error it can read instead of a crash.
  static var appGroupID: String? {
    Bundle.main.object(forInfoDictionaryKey: "BAAppGroupID") as? String
  }

  /// `AssetPackManager.shared` also traps when the app embeds no Background
  /// Assets downloader extension. Managed Background Assets removes the need to
  /// *write* one, but the target must still exist and ship inside the app.
  static var hasDownloaderExtension: Bool {
    // ExtensionKit extensions are embedded in Extensions/, not the PlugIns/
    // directory `builtInPlugInsURL` points at. Both are searched so a host app
    // built either way is recognised.
    let roots = [
      Bundle.main.bundleURL.appendingPathComponent("Extensions"),
      Bundle.main.builtInPlugInsURL,
    ].compactMap { $0 }

    return roots.contains { root in
      let entries =
        (try? FileManager.default.contentsOfDirectory(
          at: root,
          includingPropertiesForKeys: nil
        )) ?? []

      return entries.contains { url in
        guard url.pathExtension == "appex",
          let bundle = Bundle(url: url),
          let attributes = bundle.object(forInfoDictionaryKey: "EXAppExtensionAttributes")
            as? [String: Any],
          let point = attributes["EXExtensionPointIdentifier"] as? String
        else { return false }
        return point == "com.apple.background-asset-downloader-extension"
      }
    }
  }

  /// The reason this app cannot talk to Managed Background Assets, if any.
  ///
  /// Both conditions below crash the process rather than throwing, so they are
  /// checked before `AssetPackManager` is ever touched.
  static var configurationError: FreightError? {
    if appGroupID == nil { return .missingAppGroup }
    if !hasDownloaderExtension { return .missingExtension }
    return nil
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methods = FlutterMethodChannel(
      name: "dev.treamz.freight/methods",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(FreightPlugin(), channel: methods)

    let events = FlutterEventChannel(
      name: "dev.treamz.freight/status",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(FreightStatusStreamHandler())
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 26, *) else {
      result(FreightError.unsupportedOS.asFlutterError)
      return
    }
    if let problem = FreightPlugin.configurationError {
      result(problem.asFlutterError)
      return
    }

    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "allPacks":
      run(result) {
        let packs = try await AssetPackManager.shared.allAssetPacks
        var encoded: [[String: Any]] = []
        for pack in packs {
          encoded.append(await FreightCodec.encode(pack))
        }
        return encoded
      }

    case "packInfo":
      guard let packId = args["packId"] as? String else { return badArgs(result) }
      run(result) {
        // An unknown id is a legitimate answer here, not an error: callers use
        // this precisely to find out whether a pack exists.
        guard let pack = try? await AssetPackManager.shared.assetPack(withID: packId)
        else { return nil }
        return await FreightCodec.encode(pack)
      }

    case "status":
      guard let packId = args["packId"] as? String else { return badArgs(result) }
      run(result) {
        let flags = await FreightCodec.flagBits(forPackWithID: packId)
        var payload: [String: Any] = ["packId": packId, "flags": flags]
        if let pack = try? await AssetPackManager.shared.assetPack(withID: packId) {
          payload["version"] = pack.version
          payload["sizeBytes"] = pack.downloadSize
        }
        return payload
      }

    case "isDownloaded":
      guard let packId = args["packId"] as? String else { return badArgs(result) }
      run(result) {
        if #available(iOS 26.4, *) {
          return AssetPackManager.shared.assetPackIsAvailableLocally(withID: packId)
        }
        let status = try? await AssetPackManager.shared.status(ofAssetPackWithID: packId)
        return status?.contains(.downloaded) ?? false
      }

    case "ensureDownloaded":
      guard let packId = args["packId"] as? String else { return badArgs(result) }
      let requireLatest = args["requireLatest"] as? Bool ?? false
      run(result) {
        let pack = try await AssetPackManager.shared.assetPack(withID: packId)
        if #available(iOS 26.4, *) {
          try await AssetPackManager.shared.ensureLocalAvailability(
            of: pack,
            requireLatestVersion: requireLatest
          )
        } else {
          try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
        }
        return nil
      }

    case "remove":
      guard let packId = args["packId"] as? String else { return badArgs(result) }
      run(result) {
        try await AssetPackManager.shared.remove(assetPackWithID: packId)
        return nil
      }

    case "checkForUpdates":
      run(result) {
        let (updating, removed) = try await AssetPackManager.shared.checkForUpdates()
        return ["updating": Array(updating), "removed": Array(removed)]
      }

    case "read":
      guard let path = args["path"] as? String else { return badArgs(result) }
      let packId = args["packId"] as? String
      run(result) {
        let data = try AssetPackManager.shared.contents(
          at: FilePath(path),
          searchingInAssetPackWithID: packId
        )
        return FlutterStandardTypedData(bytes: data)
      }

    case "resolve":
      guard let path = args["path"] as? String else { return badArgs(result) }
      run(result) {
        // `url(for:)` searches every downloaded pack and takes no pack scope,
        // so `packId` cannot narrow it. Reads that must be scoped use `read`.
        return try AssetPackManager.shared.url(for: FilePath(path)).path
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Runs an async body and delivers its outcome on the platform thread.
  private func run(
    _ result: @escaping FlutterResult,
    _ body: @escaping () async throws -> Any?
  ) {
    Task {
      do {
        let value = try await body()
        await MainActor.run { result(value) }
      } catch {
        await MainActor.run { result(FreightError.from(error).asFlutterError) }
      }
    }
  }

  private func badArgs(_ result: @escaping FlutterResult) {
    result(
      FlutterError(
        code: "bad_arguments",
        message: "Missing or malformed arguments",
        details: nil
      )
    )
  }
}

// MARK: - Status stream

/// Forwards `AssetPackManager` status updates to Dart.
///
/// The system downloads and evicts packs on its own schedule, so this streams
/// whether or not the app asked for anything.
class FreightStatusStreamHandler: NSObject, FlutterStreamHandler {
  private var task: Task<Void, Never>?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard #available(iOS 26, *) else {
      return FreightError.unsupportedOS.asFlutterError
    }
    if let problem = FreightPlugin.configurationError {
      return problem.asFlutterError
    }

    let packId = (arguments as? [String: Any])?["packId"] as? String

    task = Task {
      // Scoping natively keeps an app watching one pack from waking on every
      // other pack's progress.
      if let packId {
        let updates = AssetPackManager.shared.statusUpdates(forAssetPackWithID: packId)
        for await update in updates {
          await Self.emit(update, to: events)
        }
      } else {
        let updates = await AssetPackManager.shared.statusUpdates
        for await update in updates {
          await Self.emit(update, to: events)
        }
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    task?.cancel()
    task = nil
    return nil
  }

  @available(iOS 26, *)
  private static func emit(
    _ update: AssetPackManager.DownloadStatusUpdate,
    to events: @escaping FlutterEventSink
  ) async {
    let payload = await FreightCodec.encode(update)
    await MainActor.run { events(payload) }
  }
}

// MARK: - Encoding

@available(iOS 26, *)
enum FreightCodec {
  /// Apple's `AssetPack.Status` raw values are not API, so they are remapped
  /// onto bits the Dart side owns. Keep in sync with `PackFlags`.
  static func flagBits(_ status: AssetPack.Status) -> Int {
    var bits = 0
    if status.contains(.downloadAvailable) { bits |= 1 << 0 }
    if status.contains(.updateAvailable) { bits |= 1 << 1 }
    if status.contains(.upToDate) { bits |= 1 << 2 }
    if status.contains(.outOfDate) { bits |= 1 << 3 }
    if status.contains(.obsolete) { bits |= 1 << 4 }
    if status.contains(.downloading) { bits |= 1 << 5 }
    if status.contains(.downloaded) { bits |= 1 << 6 }
    return bits
  }

  static func flagBits(forPackWithID packId: String) async -> Int {
    if #available(iOS 26.4, *) {
      return flagBits(await AssetPackManager.shared.localStatus(ofAssetPackWithID: packId))
    }
    guard let status = try? await AssetPackManager.shared.status(ofAssetPackWithID: packId)
    else { return 0 }
    return flagBits(status)
  }

  static func encode(_ pack: AssetPack) async -> [String: Any] {
    return [
      "id": pack.id,
      "downloadSize": pack.downloadSize,
      "version": pack.version,
      "flags": await flagBits(forPackWithID: pack.id),
    ]
  }

  static func encode(_ update: AssetPackManager.DownloadStatusUpdate) async -> [String: Any] {
    switch update {
    case .began(let pack):
      return await base(pack, kind: "began")
    case .paused(let pack):
      return await base(pack, kind: "paused")
    case .downloading(let pack, let progress):
      var payload = await base(pack, kind: "downloading")
      payload["completedBytes"] = progress.completedUnitCount
      payload["totalBytes"] =
        progress.totalUnitCount > 0 ? progress.totalUnitCount : Int64(pack.downloadSize)
      return payload
    case .finished(let pack):
      return await base(pack, kind: "finished")
    case .failed(let pack, let error):
      var payload = await base(pack, kind: "failed")
      payload["error"] = error.localizedDescription
      return payload
    @unknown default:
      return ["packId": "", "kind": "idle", "flags": 0]
    }
  }

  private static func base(_ pack: AssetPack, kind: String) async -> [String: Any] {
    return [
      "packId": pack.id,
      "kind": kind,
      "flags": await flagBits(forPackWithID: pack.id),
      "version": pack.version,
      "sizeBytes": pack.downloadSize,
    ]
  }
}

// MARK: - Errors

/// Maps native failures onto the codes `platform_channel.dart` translates.
enum FreightError {
  case packNotFound(String)
  case pathNotFound(String)
  case downloadFailed(String)
  case unsupportedOS
  case missingAppGroup
  case missingExtension

  static func from(_ error: Error) -> FreightError {
    if #available(iOS 26, *), let managed = error as? ManagedBackgroundAssetsError {
      switch managed {
      case .assetPackNotFound(let id):
        return .packNotFound(id)
      case .fileNotFound(let path):
        return .pathNotFound(path.string)
      @unknown default:
        break
      }
    }
    return .downloadFailed(error.localizedDescription)
  }

  var asFlutterError: FlutterError {
    switch self {
    case .packNotFound(let id):
      return FlutterError(
        code: "pack_not_found",
        message: "No asset pack with id \"\(id)\"",
        details: nil
      )
    case .pathNotFound(let path):
      return FlutterError(
        code: "path_not_found",
        message: "No file at \"\(path)\" in any downloaded asset pack",
        details: nil
      )
    case .downloadFailed(let reason):
      return FlutterError(code: "download_failed", message: reason, details: nil)
    case .unsupportedOS:
      return FlutterError(
        code: "unsupported_os",
        message: "Managed Background Assets requires iOS 26.0 or newer",
        details: nil
      )
    case .missingAppGroup:
      return FlutterError(
        code: "missing_app_group",
        message: """
          Info.plist has no BAAppGroupID. Managed Background Assets stores packs \
          in an app group container, and reading one without it crashes the \
          process. Add the App Groups capability and set BAAppGroupID to the \
          group id, for example group.com.example.app.
          """,
        details: nil
      )
    case .missingExtension:
      return FlutterError(
        code: "missing_extension",
        message: """
          This app embeds no Background Assets downloader extension. Managed \
          Background Assets removes the need to write one, but the target must \
          still exist: add an app extension whose principal type conforms to \
          ManagedDownloaderExtension and embed it in the app.
          """,
        details: nil
      )
    }
  }
}
