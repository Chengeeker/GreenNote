package com.green.note

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class AppDownloads(private val activity: MainActivity) {
    private val manager = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs = activity.getSharedPreferences("greennote.downloads", Context.MODE_PRIVATE)
    private val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
    fun handle(method: String, args: Map<*, *>?, result: MethodChannel.Result) {
        if (method == "install") {
            try {
                if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                    result.error("INSTALL_PERMISSION", "请允许安装应用后再次点击安装", null)
                    return
                }
                val id = (args?.get("id") as? Number)?.toLong()
                if (id != null) require(prefs.contains(id.toString()))
                val uri = if (id != null) manager.getUriForDownloadedFile(id) else {
                    val root = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)!!.canonicalFile
                    val file = File(args?.get("path") as? String ?: "").canonicalFile
                    require(file.path.startsWith(root.path + File.separator) && file.isFile && file.extension == "apk")
                    FileProvider.getUriForFile(activity, "${activity.packageName}.apk_files", file)
                }
                require(uri != null)
                activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                result.success(true)
            } catch (_: Exception) { result.error("INSTALL_FAILED", "无法打开安装包", null) }
            return
        }
        executor.execute {
            try {
                val value: Any = when (method) {
                    "enqueue" -> {
                        require(prefs.all.size < 200)
                        val uri = Uri.parse(args?.get("url") as? String ?: "")
                        require(uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.userInfo.isNullOrEmpty())
                        val name = (args?.get("name") as? String ?: "应用").take(80)
                        val filename = "greennote-${System.currentTimeMillis()}.apk"
                        val request = DownloadManager.Request(uri).setTitle(name)
                            .setMimeType("application/vnd.android.package-archive")
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            .setAllowedOverRoaming(false)
                            .setDestinationInExternalFilesDir(activity, Environment.DIRECTORY_DOWNLOADS, filename)
                        val id = manager.enqueue(request)
                        prefs.edit().putString(id.toString(), JSONObject().put("url", uri.toString()).put("name", name).toString()).apply()
                        id
                    }
                    "list" -> {
                        val ids = prefs.all.keys.mapNotNull { it.toLongOrNull() }.sortedDescending().take(200)
                        if (ids.isEmpty()) emptyList<Map<String, Any>>() else {
                            val rows = mutableListOf<Map<String, Any>>()
                            manager.query(DownloadManager.Query().setFilterById(*ids.toLongArray()))?.use { cursor ->
                                while (cursor.moveToNext()) {
                                    fun number(column: String) = cursor.getLong(cursor.getColumnIndexOrThrow(column))
                                    val id = number(DownloadManager.COLUMN_ID)
                                    val meta = JSONObject(prefs.getString(id.toString(), "{}")!!)
                                    rows.add(mapOf("id" to id, "title" to meta.optString("name"),
                                        "status" to number(DownloadManager.COLUMN_STATUS),
                                        "bytes" to number(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                                        "total" to number(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)))
                                }
                            }
                            rows
                        }
                    }
                    "cancel" -> {
                        val id = (args?.get("id") as Number).toLong()
                        require(prefs.contains(id.toString()))
                        manager.remove(id)
                        prefs.edit().remove(id.toString()).apply()
                        true
                    }
                    "retry" -> {
                        val id = (args?.get("id") as Number).toLong()
                        val meta = JSONObject(prefs.getString(id.toString(), null) ?: error("Unknown download"))
                        val uri = Uri.parse(meta.getString("url"))
                        require(uri.scheme == "https")
                        val newId = manager.enqueue(DownloadManager.Request(uri).setTitle(meta.getString("name"))
                            .setMimeType("application/vnd.android.package-archive")
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            .setAllowedOverRoaming(false)
                            .setDestinationInExternalFilesDir(activity, Environment.DIRECTORY_DOWNLOADS, "greennote-${System.currentTimeMillis()}.apk"))
                        manager.remove(id)
                        prefs.edit().remove(id.toString()).putString(newId.toString(), meta.toString()).apply()
                        newId
                    }
                    "packages" -> {
                        activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.listFiles()
                            ?.filter { it.isFile && it.extension == "apk" }
                            ?.sortedByDescending { it.lastModified() }?.take(200)?.map { file ->
                                val archive = activity.packageManager.getPackageArchiveInfo(file.path, 0)
                                mapOf("path" to file.path, "title" to (archive?.packageName ?: file.name),
                                    "version" to (archive?.versionName ?: ""), "bytes" to file.length())
                            } ?: emptyList<Map<String, Any>>()
                    }
                    else -> throw IllegalArgumentException("Unknown method")
                }
                activity.runOnUiThread { if (!activity.isDestroyed) result.success(value) }
            } catch (_: Exception) { activity.runOnUiThread { if (!activity.isDestroyed) result.error("DOWNLOAD_FAILED", "下载操作失败，请重试", null) } }
        }
    }
    fun close() { executor.shutdown() }
}
