package com.green.note.media

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.UUID

data class DownloadItem(val id: Long, val title: String, val status: Int, val bytes: Long, val total: Long,
                        val path: String = "", val version: String = "", val storeId: String = "",
                        val speed: Long = 0, val error: String = "")

class AppDownloads(context: Context) {
    private val app = context.applicationContext
    private val manager = app.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs = app.getSharedPreferences("greennote.compose.downloads", Context.MODE_PRIVATE)
    private val mutex = downloadMutex

    private fun importLegacy() {
        if (prefs.getBoolean("legacy_imported", false)) return
        val legacy = app.getSharedPreferences("greennote.downloads", Context.MODE_PRIVATE)
        val candidates = legacy.all.filterKeys { it.toLongOrNull() != null }.entries.sortedByDescending { it.key.toLong() }.take(200)
        val editor = prefs.edit()
        for ((id, raw) in candidates) {
            if (prefs.contains(id)) continue
            require(raw is String && raw.length <= 16384) { "旧下载记录格式无效，原记录已保留" }
            val metadata = JSONObject(raw)
            checkedUrl(metadata.getString("url"))
            editor.putString(id, JSONObject().put("url", metadata.getString("url")).put("name", metadata.optString("name").take(80)).toString())
        }
        check(editor.putBoolean("legacy_imported", true).commit()) { "无法迁移下载记录，原记录已保留" }
    }

    private fun enqueue(uri: Uri, title: String) = manager.enqueue(DownloadManager.Request(uri).setTitle(title)
        .setMimeType("application/vnd.android.package-archive")
        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        .setAllowedOverRoaming(false)
        .setDestinationInExternalFilesDir(app, Environment.DIRECTORY_DOWNLOADS, "greennote-${UUID.randomUUID()}.apk"))

    /** Called under downloadMutex; a null provider cursor is not evidence of deletion. */
    private fun pruneMissingTasks() {
        val ids = prefs.all.keys.mapNotNull(String::toLongOrNull)
        if (ids.isEmpty()) return
        val present = mutableSetOf<Long>()
        val cursor = manager.query(DownloadManager.Query().setFilterById(*ids.toLongArray())) ?: return
        cursor.use { while (it.moveToNext()) present.add(it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_ID))) }
        val missing = ids.filterNot(present::contains)
        if (missing.isNotEmpty()) {
            val editor = prefs.edit()
            missing.forEach { editor.remove(it.toString()) }
            check(editor.commit()) { "无法更新下载记录" }
        }
    }

    suspend fun list(): List<DownloadItem> = withContext(Dispatchers.IO) {
        mutex.withLock { importLegacy(); pruneMissingTasks() }
        val ids = prefs.all.keys.mapNotNull(String::toLongOrNull).sortedDescending().take(200)
        if (ids.isEmpty()) return@withContext emptyList()
        val result = mutableListOf<DownloadItem>()
        manager.query(DownloadManager.Query().setFilterById(*ids.toLongArray()))?.use { cursor ->
            while (cursor.moveToNext()) {
                fun number(column: String) = cursor.getLong(cursor.getColumnIndexOrThrow(column))
                val id = number(DownloadManager.COLUMN_ID)
                val metadata = JSONObject(prefs.getString(id.toString(), "{}") ?: "{}")
                result.add(DownloadItem(id, metadata.optString("name"), number(DownloadManager.COLUMN_STATUS).toInt(),
                    number(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR), number(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)))
            }
        }
        result.sortedByDescending(DownloadItem::id)
    }
    suspend fun cancel(id: Long) = withContext(Dispatchers.IO) { mutex.withLock {
        require(prefs.contains(id.toString())) { "下载任务不存在" }
        manager.remove(id)
        check(prefs.edit().remove(id.toString()).commit()) { "无法更新下载记录" }
    } }
    suspend fun retry(id: Long): Long = withContext(Dispatchers.IO) { mutex.withLock {
        val metadata = JSONObject(prefs.getString(id.toString(), null) ?: error("下载任务不存在"))
        val newId = enqueue(checkedUrl(metadata.getString("url")), metadata.getString("name"))
        if (!prefs.edit().remove(id.toString()).putString(newId.toString(), metadata.toString()).commit()) {
            manager.remove(newId)
            error("无法更新下载记录")
        }
        manager.remove(id)
        newId
    } }
    suspend fun packages(): List<DownloadItem> = withContext(Dispatchers.IO) {
        app.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.listFiles()?.filter { it.isFile && it.extension == "apk" }
            ?.sortedByDescending(File::lastModified)?.take(200)?.map { file ->
                val archive = app.packageManager.getPackageArchiveInfo(file.path, 0)
                DownloadItem(0, archive?.packageName ?: file.name, 8, file.length(), file.length(), file.path, archive?.versionName.orEmpty())
            }.orEmpty()
    }
    fun install(item: DownloadItem) {
        if (Build.VERSION.SDK_INT >= 26 && !app.packageManager.canRequestPackageInstalls()) {
            app.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            error("请允许安装应用后再次点击安装")
        }
        val uri = if (item.path.isNotEmpty()) {
            val root = (if (item.storeId.isNotEmpty()) File(app.filesDir, "store_downloads")
                else app.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS))?.canonicalFile ?: error("下载目录不可用")
            val file = File(item.path).canonicalFile
            require(file.parentFile == root && file.isFile && file.extension == "apk" &&
                (item.storeId.isEmpty() || file.name == "${item.storeId}.apk")) { "安装包路径无效" }
            FileProvider.getUriForFile(app, "${app.packageName}.apk_files", file)
        } else {
            require(prefs.contains(item.id.toString())) { "下载任务不存在" }
            manager.getUriForDownloadedFile(item.id) ?: error("下载尚未完成")
        }
        app.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    companion object {
        private val downloadMutex = Mutex()
        fun checkedUrl(url: String): Uri {
            val uri = Uri.parse(url)
            require(uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.userInfo.isNullOrEmpty()) { "下载地址无效" }
            return uri
        }
    }
}
