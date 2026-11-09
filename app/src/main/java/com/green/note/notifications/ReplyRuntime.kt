package com.green.note.notifications

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.text.Html
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import com.green.note.AppGraph
import com.green.note.MainActivity
import com.green.note.R
import com.green.note.settings.ReplyReminderSettings
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import okio.ByteString.Companion.encodeUtf8
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ReplyRuntime(private val context: Context) {
    private val prefs = context.getSharedPreferences("greennote_compose_reply_notifications", Context.MODE_PRIVATE)
    private val manager = NotificationManagerCompat.from(context)
    fun settings() = ReplyReminderSettings(prefs.getBoolean("enabled", false), prefs.getBoolean("resident", false),
        prefs.getInt("interval", 1).takeIf { it in listOf(1,5,15,30,60) } ?: 1, prefs.getBoolean("preview", false))
    fun permitted() = manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    fun status(): String {
        val current = AppGraph.get(context).session()
        val scope = if (current.authenticated) current.effectiveCookie.encodeUtf8().sha256().hex() else ""
        return if (scope.isNotEmpty() && prefs.getString("scope", "") == scope) {
            val success = prefs.getLong("success", 0)
            (prefs.getString("status", null) ?: "尚未检查") + if (success > 0) "\n上次成功：${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(success))}" else ""
        }
        else "尚未检查；首次检查只建立基线，不提醒已有消息"
    }
    fun runtimeError(): String? = prefs.getString("runtime_error", null)
    fun recordRuntimeError(message: String?) { prefs.edit().putString("runtime_error", message).apply() }
    fun observe(onChange: () -> Unit): () -> Unit {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> onChange() }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        return { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }

    suspend fun save(next: ReplyReminderSettings) = withContext(Dispatchers.IO) {
        require(next.intervalMinutes in listOf(1,5,15,30,60))
        val previous = settings()
        val editor = prefs.edit().putBoolean("enabled", next.enabled).putBoolean("resident", next.resident)
            .putInt("interval", next.intervalMinutes).putBoolean("preview", next.showPreview).putLong("revision", maxOf(System.currentTimeMillis(), prefs.getLong("revision",0) + 1))
        if (!previous.enabled && next.enabled) editor.remove("history")
        check(editor.commit()) { "保存失败，请稍后重试" }
    }

    suspend fun configure(visible: Boolean) {
        val graph = AppGraph.get(context).also { it.initialize() }
        withContext(Dispatchers.IO) { migrateLegacy() }
        val settings = withContext(Dispatchers.IO) { settings() }
        val allowed = settings.enabled && graph.session().authenticated && permitted()
        if (!allowed || !settings.resident) context.stopService(Intent(context, ReplyResidentService::class.java))
        if (!allowed || !settings.showPreview) clearNotifications()
        val work = WorkManager.getInstance(context)
        work.cancelUniqueWork("greennote.reply-notifications")
        if (!allowed) { work.cancelUniqueWork(WORK_NAME); return }
        val request = PeriodicWorkRequestBuilder<ReplyWorker>(maxOf(15, settings.intervalMinutes).toLong(), TimeUnit.MINUTES)
            .setInitialDelay(maxOf(15, settings.intervalMinutes).toLong(), TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build()
        work.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        if (visible && settings.resident) {
            try { ContextCompat.startForegroundService(context, Intent(context, ReplyResidentService::class.java)) }
            catch (_: RuntimeException) { recordRuntimeError("常驻服务未能启动，省电检查仍已安排；可重新打开应用后重试") }
        }
    }

    suspend fun check(force: Boolean = false): String = withContext(Dispatchers.IO) {
        if (!pollMutex.tryLock()) return@withContext "正在检查回复"
        var scope = ""
        var revision = 0L
        var owner: com.green.note.network.ApiSession? = null
        val graph = AppGraph.get(context)
        fun current() = owner == graph.session() && prefs.getLong("revision", 0) == revision && settings().enabled
        val now = System.currentTimeMillis()
        try {
            graph.initialize()
            val settings = settings()
            if (!settings.enabled) return@withContext "自动检查已关闭"
            owner = graph.session()
            if (!owner.authenticated) return@withContext "请使用酷安账号登录"
            scope = owner.effectiveCookie.encodeUtf8().sha256().hex()
            revision = prefs.getLong("revision", 0)
            val failures = if (prefs.getString("scope", "") == scope) prefs.getInt("failures", 0) else 0
            val delay = minOf(60, settings.intervalMinutes * (1 shl minOf(failures, 4))) * 60000L
            if (!force && prefs.getString("scope", "") == scope && now - prefs.getLong("attempt", 0) < delay) return@withContext "等待下次检查"
            if (!permitted()) return@withContext "系统通知权限未开启"
            val items = ReplyItem.parse(graph.api.request("/v6/notification/list", query = mapOf("page" to "1")))
            if (!current()) return@withContext "会话或设置已变更，已丢弃旧检查"
            val history = runCatching { ReplyHistory.parse(JSONObject(prefs.getString("history", "{}")!!)) }.getOrDefault(ReplyHistory())
            val (next, fresh) = history.merge(scope, items)
            if (fresh.isNotEmpty()) {
                if (!permitted()) return@withContext "系统通知权限未开启"
                if (!current()) return@withContext "会话或设置已变更"
                show(scope, fresh, settings.showPreview)
            }
            if (!current()) { clearNotifications(); return@withContext "会话或设置已变更" }
            val message = if (history.scope != scope) "已建立检查基线，已有消息不会重复提醒" else if (fresh.isEmpty()) "检查成功，暂无新回复" else "已提醒 ${fresh.size} 条新回复"
            check(prefs.edit().putString("history", next.json().toString()).putString("scope", scope)
                .putLong("attempt", now).putLong("success", now).putInt("failures", 0).putString("status", message).commit())
            message
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) {
            val message = "检查失败，请确认网络正常且官方 Cookie 未过期；将自动降低检查频率"
            if (owner != null && current()) prefs.edit().putString("scope", scope).putLong("attempt", now)
                .putInt("failures", minOf(5, prefs.getInt("failures", 0) + 1)).putString("status", message).commit()
            message
        } finally { pollMutex.unlock() }
    }

    fun clearNotifications() {
        if (Build.VERSION.SDK_INT >= 23) (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .activeNotifications.filter { it.tag == TAG }.forEach { manager.cancel(TAG, it.id) }
    }
    private fun migrateLegacy() {
        if (prefs.getBoolean("flutter_imported", false)) return
        val editor = prefs.edit()
        if (!prefs.contains("enabled")) {
            val old = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            fun json(key: String) = runCatching { JSONObject(old.getString("flutter.greennote.reply_notifications.$key", "{}")!!) }.getOrDefault(JSONObject())
            val settings = json("settings")
            editor.putBoolean("enabled", settings.optBoolean("enabled"))
                .putBoolean("resident", settings.optString("mode") == "resident")
                .putBoolean("preview", settings.optBoolean("showPreview"))
                .putInt("interval", settings.optInt("intervalMinutes",1).takeIf { it in listOf(1,5,15,30,60) } ?: 1)
                .putLong("revision", settings.optLong("revision"))
                .putString("history", ReplyHistory.parse(json("history")).json().toString())
            val status = json("status")
            editor.putString("scope", status.optString("scope")).putString("status", status.optString("message", "尚未检查"))
                .putLong("success", status.optLong("lastSuccess")).putLong("attempt", status.optLong("lastAttempt"))
        }
        check(editor.putBoolean("flutter_imported", true).commit()) { "通知设置迁入失败，旧设置已保留" }
    }
    private fun show(scope: String, items: List<ReplyItem>, preview: Boolean) {
        if (!permitted()) return
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("greennote_replies_v1", "评论与回复", NotificationManager.IMPORTANCE_HIGH))
        val digest = "$scope:${items.map { it.id }.sorted().joinToString(",")}".encodeUtf8().sha256().hex()
        val id = digest.take(7).toInt(16) or 0x10000000
        val text = items.first().preview
        val intent = Intent(context, MainActivity::class.java).putExtra("reply_scope", scope).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try { manager.notify(TAG, id, NotificationCompat.Builder(context, "greennote_replies_v1").setSmallIcon(R.drawable.ic_stat_reply)
            .setContentTitle("收到 ${items.size} 条新评论或回复").setContentText(if (preview && text.isNotBlank()) text else "点按查看酷安回复消息")
            .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_HIGH).setGroup(TAG).build()) }
        catch (denied: SecurityException) { throw IllegalStateException("通知权限已改变", denied) }
    }
    companion object {
        private val pollMutex = Mutex()
        private const val TAG = "greennote_replies"
        private const val WORK_NAME = "greennote.compose.reply-notifications"
        @Volatile var visible = false
        @Volatile var residentRunning = false
    }
}

class ReplyWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (ReplyRuntime.visible || ReplyRuntime.residentRunning) return Result.success()
        ReplyRuntime(applicationContext).check()
        return Result.success()
    }
}

class ReplyResidentService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var polling: Job? = null
    private val wakeLock by lazy { (getSystemService(Context.POWER_SERVICE) as PowerManager)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GreenNote:ReplyMonitor").apply { setReferenceCounted(false) } }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val runtime = ReplyRuntime(this)
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("greennote_reply_monitor", "后台回复检查", NotificationManager.IMPORTANCE_LOW))
        startForeground(9127, NotificationCompat.Builder(this, "greennote_reply_monitor").setSmallIcon(R.drawable.ic_stat_reply)
            .setContentTitle("GreenNote 正在检查回复").setContentText("每 ${runtime.settings().intervalMinutes} 分钟检查；可在通知中心关闭").setOngoing(true).build())
        runtime.recordRuntimeError(null)
        ReplyRuntime.residentRunning = true
        if (polling == null) polling = scope.launch {
            val runtime = ReplyRuntime(this@ReplyResidentService)
            while (isActive) {
                wakeLock.acquire(120_000)
                val settings = withContext(Dispatchers.IO) { runtime.settings() }
                if (!settings.enabled || !settings.resident || !runtime.permitted()) { stopSelf(); break }
                val message = runtime.check()
                if (message == "请使用酷安账号登录") { stopSelf(); break }
                delay(60000)
            }
        }
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { ReplyRuntime(this).recordRuntimeError("常驻检查被系统限时停止，省电检查继续运行"); stopSelf() }
    override fun onDestroy() { ReplyRuntime.residentRunning = false; scope.cancel(); if (wakeLock.isHeld) wakeLock.release(); super.onDestroy() }
}
