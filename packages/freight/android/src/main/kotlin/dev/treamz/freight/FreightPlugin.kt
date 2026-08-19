package dev.treamz.freight

import android.content.Context
import com.google.android.play.core.assetpacks.AssetPackManager
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import com.google.android.play.core.assetpacks.AssetPackState
import com.google.android.play.core.assetpacks.AssetPackStateUpdateListener
import com.google.android.play.core.assetpacks.model.AssetPackStatus
import com.google.android.play.core.ktx.requestFetch
import com.google.android.play.core.ktx.requestPackStates
import com.google.android.play.core.ktx.requestRemovePack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Bridges Play Asset Delivery to the same channel contract the iOS side speaks.
 *
 * The two platforms agree on more than they differ: declare a pack, let the
 * store host it, ask for it at runtime, read files by logical path. Where they
 * do not agree it is noted at the method, rather than papered over.
 */
class FreightPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var methods: MethodChannel
  private lateinit var events: EventChannel
  private lateinit var context: Context
  private lateinit var manager: AssetPackManager
  private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  private var statusHandler: StatusStreamHandler? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    manager = AssetPackManagerFactory.getInstance(context)

    methods = MethodChannel(binding.binaryMessenger, "dev.treamz.freight/methods")
    methods.setMethodCallHandler(this)

    events = EventChannel(binding.binaryMessenger, "dev.treamz.freight/status")
    statusHandler = StatusStreamHandler(manager).also(events::setStreamHandler)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
    events.setStreamHandler(null)
    statusHandler = null
    scope.cancel()
    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "allPacks" -> run(result) {
        // Play has no API for "every pack this app declares" — only for the
        // ones already on the device. A pack that has never been fetched is
        // therefore invisible here, unlike on iOS where the download manifest
        // lists them all.
        manager.packLocations.map { (id, _) ->
          mapOf(
            "id" to id,
            "downloadSize" to 0,
            "version" to 0,
            "flags" to (FLAG_DOWNLOADED or FLAG_UP_TO_DATE),
          )
        }
      }

      "packInfo" -> {
        val packId = call.argument<String>("packId") ?: return badArguments(result)
        run(result) {
          val state = stateOf(packId) ?: return@run null
          mapOf(
            "id" to packId,
            "downloadSize" to state.totalBytesToDownload(),
            "version" to 0,
            "flags" to flagsOf(state.status()),
          )
        }
      }

      "status" -> {
        val packId = call.argument<String>("packId") ?: return badArguments(result)
        run(result) {
          val state = stateOf(packId)
          mapOf(
            "packId" to packId,
            "flags" to flagsOf(state?.status() ?: AssetPackStatus.UNKNOWN),
            "version" to 0,
            "sizeBytes" to (state?.totalBytesToDownload() ?: 0L),
          )
        }
      }

      "isDownloaded" -> {
        val packId = call.argument<String>("packId") ?: return badArguments(result)
        run(result) { manager.getPackLocation(packId) != null }
      }

      "ensureDownloaded" -> {
        val packId = call.argument<String>("packId") ?: return badArguments(result)
        run(result) {
          // requireLatest has no meaning here: Play versions asset packs with
          // the app, so there is never a newer pack for the installed build.
          if (manager.getPackLocation(packId) == null) {
            manager.requestFetch(listOf(packId))
          }
          null
        }
      }

      "remove" -> {
        val packId = call.argument<String>("packId") ?: return badArguments(result)
        run(result) {
          manager.requestRemovePack(packId)
          null
        }
      }

      // Play refreshes packs when the app updates, so there is nothing to poll.
      "checkForUpdates" -> run(result) {
        mapOf("updating" to emptyList<String>(), "removed" to emptyList<String>())
      }

      "read" -> {
        val path = call.argument<String>("path") ?: return badArguments(result)
        run(result) { readBytes(path, call.argument<String>("packId")) }
      }

      "resolve" -> {
        val path = call.argument<String>("path") ?: return badArguments(result)
        run(result) {
          resolveFile(path, call.argument<String>("packId"))?.absolutePath
            ?: throw PathNotFound(path)
        }
      }

      else -> result.notImplemented()
    }
  }

  private suspend fun stateOf(packId: String): AssetPackState? =
    manager.requestPackStates(listOf(packId)).packStates()[packId]

  /**
   * Resolves a logical path across downloaded packs.
   *
   * Install-time packs are not reachable through [AssetPackManager]; their
   * files sit in the ordinary asset manager, which is why [readBytes] falls
   * back to it rather than reporting the path as missing.
   */
  private fun resolveFile(path: String, packId: String?): File? {
    val locations = if (packId == null) {
      manager.packLocations.values
    } else {
      listOfNotNull(manager.getPackLocation(packId))
    }

    for (location in locations) {
      val root = location.assetsPath() ?: continue
      val file = File(root, path)
      if (file.exists()) return file
    }
    return null
  }

  private fun readBytes(path: String, packId: String?): ByteArray {
    resolveFile(path, packId)?.let { return it.readBytes() }

    if (packId == null) {
      runCatching { context.assets.open(path).use { it.readBytes() } }
        .getOrNull()
        ?.let { return it }
    }

    throw PathNotFound(path)
  }

  private fun run(result: Result, body: suspend () -> Any?) {
    scope.launch {
      try {
        result.success(body())
      } catch (e: PathNotFound) {
        result.error("path_not_found", "No file at \"${e.path}\"", null)
      } catch (e: Exception) {
        result.error("download_failed", e.message ?: e.toString(), null)
      }
    }
  }

  private fun badArguments(result: Result) =
    result.error("bad_arguments", "Missing or malformed arguments", null)

  private class PathNotFound(val path: String) : Exception("No file at \"$path\"")
}

