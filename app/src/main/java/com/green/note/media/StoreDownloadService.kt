package com.green.note.media

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.green.note.MainActivity
import com.green.note.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal const val OPEN_DOWNLOADS = "com.green.note.action.OPEN_DOWNLOADS"

internal fun downloadManagerIntent(context: Context) = Intent(context, MainActivity::class.java)
    .setAction(OPEN_DOWNLOADS)
    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)

class StoreDownloadService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private val openDownloads by lazy {
        PendingIntent.getActivity(this, 0, downloadManagerIntent(this), PendingIntent.FLAG_IMMUTABLE)
    }
    private var worker: Job? = null
    private var current: ApkTransfer? = null
    private var latestStart = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStart = startId
        if (worker?.isActive == true) return START_NOT_STICKY
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(NotificationChannel(CHANNEL, "应用下载", NotificationManager.IMPORTANCE_LOW))
        }
        try {
            startForeground(PROGRESS, notification("正在准备应用下载", "轻触查看下载管理", ongoing = true)
                .setProgress(0, 0, true).build())
        } catch (_: RuntimeException) {
            scope.launch {
                withContext(NonCancellable) { store().pauseWaiting() }
                stopSelfResult(startId)
            }
            stopSelf()
            return START_NOT_STICKY
        }
        worker = scope.launch {
            val downloads = store()
            val initial = downloads.tasks.value.associate { it.id to it.state }
            val observe = launch {
                downloads.tasks.collect { tasks ->
                    val task = tasks.firstOrNull { it.state == StoreDownloadState.DOWNLOADING } ?: return@collect
                    val queued = tasks.count { it.state == StoreDownloadState.QUEUED }
                    val percent = if (task.total > 0) (task.bytes.toDouble() * 100 / task.total).toInt().coerceIn(0, 100) else 0
                    val progress = if (task.total > 0) "$percent%" else "正在下载"
                    val text = if (queued > 0) "$progress · $queued 项排队" else progress
                    runCatching {
                        notifications.notify(PROGRESS, notification(task.name, text, ongoing = true)
                            .setProgress(100, percent, task.total <= 0).build())
                    }
                }
            }
            try {
                while (isActive) {
                    val start = latestStart
                    val transfer = ApkTransfer()
                    current = transfer
                    val worked = downloads.runNext(transfer)
                    current = null
                    if (!worked && stopSelfResult(start)) {
                        val changed = downloads.tasks.value.filter { initial[it.id] != it.state }
                        val completed = changed.count { it.state == StoreDownloadState.COMPLETE }
                        val failed = changed.count { it.state == StoreDownloadState.FAILED }
                        if (completed + failed > 0) {
                            val summary = listOfNotNull(
                                completed.takeIf { it > 0 }?.let { "$it 项下载完成" },
                                failed.takeIf { it > 0 }?.let { "$it 项可重试" },
                            ).joinToString(" · ")
                            runCatching { notifications.notify(RESULT, notification("应用下载", summary, ongoing = false).build()) }
                        }
                        break
                    }
                }
            } finally {
                current?.cancel()
                current = null
                observe.cancel()
                if (!isActive) withContext(NonCancellable) { downloads.pauseWaiting() }
            }
        }
        return START_NOT_STICKY
    }

    private suspend fun store() = withContext(Dispatchers.IO) { StoreDownloads.get(this@StoreDownloadService) }

    private fun notification(title: String, message: String, ongoing: Boolean) =
        NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(if (ongoing) android.R.drawable.stat_sys_download else android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(message)
            .setContentIntent(openDownloads)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

    override fun onTimeout(startId: Int, fgsType: Int) {
        current?.cancel()
        scope.cancel()
        stopSelf()
    }

    override fun onDestroy() {
        current?.cancel()
        scope.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "greennote_store_downloads"
        const val PROGRESS = 5411
        const val RESULT = 5412
    }
}
