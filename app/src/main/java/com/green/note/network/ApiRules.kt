package com.green.note.network

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

data class ApiSession(val device: String, val cookie: String = "", val anonymous: Boolean = false, val revision: Long = 0) {
    val authenticated get() = !anonymous && cookie.isNotBlank()
    val effectiveCookie get() = if (authenticated) cookie else ""
    override fun toString() = "ApiSession(authenticated=$authenticated, anonymous=$anonymous, revision=$revision)"
}

object ApiRules {
    internal val commentPaths = setOf("/v6/feed/replyList", "/v6/feed/hotReplyList", "/v6/feed/replyDetail")
    private val mutatingGets = setOf(
        "/v6/user/unfollow", "/v6/user/addToBlackList", "/v6/user/removeFromBlackList",
        "/v6/user/addToIgnoreList", "/v6/user/removeFromIgnoreList", "/v6/feed/favorite",
        "/v6/feed/unFavorite", "/v6/feed/followTag", "/v6/feed/unFollowTag",
    )

    fun trusted(url: HttpUrl) = url.isHttps && url.port == 443 &&
        url.host in setOf("api.coolapk.com", "api2.coolapk.com") && url.username.isEmpty() && url.password.isEmpty()

    internal fun commentRead(url: HttpUrl) = trusted(url) && url.encodedPath in commentPaths

    fun resolve(path: String, query: Map<String, String>): HttpUrl {
        val url = "https://api.coolapk.com/".toHttpUrl().resolve(path) ?: error("接口地址无效")
        require(trusted(url)) { "接口地址不受信任" }
        return url.newBuilder().apply { query.forEach { (name, value) -> addQueryParameter(name, value) } }.build()
    }

    fun allow(session: ApiSession, method: String, path: String) {
        if (!session.anonymous) return
        if ((method.uppercase() != "GET" || path in mutatingGets) && path != "/v6/player/getUrl" ||
            listOf("/account/", "/notification/", "/message/").any { it in path }) {
            throw ApiException("当前为匿名登录，无法使用此功能")
        }
    }

    fun hasMore(root: JSONObject, count: Int, allowShortPage: Boolean = false): Boolean {
        val value = listOf("hasMore", "has_more", "hasNextPage").firstNotNullOfOrNull { key ->
            root.opt(key).takeUnless { it == null || it == JSONObject.NULL }
        }
        return when (value) {
            is Boolean -> value
            is Number -> value.toInt() != 0
            "1", "true" -> true
            "0", "false" -> false
            else -> if (allowShortPage) count > 0 else count >= 10
        }
    }
}

open class ApiException(message: String) : Exception(message)

data class CaptchaChallenge(val id: String, val field: String) {
    fun proof(validate: String): String? = if (!id.matches(Regex("[a-zA-Z0-9]{16,64}")) ||
        field.isNotEmpty() && !field.matches(Regex("_[a-zA-Z0-9_]{1,63}")) || validate.isEmpty() || validate.length > 8192 ||
        validate.any { it.isWhitespace() || it.code < 32 || it.code == 127 }) null else "NEC:${id.take(8)}:$validate"

    companion object {
        fun parse(root: JSONObject): CaptchaChallenge? {
            if (root.optString("messageStatus") != "err_request_captcha_v2") return null
            fun JSONObject.value(key: String) = opt(key).takeUnless { it == null || it == JSONObject.NULL }
            val raw = root.value("messageExtra") ?: root.value("extra") ?: root
            val extra = when (raw) {
                is JSONObject -> raw
                is String -> runCatching { JSONObject(raw) }.getOrNull()
                else -> null
            } ?: return null
            if (extra.value("captchaType")?.let { it != "NEC" } == true) return null
            val id = extra.opt("captchaId") as? String ?: return null
            val field = (extra.value("captchaField") ?: "_v2_post_token") as? String ?: return null
            if (!id.matches(Regex("[a-zA-Z0-9]{16,64}")) ||
                field.isNotEmpty() && !field.matches(Regex("_[a-zA-Z0-9_]{1,63}"))) return null
            return CaptchaChallenge(id, field)
        }
    }
}

/** An immutable read request issued by one ApiClient. It never retains credentials or a proof. */
class CommentCaptchaRequest internal constructor(
    internal val url: HttpUrl,
    internal val modernReplies: Boolean,
    internal val issuer: Any,
) {
    private val replayed = AtomicBoolean(false)
    internal fun claim() = replayed.compareAndSet(false, true)
    internal fun matches(other: HttpUrl, modern: Boolean): Boolean = modernReplies == modern &&
        url.scheme == other.scheme && url.host == other.host && url.port == other.port &&
        url.encodedPath == other.encodedPath && url.queryParameterNames == other.queryParameterNames &&
        url.queryParameterNames.all { url.queryParameterValues(it) == other.queryParameterValues(it) }
    override fun toString() = "CommentCaptchaRequest(host=${url.host}, path=${url.encodedPath}, modern=$modernReplies)"
}

class CaptchaRequired(
    val challenge: CaptchaChallenge,
    val context: String,
    message: String,
    val request: CommentCaptchaRequest? = null,
) : ApiException(message) {
    val canVerifyComment get() = request?.let { ApiRules.commentRead(it.url) } == true
}

internal class UnsupportedCaptcha : ApiException("当前接口需要验证码，但未返回可用的验证参数，请稍后重试")
