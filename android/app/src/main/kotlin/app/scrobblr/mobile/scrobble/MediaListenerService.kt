package app.scrobblr.mobile.scrobble

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.util.Log

/**
 * The persistent notification listener that powers scrobbling.
 *
 * Holding notification access is what authorizes
 * [MediaSessionManager.getActiveSessions] — structured `MediaMetadata` from
 * every player (title/artist/album/duration), far more reliable than parsing
 * notification text, and the same events the media notification itself is
 * rendered from. The system keeps this service bound and rebinds it after
 * crashes and reboots, which keeps the background Dart pipeline alive with
 * no foreground-service notification.
 *
 * This class is deliberately a thin sensor: it diffs active sessions,
 * subscribes to per-controller callbacks, and forwards raw events to the
 * Dart side. All interpretation (per-source parsing, debounce, dedupe,
 * thresholds) happens in Dart where it is unit-testable.
 */
class MediaListenerService : NotificationListenerService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var sessionManager: MediaSessionManager? = null
    private val tracked = mutableMapOf<MediaSession.Token, TrackedController>()

    private val componentName by lazy {
        ComponentName(this, MediaListenerService::class.java)
    }

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            syncSessions(controllers.orEmpty())
        }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "notification listener connected")
        isConnected = true
        BackgroundEngineHolder.ensureStarted(applicationContext)

        val manager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        sessionManager = manager
        try {
            manager.addOnActiveSessionsChangedListener(
                sessionsListener, componentName, mainHandler
            )
            syncSessions(manager.getActiveSessions(componentName))
        } catch (e: SecurityException) {
            Log.w(TAG, "media session access denied (permission revoked?)", e)
        }
    }

    override fun onListenerDisconnected() {
        isConnected = false
        teardown()
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun teardown() {
        try {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsListener)
        } catch (_: Exception) {
        }
        sessionManager = null
        for (controller in tracked.values) controller.dispose()
        tracked.clear()
    }

    private fun syncSessions(active: List<MediaController>) {
        val activeTokens = active.map { it.sessionToken }.toSet()

        val gone = tracked.keys.filter { it !in activeTokens }
        for (token in gone) {
            tracked.remove(token)?.let {
                it.dispose()
                emitSessionEnded(it.controller)
            }
        }

        for (controller in active) {
            if (controller.sessionToken !in tracked) {
                val trackedController = TrackedController(controller)
                tracked[controller.sessionToken] = trackedController
                controller.registerCallback(trackedController, mainHandler)
                // Initial snapshot: catches sessions already mid-track.
                emitState(controller, controller.metadata, controller.playbackState)
            }
        }
    }

    private inner class TrackedController(
        val controller: MediaController,
    ) : MediaController.Callback() {

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            emitState(controller, metadata, controller.playbackState)
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            emitState(controller, controller.metadata, state)
        }

        override fun onSessionDestroyed() {
            tracked.remove(controller.sessionToken)?.dispose()
            emitSessionEnded(controller)
        }

        fun dispose() {
            try {
                controller.unregisterCallback(this)
            } catch (_: Exception) {
            }
        }
    }

    private fun sessionKey(controller: MediaController): String =
        "${controller.packageName}:${controller.sessionToken.hashCode()}"

    private fun emitSessionEnded(controller: MediaController) {
        BackgroundEngineHolder.emit(
            mapOf(
                "origin" to "session_ended",
                "package" to controller.packageName,
                "sessionKey" to sessionKey(controller),
                "playing" to false,
                "eventAtMs" to System.currentTimeMillis(),
            )
        )
    }

    private fun emitState(
        controller: MediaController,
        metadata: MediaMetadata?,
        state: PlaybackState?,
    ) {
        if (metadata == null && state == null) return
        val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        BackgroundEngineHolder.emit(
            mapOf(
                "origin" to "media_session",
                "package" to controller.packageName,
                "sessionKey" to sessionKey(controller),
                "title" to metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
                "artist" to metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST),
                "album" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
                "albumArtist" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST),
                "durationMs" to if (duration > 0) duration else null,
                "positionMs" to state?.position,
                "playing" to (state?.state == PlaybackState.STATE_PLAYING),
                "eventAtMs" to System.currentTimeMillis(),
            )
        )
    }

    companion object {
        private const val TAG = "ScrobblrMediaListener"

        /** Whether the system currently has this listener bound. Lets the
         *  activity detect the OEM "permission granted but never rebound
         *  after reinstall" state and force a fresh bind. */
        @Volatile
        var isConnected = false
            private set
    }
}
