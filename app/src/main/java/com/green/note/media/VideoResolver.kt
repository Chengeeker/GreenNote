package com.green.note.media

import com.green.note.content.ContentApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.util.Collections
import java.util.IdentityHashMap
import java.util.concurrent.TimeUnit

object VideoResolver {
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(8, TimeUnit.SECONDS).readTimeout(12, TimeUnit.SECONDS).callTimeout(20, TimeUnit.SECONDS).build()

    suspend fun resolve(input: String, requestParams: String, api: ContentApi, onQualities: (Map<String, String>) -> Unit = {}): String {
        var current = input.trim()
        if (requestParams.isNotBlank()) {
            try {
                val result = api.request("/v6/player/getUrl", method = "POST", body = mapOf("params" to requestParams.trim()))
                extractStream(result).takeIf(String::isNotEmpty)?.let { onQualities(resolvedQualityUrls(result)); return it }
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* Direct sources can still be playable. */ }
        }
        if (current.isEmpty()) return ""
        if (direct(current)) return normalize(current)
        return withContext(Dispatchers.IO) {
            val first = current.toHttpUrlOrNull() ?: return@withContext ""
            if (first.host in listOf("t.cn", "b23.tv", "url.cn")) {
                try {
                    client.newCall(Request.Builder().url(first).build()).execute().use { response ->
                        response.header("Location")?.let { location -> first.resolve(location)?.let { current = it.toString() } }
                    }
                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* Preserve the original URL as the fallback. */ }
            }
            if (direct(current)) return@withContext normalize(current)
            var objectId = objectId(current)
            if (objectId == null) {
                val uri = current.toHttpUrlOrNull()
                if (uri != null && (uri.host == "weibo.com" || uri.host.endsWith(".weibo.com") || uri.host == "weibo.cn" || uri.host.endsWith(".weibo.cn"))) {
                    val statusId = Regex("/(?:[0-9]+|status|detail)/([A-Za-z0-9]+)").find(uri.encodedPath)?.groupValues?.get(1)
                    if (statusId != null) try {
                        val root = fetchJson(Request.Builder().url("https://m.weibo.cn/statuses/show?id=$statusId")
                            .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)").build())
                        root.optJSONObject("data")?.optJSONObject("page_info")?.optString("object_id")?.let { value -> objectId = checkedObjectId(value) }
                    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* A status may have no video. */ }
                }
            }
            if (objectId != null) {
                try {
                    val id = objectId!!
                    val url = "https://h5.video.weibo.com/api/component".toHttpUrlOrNull()!!.newBuilder().addQueryParameter("page", "/show/$id").build()
                    val payload = JSONObject().put("Component_Play_Playinfo", JSONObject().put("oid", id))
                    val request = Request.Builder().url(url)
                        .header("Accept", "application/json, text/plain, */*").header("Referer", "https://h5.video.weibo.com/show/$id")
                        .header("Origin", "https://h5.video.weibo.com").header("PAGE-REFERER", "/show/$id")
                        .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15")
                        .post(FormBody.Builder().add("data", payload.toString()).build()).build()
                    val result = fetchJson(request)
                    preferredStream(result).takeIf(String::isNotEmpty)?.let { onQualities(resolvedQualityUrls(result)); return@withContext it }
                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* The original source remains the final fallback. */ }
            }
            normalize(current)
        }
    }

