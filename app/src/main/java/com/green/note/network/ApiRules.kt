package com.green.note.network

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject

data class ApiSession(val device: String, val cookie: String = "", val anonymous: Boolean = false, val revision: Long = 0) {
    val authenticated get() = !anonymous && cookie.isNotBlank()
    val effectiveCookie get() = if (authenticated) cookie else ""
    override fun toString() = "ApiSession(authenticated=$authenticated, anonymous=$anonymous, revision=$revision)"
}

object ApiRules {
    private val mutatingGets = setOf(
        "/v6/user/unfollow", "/v6/user/addToBlackList", "/v6/user/removeFromBlackList",
        "/v6/user/addToIgnoreList", "/v6/user/removeFromIgnoreList", "/v6/feed/favorite",
        "/v6/feed/unFavorite", "/v6/feed/followTag", "/v6/feed/unFollowTag",
    )

    fun trusted(url: HttpUrl) = url.isHttps && url.port == 443 &&
        url.host in setOf("api.coolapk.com", "api2.coolapk.com") && url.username.isEmpty() && url.password.isEmpty()

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
            val raw = root.opt("messageExtra") ?: root.opt("extra") ?: root
            val extra = when (raw) {
                is JSONObject -> raw
                is String -> runCatching { JSONObject(raw) }.getOrNull()
                else -> null
            } ?: return null
            if (extra.has("captchaType") && extra.optString("captchaType") != "NEC") return null
            val id = extra.opt("captchaId") as? String ?: return null
            val field = if (extra.has("captchaField")) extra.opt("captchaField") as? String ?: return null else "_v2_post_token"
            if (!id.matches(Regex("[a-zA-Z0-9]{16,64}")) ||
                field.isNotEmpty() && !field.matches(Regex("_[a-zA-Z0-9_]{1,63}"))) return null
            return CaptchaChallenge(id, field)
        }
    }
}

class CaptchaRequired(val challenge: CaptchaChallenge, val context: String, message: String) : ApiException(message)
