package fm.newfm.mobile.scrobble

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.ArrayDeque

/**
 * Owns the headless FlutterEngine that runs the Dart scrobble pipeline
 * (`scrobbleServiceMain`), independent of any Activity. Started by
 * [MediaListenerService] when the system binds the notification listener,
 * so the pipeline exists even if the UI has never been opened.
 *
 * Player events that arrive while the engine is still booting are buffered
 * and flushed once Dart calls `ready` (which also hands Dart its init args).
 */
object BackgroundEngineHolder {
    private const val TAG = "NewfmBgEngine"
    private const val ENGINE_ID = "newfm_scrobble_engine"
    private const val CHANNEL = "newfm/scrobble/background"
    private const val ENTRYPOINT = "scrobbleServiceMain"
    private const val BUFFER_CAP = 200

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var dartReady = false
    private val buffered = ArrayDeque<Map<String, Any?>>()

    fun ensureStarted(context: Context) {
        val appContext = context.applicationContext
        runOnMain {
            if (FlutterEngineCache.getInstance().contains(ENGINE_ID)) return@runOnMain
            Log.i(TAG, "starting background scrobble engine")

            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(appContext)
                loader.ensureInitializationComplete(appContext, null)
            }

            val engine = FlutterEngine(appContext)
            // Manual creation means manual plugin registration
            // (secure storage + shared prefs are used by the pipeline).
            GeneratedPluginRegistrant.registerWith(engine)

            channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ready" -> {
                            dartReady = true
                            result.success(mapOf("filesDir" to appContext.filesDir.absolutePath))
                            flushBuffered()
                        }
                        "nowPlayingNotification" -> {
                            val args = call.arguments as? Map<*, *>
                            val title = args?.get("title") as? String
                            val artist = args?.get("artist") as? String
                            if (title != null && artist != null) {
                                NowPlayingNotification.show(
                                    appContext, title, artist, args["album"] as? String
                                )
                            }
                            result.success(null)
                        }
                        "clearNowPlayingNotification" -> {
                            NowPlayingNotification.clear(appContext)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }

            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT)
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        }
    }

    /** Forwards a player event to Dart, buffering while the engine boots. */
    fun emit(event: Map<String, Any?>) {
        runOnMain {
            val ch = channel
            if (dartReady && ch != null) {
                ch.invokeMethod("playerEvent", event)
            } else {
                if (buffered.size >= BUFFER_CAP) buffered.pollFirst()
                buffered.addLast(event)
            }
        }
    }

    private fun flushBuffered() {
        val ch = channel ?: return
        while (buffered.isNotEmpty()) {
            ch.invokeMethod("playerEvent", buffered.pollFirst())
        }
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }
}
