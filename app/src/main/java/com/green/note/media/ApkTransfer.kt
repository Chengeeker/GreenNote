package com.green.note.media

import okhttp3.Call
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.CancellationException

internal class ApkTransferFailure(message: String, val renewUrl: Boolean = false) : IOException(message)

internal class ApkTransfer {
    private var call: Call? = null
    @Volatile private var cancelled = false

    @Synchronized fun cancel() {
        cancelled = true
        call?.cancel()
    }

    fun checkActive() {
        if (cancelled) throw CancellationException()
    }

    private fun execute(client: OkHttpClient, request: Request): Response {
        val next = synchronized(this) {
            checkActive()
            client.newCall(request).also { call = it }
        }
        return next.execute()
    }

    fun download(
        client: OkHttpClient,
        url: HttpUrl,
        part: File,
        checkpoint: File,
        progress: (bytes: Long, total: Long, speed: Long) -> Unit,
    ) {
        val offset = part.length()
        val saved = if (offset > 0 && checkpoint.isFile) runCatching { JSONObject(checkpoint.readText()) }.getOrNull() else null
        val etag = saved?.optString("etag")?.takeIf(::strongETag)
        val request = Request.Builder().url(url).header("Accept-Encoding", "identity")
        if (etag != null) {
            request.header("Range", "bytes=$offset-").header("If-Range", etag)
        }
        execute(client, request.build()).use { response ->
            if (response.code == 200) {
                write(response, part, checkpoint, 0, response.body?.contentLength() ?: -1, progress)
                return
            }
            if (saved == null || etag == null || response.code != 206 && response.code != 416) throw httpFailure(response.code)
            val total = resumeTotal(response, offset, etag, saved.optString("url"), saved.optLong("total", -1))
            if (total != null) {
                write(response, part, checkpoint, offset, total, progress)
                return
            }
        }
        execute(client, request.removeHeader("Range").removeHeader("If-Range").build()).use { response ->
            if (response.code != 200) throw httpFailure(response.code)
            write(response, part, checkpoint, 0, response.body?.contentLength() ?: -1, progress)
        }
    }

    private fun write(
        response: Response,
        part: File,
        checkpoint: File,
        offset: Long,
        total: Long,
        progress: (Long, Long, Long) -> Unit,
    ) {
        val body = response.body ?: throw ApkTransferFailure("服务器没有返回安装包")
        if (response.header("Content-Encoding")?.equals("identity", ignoreCase = true) == false) {
            throw ApkTransferFailure("服务器返回了不支持的文件编码")
        }
        val contentType = body.contentType()?.type
        if (contentType == "text" || contentType == "application" && body.contentType()?.subtype == "json") {
            throw ApkTransferFailure("下载地址没有返回安装包，请重试", renewUrl = true)
        }
        val remaining = if (total >= 0) total - offset else -1
        if (remaining > part.parentFile!!.usableSpace) throw ApkTransferFailure("存储空间不足")
        var bytes = offset
        var lastBytes = offset
        var lastTime = System.nanoTime()
        checkActive()
        FileOutputStream(part, offset > 0).use { output ->
            if (offset == 0L) {
                val etag = response.header("ETag")?.takeIf(::strongETag)
                if (etag == null) {
                    if (checkpoint.exists() && !checkpoint.delete()) throw IOException("Cannot clear checkpoint")
                } else {
                    checkpoint.writeText(JSONObject().put("etag", etag).put("url", response.request.url.toString())
                        .put("total", total).toString())
                }
            }
            progress(bytes, total, 0)
            val buffer = ByteArray(64 * 1024)
            val input = body.byteStream()
            while (true) {
                checkActive()
                val count = input.read(buffer)
                if (count == -1) break
                if (total >= 0 && count > total - bytes) throw ApkTransferFailure("安装包大小与服务器声明不符")
                output.write(buffer, 0, count)
                bytes += count
                val now = System.nanoTime()
                val elapsed = (now - lastTime) / 1_000_000
                if (elapsed >= 500) {
                    progress(bytes, total, (bytes - lastBytes) * 1000 / elapsed)
                    lastTime = now
                    lastBytes = bytes
                }
            }
            if (bytes == 0L || total >= 0 && bytes != total) throw ApkTransferFailure("下载不完整，请继续下载")
            output.fd.sync()
        }
        checkActive()
        progress(bytes, total, 0)
    }
}

private val downloadRange = Regex("""bytes (\d+)-(\d+)/(\d+)""")

private fun strongETag(value: String) = value.length >= 2 && value.first() == '"' && value.last() == '"'

private fun resumeTotal(response: Response, offset: Long, etag: String, url: String, expectedTotal: Long): Long? {
    if (response.code != 206 || response.request.url.toString() != url || response.header("ETag") != etag) return null
    val range = response.header("Content-Range")?.let(downloadRange::matchEntire) ?: return null
    val start = range.groupValues[1].toLongOrNull() ?: return null
    val end = range.groupValues[2].toLongOrNull() ?: return null
    val total = range.groupValues[3].toLongOrNull() ?: return null
    val length = response.body?.contentLength() ?: -1
    return total.takeIf {
        start == offset && total > start && end == total - 1 &&
            (expectedTotal < 0 || expectedTotal == total) && (length < 0 || length == total - start)
    }
}

private fun httpFailure(code: Int): ApkTransferFailure = when (code) {
    401, 403, 404, 410 -> ApkTransferFailure("下载地址可能已失效，请重试获取", renewUrl = true)
    else -> ApkTransferFailure("服务器暂时无法提供下载（HTTP $code）")
}