    private fun fetchJson(request: Request): JSONObject = client.newCall(request).execute().use { response ->
        check(response.isSuccessful) { "视频解析请求失败" }
        val source = response.body?.source() ?: error("视频解析响应为空")
        require(!source.request(4L * 1024 * 1024 + 1)) { "视频解析响应过大" }
        JSONObject(source.readUtf8())
    }
    private fun direct(value: String): Boolean = value.toHttpUrlOrNull()?.encodedPath?.lowercase()?.let { it.endsWith(".mp4") || it.endsWith(".m3u8") } == true
    fun normalize(value: Any?): String {
        val raw = when (value) { null, JSONObject.NULL -> ""; is JSONObject -> value.optString("url").ifBlank { value.optString("src") }; is String -> value; else -> "" }
        val normalized = if (raw.startsWith("//")) "https:$raw" else raw
        val uri = normalized.toHttpUrlOrNull() ?: return ""
        return normalized.takeIf { uri.username.isEmpty() && uri.password.isEmpty() }.orEmpty()
    }
    fun extractStream(payload: Any?): String {
        val pending = mutableListOf(payload)
        val visited = Collections.newSetFromMap(IdentityHashMap<Any, Boolean>())
        var cursor = 0
        while (cursor < pending.size && cursor < 10000) {
            val value = pending[cursor++]
            normalize(value).takeIf(String::isNotEmpty)?.let { return it }
            if (value != null && !visited.add(value)) continue
            when (value) {
                is JSONArray -> for (i in 0 until value.length()) pending.add(value.opt(i))
                is JSONObject -> {
                    listOf("url", "videoUrl", "video_url", "videoSrc", "video_src", "finalUrl", "final_url", "data", "result", "payload", "urlList", "url_list", "urls").forEach { key ->
                        value.opt(key)?.let { nested ->
                            pending.add(nested)
                            if (key == "urls" && nested is JSONObject) nested.keys().forEach { pending.add(nested.opt(it)) }
                        }
                    }
                }
            }
        }
        return ""
    }
    internal fun resolvedQualityUrls(payload: Any?): Map<String, String> {
        val root = payload as? JSONObject ?: return emptyMap()
        val data = root.optJSONObject("data") ?: root
        val player = data.optJSONObject("Component_Play_Playinfo") ?: data
        val options = sortedMapOf<Int, String>(compareByDescending { it })
        val resolution = Regex("(?<![0-9])(2160|1440|1080|720|480|360)(?![0-9])")
        fun add(label: String, url: Any?) {
            val pixels = resolution.find(label)?.value?.toIntOrNull() ?: return
            normalize(url).takeIf(String::isNotEmpty)?.let { options.putIfAbsent(pixels, it) }
        }
        when (val urls = player.opt("urls")) {
            is JSONObject -> for (key in urls.keys()) add(key, urls.opt(key))
            is JSONArray -> for (i in 0 until urls.length()) {
                val row = urls.optJSONObject(i) ?: continue
                val label = listOf("height", "resolution", "quality", "label").firstOrNull { resolution.containsMatchIn(row.optString(it)) }
                if (label != null) add(row.optString(label), row.opt("url") ?: row.opt("play_url") ?: row.opt("play_info"))
            }
        }
        val seen = hashSetOf<String>()
        return options.filterValues(seen::add).mapKeys { "${it.key}P" }.takeIf { it.size > 1 }.orEmpty()
    }
    fun preferredStream(payload: JSONObject): String {
        val data = payload.optJSONObject("data") ?: payload
        val info = data.optJSONObject("Component_Play_Playinfo") ?: payload.optJSONObject("Component_Play_Playinfo") ?: return ""
        when (val urls = info.opt("urls")) {
            is JSONObject -> {
                for (prefix in listOf("1080", "720", "hd", "ld")) for (key in urls.keys()) {
                    if (key.lowercase().contains(prefix)) normalize(urls.opt(key)).takeIf(String::isNotEmpty)?.let { return it }
                }
                for (key in urls.keys()) normalize(urls.opt(key)).takeIf(String::isNotEmpty)?.let { return it }
            }
            is JSONArray -> for (i in 0 until urls.length()) {
                val row = urls.optJSONObject(i) ?: continue
                listOf("url", "play_url", "play_info").forEach { normalize(row.opt(it)).takeIf(String::isNotEmpty)?.let { value -> return value } }
            }
        }
        return normalize(info.opt("stream_url") ?: info.opt("stream_url_hd"))
    }
    private fun checkedObjectId(raw: String): String? {
        val value = raw.removePrefix("1034:")
        return if (Regex("^[0-9]{1,40}$").matches(value)) "1034:$value" else null
    }
    fun objectId(url: String): String? {
        Regex("1034(?::|%3[Aa])([0-9]+)").find(url)?.groupValues?.get(1)?.let { return checkedObjectId(it) }
        val uri = url.toHttpUrlOrNull()
        for (key in listOf("fid", "object_id", "oid")) uri?.queryParameter(key)?.let { checkedObjectId(it)?.let { id -> return id } }
        Regex("/show/(1034:[0-9]+|[0-9]+)").find(url)?.groupValues?.get(1)?.let { return checkedObjectId(it) }
        return null
    }

    fun playbackHeaders(url: String): Map<String, String> {
        val host = url.toHttpUrlOrNull()?.host.orEmpty()
        val result = mutableMapOf("User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
        if (listOf("weibo.com", "weibo.cn", "sina.com.cn", "sinaimg.cn").any { host == it || host.endsWith(".$it") }) {
            result["Referer"] = "https://h5.video.weibo.com/"; result["Origin"] = "https://h5.video.weibo.com"
        } else if (host == "coolapk.com" || host.endsWith(".coolapk.com")) result["Referer"] = "https://www.coolapk.com/"
        return result
    }
}
