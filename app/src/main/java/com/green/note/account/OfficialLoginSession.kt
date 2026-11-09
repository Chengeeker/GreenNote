package com.green.note.account

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Cookie
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.Closeable
import java.util.concurrent.TimeUnit

class LoginFailure(message: String, val captchaRequired: Boolean = false, val webRequired: Boolean = false) : Exception(message)

/** Separate cookie jar and cancellation scope for each password-login attempt. */
class OfficialLoginSession : Closeable {
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS).build()
    private val cookies = linkedMapOf<String, String>()
    private val lifecycle = HttpSessionLifecycle(client, { client.connectionPool.evictAll() })
    @Volatile private var requestHash: String? = null
    private val closed get() = lifecycle.isClosed
    private val origin = "https://account.coolapk.com".toHttpUrl()
    private val cookie get() = synchronized(cookies) { cookies.entries.joinToString("; ") { "${it.key}=${it.value}" } }

    private fun request(path: String, body: Map<String, String>? = null, limit: Int = 2 * 1024 * 1024, redirects: Int = 0): ByteArray {
        check(!closed) { "登录会话已关闭" }
        val url = origin.resolve(path) ?: throw LoginFailure("登录页面地址无效")
        if (url.scheme != "https" || url.host != origin.host || url.port != 443 || url.username.isNotEmpty() || url.password.isNotEmpty() || redirects > 4) {
            throw LoginFailure("登录页面跳转异常，请使用官方网页登录")
        }
        val builder = Request.Builder().url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.0.0 Mobile Safari/537.36")
            .header("Referer", "https://account.coolapk.com/auth/loginByCoolApk")
            .header("Cookie", cookie).header("X-Requested-With", if (body == null) "com.coolapk.market" else "XMLHttpRequest")
        body?.let { values -> builder.post(FormBody.Builder().apply { values.forEach { (k, v) -> add(k, v) } }.build()) }
        return lifecycle.readResponse(builder.build()) { response ->
            if (response.code !in 200..399) throw LoginFailure("连接失败，请检查网络后重试")
            for (header in response.headers.values("Set-Cookie")) {
                val parsed = Cookie.parse(url, header) ?: continue
                if (parsed.domain != "coolapk.com" && parsed.domain != url.host) continue
                if (Regex("[\\x00-\\x20\\x7f;,]").containsMatchIn(parsed.name + parsed.value)) continue
                synchronized(cookies) {
                    check(!closed) { "登录会话已关闭" }
                    if (parsed.expiresAt <= System.currentTimeMillis()) cookies.remove(parsed.name) else cookies[parsed.name] = parsed.value
                }
            }
            if (response.code >= 300) {
                if (body != null) throw LoginFailure("请使用官方网页完成登录", webRequired = true)
                val location = response.header("Location") ?: throw LoginFailure("登录页面缺少跳转地址")
                return@readResponse request(url.resolve(location)?.toString() ?: throw LoginFailure("登录页面地址无效"), limit = limit, redirects = redirects + 1)
            }
            val source = response.body?.source() ?: throw LoginFailure("登录响应为空")
            if (source.request(limit.toLong() + 1)) throw LoginFailure("登录响应过大")
            source.readByteArray()
        }
    }

    suspend fun prepare() = withContext(Dispatchers.IO) {
        requestHash = null
        synchronized(cookies) { cookies.clear() }
        request("/auth/login?type=mobile")
        val html = request("/auth/loginByCoolApk").toString(Charsets.UTF_8)
        val body = Regex("<body\\b[^>]*>", RegexOption.IGNORE_CASE).find(html)?.value.orEmpty()
        synchronized(cookies) {
            check(!closed) { "登录会话已关闭" }
            requestHash = Regex("data-request-hash\\s*=\\s*[\"']([^\"']+)[\"']", RegexOption.IGNORE_CASE).find(body)?.groupValues?.get(1)?.let(::decodeHtml)
        }
        if (requestHash.isNullOrEmpty() || !synchronized(cookies) { cookies.containsKey("SESSID") }) throw LoginFailure("无法获取登录参数，请重试或使用官方网页登录")
    }
    suspend fun captcha(): ByteArray = withContext(Dispatchers.IO) {
        request("/auth/showCaptchaImage?${System.currentTimeMillis()}").also { if (it.isEmpty()) throw LoginFailure("验证码图片无效，请重新获取") }
    }
    suspend fun login(account: String, password: String, captcha: String): String = withContext(Dispatchers.IO) {
        val hash = requestHash ?: throw LoginFailure("请先重新加载登录参数")
        synchronized(cookies) { listOf("uid", "username", "token").forEach(cookies::remove) }
        val bytes = request("/auth/loginByCoolApk", mapOf("submit" to "1", "randomNumber" to Math.random().toString().replace(".", "undefined"),
            "requestHash" to hash, "login" to account, "password" to password, "captcha" to captcha, "code" to ""))
        val body = try { JSONObject(bytes.toString(Charsets.UTF_8)) } catch (_: Exception) { throw LoginFailure("登录响应异常，请使用官方网页登录", webRequired = true) }
        if (body.optString("status") == "1") {
            if (!hasAccountCookie(cookie)) throw LoginFailure("登录响应缺少账号凭据，请使用官方网页登录")
            cookie
        } else {
            val message = body.optString("message", "登录失败，请重试")
            throw LoginFailure(message, message.contains("图形验证码") || (captcha.isNotEmpty() && message == "密码错误"),
                message.contains("人机") || body.optString("messageStatus") == "err_request_captcha_v2")
        }
    }
    override fun close() {
        lifecycle.close { synchronized(cookies) { cookies.clear(); requestHash = null } }
    }
    companion object {
        internal fun decodeHtml(value: String): String = Regex("&(#x[0-9a-fA-F]+|#[0-9]+|amp|quot|apos|lt|gt);").replace(value) { match ->
            when (val entity = match.groupValues[1]) {
                "amp" -> "&"; "quot" -> "\""; "apos" -> "'"; "lt" -> "<"; "gt" -> ">"
                else -> {
                    val code = if (entity.startsWith("#x")) entity.substring(2).toIntOrNull(16) else entity.substring(1).toIntOrNull()
                    if (code != null && Character.isValidCodePoint(code) && code !in 0xD800..0xDFFF) String(Character.toChars(code)) else match.value
                }
            }
        }
        fun hasAccountCookie(cookie: String): Boolean {
            if (cookie.length > 65536 || Regex("[\\x00-\\x1f\\x7f]").containsMatchIn(cookie)) return false
            val values = cookie.split(';').mapNotNull {
                val index = it.indexOf('=')
                if (index <= 0) null else it.substring(0, index).trim() to it.substring(index + 1).trim()
            }.toMap()
            val uid = values["uid"].orEmpty()
            val token = values["token"].orEmpty()
            return Regex("^[0-9]+$").matches(uid) && uid !in listOf("0", "10000") && token.isNotEmpty() &&
                !Regex("\\s").containsMatchIn(token) && token.lowercase() !in listOf("deleted", "expired")
        }
    }
}
