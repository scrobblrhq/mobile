package fm.newfm.mobile.scrobble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context

/**
 * Silent, persistent "now playing" notification mirroring the track the
 * background pipeline is currently tracking. Posted/cleared by the Dart
 * side over the background channel; IMPORTANCE_LOW keeps it soundless and
 * un-intrusive. A timeout guards against a zombie ongoing notification if
 * the process is killed before playback ends.
 */
object NowPlayingNotification {
    private const val CHANNEL_ID = "now_playing"
    private const val NOTIFICATION_ID = 1001
    private const val TIMEOUT_MS = 45L * 60L * 1000L

    fun show(context: Context, title: String, artist: String, album: String?) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Now playing",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows the track currently being scrobbled"
                setShowBadge(false)
            }
        )

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(if (album.isNullOrEmpty()) artist else "$artist · $album")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setTimeoutAfter(TIMEOUT_MS)
            .build()

        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted; playback tracking continues.
        }
    }

    fun clear(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
    }
}
