package com.green.note.media

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.green.note.content.ContentApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CancellationException

internal enum class StoreDownloadState { QUEUED, DOWNLOADING, PAUSED, COMPLETE, FAILED }

internal data class StoreDownloadSource(val packageName: String, val appId: String, val versionCode: String) {
    val canResolve get() = packageName.isNotBlank() && appId.isNotBlank() && versionCode.isNotBlank()
    suspend fun resolve(api: ContentApi) = api.resolveApkDownloadUrl(packageName, appId, versionCode)
}

internal data class StoreDownload(
    val id: String,
    val name: String,
    val url: String,
    val source: StoreDownloadSource,
    val state: StoreDownloadState = StoreDownloadState.QUEUED,
    val bytes: Long = 0,
    val total: Long = -1,
    val speed: Long = 0,
    val version: String = "",
    val error: String = "",
    val renewUrl: Boolean = false,
)

internal fun checkedStoreUrl(value: String) = value.toHttpUrlOrNull()
    ?.takeIf { it.isHttps && it.username.isEmpty() && it.password.isEmpty() }
    ?: throw IllegalArgumentException("下载地址无效")

internal class StoreDownloads(private val app: Context) {
    private val prefs = app.getSharedPreferences("greennote.compose.store_downloads", Context.MODE_PRIVATE)
    private val parts = File(app.filesDir, "store_download_parts")
    private val apks = File(app.filesDir, "store_downloads")
    private val lock = Any()
    private val worker = Mutex()
    private var active: Pair<String, ApkTransfer>? = null
    private val records = MutableStateFlow(readRecords())
    val tasks = records.asStateFlow()

    private fun readRecords(): List<StoreDownload> {
        val rows = prefs.all.mapNotNull { (id, raw) ->
            if (raw !is String || !validId(id)) return@mapNotNull null
            runCatching {
                val data = JSONObject(raw)
                val saved = StoreDownloadState.valueOf(data.getString("state"))
                val completed = apk(id).isFile
                val state = when {
                    completed -> StoreDownloadState.COMPLETE
                    saved == StoreDownloadState.COMPLETE -> StoreDownloadState.FAILED
                    saved == StoreDownloadState.DOWNLOADING || saved == StoreDownloadState.QUEUED -> StoreDownloadState.PAUSED
                    else -> saved
                }
                val error = when {
                    saved == StoreDownloadState.COMPLETE && !completed -> "安装包已不存在，请重试"
                    state == StoreDownloadState.FAILED -> data.optString("error")
                    else -> ""
                }
                StoreDownload(id, data.getString("name"), checkedStoreUrl(data.getString("url")).toString(),
                    StoreDownloadSource(data.optString("package"), data.optString("aid"), data.optString("vc")),
                    state, if (completed) apk(id).length() else part(id).length(),
                    data.optLong("total", -1), version = data.optString("version"), error = error,
                    renewUrl = data.optBoolean("renewUrl"))
            }.getOrNull()
        }.sortedByDescending { prefs.getString(it.id, null)?.let { raw -> JSONObject(raw).optLong("created") } ?: 0 }
        val ids = rows.mapTo(mutableSetOf(), StoreDownload::id)
        for (directory in listOf(parts, apks)) {
            directory.listFiles()?.filter { validId(it.nameWithoutExtension) && it.nameWithoutExtension !in ids }
                ?.forEach { it.delete() }
        }
        return rows
    }

    private fun publish(task: StoreDownload) {
        val before = records.value
        records.value = if (before.any { it.id == task.id }) before.map { if (it.id == task.id) task else it }
            else listOf(task) + before
    }

    private fun save(task: StoreDownload): Boolean {
        val created = prefs.getString(task.id, null)?.let { JSONObject(it).optLong("created") } ?: System.currentTimeMillis()
        return prefs.edit().putString(task.id, JSONObject().put("name", task.name).put("url", task.url)
            .put("package", task.source.packageName).put("aid", task.source.appId).put("vc", task.source.versionCode)
            .put("state", task.state.name).put("total", task.total).put("version", task.version)
            .put("error", task.error).put("renewUrl", task.renewUrl).put("created", created).toString()).commit()
    }

