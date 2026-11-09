package com.green.note.media

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.TimeUnit

object MediaFiles {
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(25, TimeUnit.SECONDS).readTimeout(120, TimeUnit.SECONDS).build()

    private suspend fun copy(url: String, output: OutputStream, headers: Map<String, String>, limit: Long): String {
        var target = url.toHttpUrl()
        for (hop in 0..5) {
            coroutineContext.ensureActive()
            require(target.username.isEmpty() && target.password.isEmpty()) { "媒体地址无效" }
            val trusted = target.scheme == "https" && target.port == 443 && (target.host == "coolapk.com" || target.host.endsWith(".coolapk.com"))
            val request = Request.Builder().url(target).apply {
                headers.forEach { (name, value) ->
                    val key = name.lowercase()
                    if (trusted || key !in setOf("cookie", "authorization") && !key.startsWith("x-app-") && !key.startsWith("x-green")) header(name, value)
                }
            }.build()
            client.newCall(request).execute().use { response ->
                if (response.code in 300..399) {
                    target = target.resolve(response.header("Location") ?: error("媒体跳转无地址")) ?: error("媒体跳转地址无效")
                } else {
                    check(response.isSuccessful) { "媒体下载失败" }
                    val body = response.body ?: error("媒体数据为空")
                    require(body.contentLength() <= limit) { "媒体文件超过大小限制" }
                    val contentType = body.contentType()?.toString().orEmpty()
                    var total = 0L
                    body.byteStream().use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            coroutineContext.ensureActive()
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (total == 0L) validateMediaPayload(contentType, buffer.copyOf(minOf(count, 512)))
                            total += count
                            require(total <= limit) { "媒体文件超过大小限制" }
                            output.write(buffer, 0, count)
                        }
                    }
                    require(total > 0) { "媒体数据为空" }
                    return mediaMimeType(contentType, url)
                }
            }
        }
        error("媒体跳转过多")
    }

    suspend fun save(context: Context, url: String, video: Boolean, headers: Map<String, String> = emptyMap(), subdirectory: String = "GreenNote"): String = withContext(Dispatchers.IO) {
        require(subdirectory.isNotBlank() && subdirectory.length <= 160 && subdirectory.split('/').all { segment ->
            segment.isNotBlank() && segment !in listOf(".", "..") && !Regex("[\\\\:*?\"<>|\\x00-\\x1f]").containsMatchIn(segment)
        }) { "保存目录无效" }
        val baseName = "gn_${UUID.randomUUID()}"
        var name = "$baseName.${if (video) "mp4" else "jpg"}"
        val directory = if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
        val mime = if (video) "video/mp4" else "image/jpeg"
        val limit = if (video) 2L * 1024 * 1024 * 1024 else 64L * 1024 * 1024
        if (Build.VERSION.SDK_INT >= 29) {
            val collection = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name); put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$directory/$subdirectory"); put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(collection, values) ?: error("无法创建媒体文件")
            try {
                val actualType = context.contentResolver.openOutputStream(uri)?.use { copy(url, it, headers, limit) } ?: error("无法写入媒体文件")
                name = "$baseName.${extension(actualType, video)}"
                val complete = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    if (actualType.substringBefore(';').startsWith(if (video) "video/" else "image/")) put(MediaStore.MediaColumns.MIME_TYPE, actualType.substringBefore(';'))
                }
                check(context.contentResolver.update(uri, complete, null, null) > 0)
            } catch (failure: Exception) { context.contentResolver.delete(uri, null, null); throw failure }
        } else {
            check(context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) { "请先允许保存到相册" }
            val folder = File(Environment.getExternalStoragePublicDirectory(directory), subdirectory)
            check(folder.isDirectory || folder.mkdirs()) { "无法创建保存目录" }
            var file = File(folder, name)
            try {
                val actualType = file.outputStream().use { copy(url, it, headers, limit) }
                name = "$baseName.${extension(actualType, video)}"
                val destination = File(folder, name)
                if (file != destination) { check(file.renameTo(destination)) { "无法完成媒体文件写入" }; file = destination }
                MediaScannerConnection.scanFile(context, arrayOf(file.path), arrayOf(actualType.ifBlank { mime }), null)
            } catch (failure: Exception) { file.delete(); throw failure }
        }
        "$directory/$subdirectory/$name"
    }

    suspend fun share(context: Context, url: String, headers: Map<String, String> = emptyMap()): Intent = withContext(Dispatchers.IO) {
        val (uri, type) = prepareSharedImage(context, url, headers)
        Intent.createChooser(Intent(Intent.ACTION_SEND).setType(type)
            .putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "分享图片")
    }
    suspend fun wallpaper(context: Context, url: String, headers: Map<String, String> = emptyMap()): Intent = withContext(Dispatchers.IO) {
        val (uri, type) = prepareSharedImage(context, url, headers)
        runCatching { android.app.WallpaperManager.getInstance(context).getCropAndSetWallpaperIntent(uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }.getOrElse {
            Intent.createChooser(Intent(Intent.ACTION_ATTACH_DATA).setDataAndType(uri, type).putExtra("mimeType", type).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "设为壁纸")
        }
    }
    private suspend fun prepareSharedImage(context: Context, url: String, headers: Map<String, String>): Pair<Uri, String> {
        val directory = File(context.cacheDir, "compose-share").apply { mkdirs() }
        directory.listFiles()?.filter { it.isFile && System.currentTimeMillis() - it.lastModified() > 24 * 60 * 60 * 1000 }?.forEach { it.delete() }
        var file = File(directory, "gn_${UUID.randomUUID()}.jpg")
        val type = try { file.outputStream().use { copy(url, it, headers, 64L * 1024 * 1024) } } catch (failure: Exception) { file.delete(); throw failure }
        val destination = File(directory, "${file.nameWithoutExtension}.${extension(type, false)}")
        if (file != destination) { if (!file.renameTo(destination)) { file.delete(); error("无法准备分享图片") }; file = destination }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.apk_files", file)
        return uri to (type.substringBefore(';').takeIf { it.startsWith("image/") } ?: "image/*")
    }
    internal fun extension(mime: String, video: Boolean): String = when (mime.substringBefore(';').lowercase()) {
        "image/png" -> "png"; "image/gif" -> "gif"; "image/webp" -> "webp"; "image/avif" -> "avif"; "image/heic", "image/heif" -> "heic"
        "video/webm" -> "webm"; "video/quicktime" -> "mov"; else -> if (video) "mp4" else "jpg"
    }
    internal fun mediaMimeType(contentType: String, url: String): String {
        val type = contentType.substringBefore(';').trim().lowercase()
        if (type.startsWith("image/") || type.startsWith("video/")) return type
        // Original GalleryImage.isGif supplies the MIME fallback when a CDN responds
        // with octet-stream; do not relabel an animated GIF as a JPEG in MediaStore.
        return if (url.contains(".gif", ignoreCase = true)) "image/gif" else contentType
    }
    internal fun validateMediaPayload(mime: String, prefix: ByteArray) {
        val type = mime.substringBefore(';').trim().lowercase()
        val leading = String(prefix, Charsets.ISO_8859_1).trimStart().lowercase()
        require(!leading.startsWith("#extm3u") && type !in setOf("application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl")) { "当前视频为分段流，无法保存为单个视频文件" }
        require((type.isEmpty() || type.startsWith("image/") || type.startsWith("video/") || type in setOf("application/octet-stream", "binary/octet-stream", "application/mp4")) &&
            !leading.startsWith("<!doctype html") && !leading.startsWith("<html") && !leading.startsWith('{') && !leading.startsWith('[')) { "服务器未返回有效媒体文件，请重试" }
    }
}