// MARK: - Status stream

private class StatusStreamHandler(
  private val manager: AssetPackManager,
) : EventChannel.StreamHandler {
  private var listener: AssetPackStateUpdateListener? = null

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
    val wanted = (arguments as? Map<*, *>)?.get("packId") as? String

    listener = AssetPackStateUpdateListener { state ->
      // Play has no per-pack subscription, so a stream scoped to one pack is
      // filtered here. iOS scopes natively; the Dart side cannot tell.
      if (wanted == null || state.name() == wanted) {
        sink.success(encode(state))
      }
    }.also(manager::registerListener)
  }

  override fun onCancel(arguments: Any?) {
    listener?.let(manager::unregisterListener)
    listener = null
  }

  private fun encode(state: AssetPackState): Map<String, Any?> = mapOf(
    "packId" to state.name(),
    "kind" to kindOf(state.status()),
    "flags" to flagsOf(state.status()),
    "completedBytes" to state.bytesDownloaded(),
    "totalBytes" to state.totalBytesToDownload(),
    "version" to 0,
    "sizeBytes" to state.totalBytesToDownload(),
    "error" to state.errorCode().takeIf { state.status() == AssetPackStatus.FAILED }
      ?.let { "Play Asset Delivery error $it" },
  )
}

// MARK: - Status mapping

internal const val FLAG_DOWNLOAD_AVAILABLE = 1 shl 0
internal const val FLAG_UP_TO_DATE = 1 shl 2
internal const val FLAG_DOWNLOADING = 1 shl 5
internal const val FLAG_DOWNLOADED = 1 shl 6

/** Keep in sync with `PackFlags` on the Dart side. */
internal fun flagsOf(status: Int): Int = when (status) {
  AssetPackStatus.NOT_INSTALLED, AssetPackStatus.CANCELED -> FLAG_DOWNLOAD_AVAILABLE
  AssetPackStatus.PENDING,
  AssetPackStatus.DOWNLOADING,
  AssetPackStatus.TRANSFERRING,
  -> FLAG_DOWNLOADING
  AssetPackStatus.COMPLETED -> FLAG_DOWNLOADED or FLAG_UP_TO_DATE
  // WAITING_FOR_WIFI and REQUIRES_USER_CONFIRMATION are paused, not failed:
  // the download resumes once the condition clears.
  AssetPackStatus.WAITING_FOR_WIFI,
  AssetPackStatus.REQUIRES_USER_CONFIRMATION,
  -> FLAG_DOWNLOAD_AVAILABLE
  else -> 0
}

/** Keep in sync with the event kinds `platform_channel.dart` understands. */
internal fun kindOf(status: Int): String = when (status) {
  AssetPackStatus.PENDING -> "began"
  AssetPackStatus.DOWNLOADING, AssetPackStatus.TRANSFERRING -> "downloading"
  AssetPackStatus.WAITING_FOR_WIFI,
  AssetPackStatus.REQUIRES_USER_CONFIRMATION,
  -> "paused"
  AssetPackStatus.COMPLETED -> "finished"
  AssetPackStatus.FAILED -> "failed"
  else -> "idle"
}