    private fun update(task: StoreDownload) {
        check(save(task)) { "无法保存下载记录" }
        publish(task)
    }

    suspend fun enqueue(url: String, name: String, source: StoreDownloadSource) = withContext(Dispatchers.IO) {
        val normalized = checkedStoreUrl(url).toString()
        val task = synchronized(lock) {
            val existing = records.value.firstOrNull {
                it.url == normalized || (source.canResolve && it.source == source)
            }
            if (existing != null && existing.state in ongoingOrComplete) return@withContext
            require(existing != null || records.value.size < 200) { "下载任务已达到 200 个，请移除旧任务" }
            val next = existing?.copy(url = normalized, state = StoreDownloadState.QUEUED, error = "", renewUrl = false)
                ?: StoreDownload(UUID.randomUUID().toString(), name.take(80).ifBlank { "应用" }, normalized, source)
            update(next)
            next
        }
        start(task)
    }

    suspend fun resume(id: String, api: ContentApi) {
        val task = records.value.firstOrNull { it.id == id } ?: return
        if (task.state !in resumable) return
        val url = if (task.renewUrl && task.source.canResolve) {
            val owner = api.imageCacheScope()
            checkedStoreUrl(task.source.resolve(api)).toString().also {
                check(owner == api.imageCacheScope()) { "账号已变更，请重新下载" }
            }
        } else task.url
        withContext(Dispatchers.IO) {
            val next = synchronized(lock) {
                val latest = records.value.firstOrNull { it.id == id } ?: return@withContext
                if (latest.state != task.state || latest.url != task.url) return@withContext
                latest.copy(url = url, state = StoreDownloadState.QUEUED, speed = 0, error = "", renewUrl = false).also(::update)
            }
            start(next)
        }
    }

    private fun start(task: StoreDownload) {
        try {
            ContextCompat.startForegroundService(app, Intent(app, StoreDownloadService::class.java))
        } catch (_: RuntimeException) {
            synchronized(lock) {
                if (records.value.firstOrNull { it.id == task.id } != task) return
                update(task.copy(state = StoreDownloadState.PAUSED))
            }
            error("系统暂时无法启动下载，请在下载管理中继续")
        }
    }

    suspend fun pause(id: String) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val task = records.value.firstOrNull { it.id == id } ?: return@synchronized
            if (task.state !in inProgress) return@synchronized
            update(task.copy(state = StoreDownloadState.PAUSED, speed = 0))
            active?.takeIf { it.first == id }?.second?.cancel()
        }
    }

    suspend fun remove(id: String) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val task = records.value.firstOrNull { it.id == id } ?: return@synchronized
            val transfer = active?.takeIf { it.first == id }?.second
            if (transfer == null) eraseFiles(id)
            check(prefs.edit().remove(id).commit()) { "无法移除下载记录" }
            records.value = records.value - task
            transfer?.cancel()
        }
    }

    suspend fun runNext(transfer: ApkTransfer): Boolean = worker.withLock {
        withContext(Dispatchers.IO) {
            val task = synchronized(lock) {
                transfer.checkActive()
                val queued = records.value.lastOrNull { it.state == StoreDownloadState.QUEUED }
                    ?: return@withContext false
                active = queued.id to transfer
                queued.copy(state = StoreDownloadState.DOWNLOADING).also(::publish)
            }
            var failure = ""
            var renewUrl = false
            var version: String? = null
            try {
                check(parts.isDirectory || parts.mkdirs()) { "无法创建下载目录" }
                check(apks.isDirectory || apks.mkdirs()) { "无法创建安装包目录" }
                transfer.download(client, checkedStoreUrl(task.url), part(task.id), checkpoint(task.id)) { bytes, total, speed ->
                    synchronized(lock) {
                        running(task.id)?.let { publish(it.copy(bytes = bytes, total = total, speed = speed)) }
                    }
                }
                val file = part(task.id)
                val archive = app.packageManager.getPackageArchiveInfo(file.path, 0)
                if (archive == null || task.source.packageName.isNotBlank() && archive.packageName != task.source.packageName) {
                    checkpoint(task.id).delete()
                    file.delete()
                    throw ApkTransferFailure("安装包无效或包名不匹配，请重试")
                }
                version = archive.versionName.orEmpty()
            } catch (_: CancellationException) {
                transfer.cancel()
            } catch (error: ApkTransferFailure) {
                failure = error.message.orEmpty()
                renewUrl = error.renewUrl
            } catch (_: IOException) {
                failure = "下载中断，请检查网络和存储空间后重试"
            } catch (_: RuntimeException) {
                failure = "无法保存或读取安装包，请重试"
            } finally {
                synchronized(lock) {
                    try {
                        val latest = records.value.firstOrNull { it.id == task.id }
                        if (latest == null) {
                            runCatching { eraseFiles(task.id) }
                        } else if (latest.state == StoreDownloadState.DOWNLOADING) {
                            val result = finish(latest, transfer, version, failure, renewUrl)
                            save(result)
                            publish(result)
                        } else {
                            publish(latest.copy(bytes = part(task.id).length(), speed = 0))
                        }
                    } finally {
                        active = null
                    }
                }
            }
            true
        }
    }

    private fun finish(task: StoreDownload, transfer: ApkTransfer, version: String?, failure: String, renewUrl: Boolean): StoreDownload {
        val file = part(task.id)
        val paused = try { transfer.checkActive(); false } catch (_: CancellationException) { true }
        if (!paused && version != null && file.renameTo(apk(task.id))) {
            checkpoint(task.id).delete()
            return task.copy(state = StoreDownloadState.COMPLETE, speed = 0, version = version)
        }
        return task.copy(state = if (paused) StoreDownloadState.PAUSED else StoreDownloadState.FAILED,
            bytes = file.length(), speed = 0, error = if (paused) "" else failure.ifEmpty { "无法保存安装包，请重试" },
            renewUrl = !paused && renewUrl)
    }

    suspend fun pauseWaiting() = withContext(Dispatchers.IO) {
        synchronized(lock) {
            records.value.filter { it.state == StoreDownloadState.QUEUED }.forEach {
                val paused = it.copy(state = StoreDownloadState.PAUSED)
                save(paused)
                publish(paused)
            }
        }
    }

    private fun running(id: String) = records.value.firstOrNull { it.id == id && it.state == StoreDownloadState.DOWNLOADING }
    private fun part(id: String) = File(parts, "$id.apk")
    private fun checkpoint(id: String) = File(parts, "$id.etag")
    fun apk(id: String): File {
        require(validId(id))
        return File(apks, "$id.apk")
    }

    private fun eraseFiles(id: String) {
        for (file in listOf(apk(id), part(id), checkpoint(id))) {
            check(!file.exists() || file.delete()) { "无法删除下载文件，请重试" }
        }
    }

    companion object {
        private val idPattern = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
        private fun validId(id: String) = idPattern.matches(id)
        private val inProgress = setOf(StoreDownloadState.QUEUED, StoreDownloadState.DOWNLOADING)
        private val ongoingOrComplete = inProgress + StoreDownloadState.COMPLETE
        private val resumable = setOf(StoreDownloadState.PAUSED, StoreDownloadState.FAILED)
        private val client by lazy {
            OkHttpClient.Builder().followSslRedirects(false)
                .addNetworkInterceptor { chain ->
                    val request = chain.request()
                    val url = request.url
                    if (!url.isHttps || url.username.isNotEmpty() || url.password.isNotEmpty()) {
                        throw ApkTransferFailure("下载跳转地址无效")
                    }
                    chain.proceed(request)
                }.build()
        }

        private var instance: StoreDownloads? = null
        @Synchronized fun get(context: Context): StoreDownloads =
            instance ?: StoreDownloads(context.applicationContext).also { instance = it }
    }
}
