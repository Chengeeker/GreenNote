package com.green.note.network

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ApiRulesTest {
    @Test fun credentialDestinationsAreStrict() {
        listOf("https://api.coolapk.com/", "https://api2.coolapk.com/").forEach { assertTrue(ApiRules.trusted(it.toHttpUrl())) }
        listOf("http://api.coolapk.com/", "https://api.coolapk.com.evil.test/", "https://evil.test/", "https://api.coolapk.com:444/", "https://user:pass@api.coolapk.com/").forEach {
            assertFalse(ApiRules.trusted(it.toHttpUrl()))
            assertThrows(IllegalArgumentException::class.java) { ApiRules.resolve(it, emptyMap()) }
        }
    }
    @Test fun anonymousCannotMutateOrReadPrivateDataButCanResolveVideo() {
        val anonymous = ApiSession("device", "uid=1; token=secret", true)
        assertEquals("", anonymous.effectiveCookie)
        listOf("/v6/user/unfollow", "/v6/account/checkLoginInfo", "/v6/message/list", "/v6/notification/list").forEach {
            assertThrows(ApiException::class.java) { ApiRules.allow(anonymous, "GET", it) }
        }
        assertThrows(ApiException::class.java) { ApiRules.allow(anonymous, "POST", "/v6/feed/like") }
        ApiRules.allow(anonymous, "GET", "/v6/feed/detail")
        ApiRules.allow(anonymous, "POST", "/v6/player/getUrl")
    }
    @Test fun paginationUsesServerFlagsBeforePageSize() {
        for (value in listOf(false, 0, "0", "false")) assertFalse(ApiRules.hasMore(JSONObject().put("hasMore", value), 20))
        for (value in listOf(true, 1, "1", "true")) assertTrue(ApiRules.hasMore(JSONObject().put("hasMore", value), 0))
        assertFalse(ApiRules.hasMore(JSONObject(), 9))
        assertTrue(ApiRules.hasMore(JSONObject(), 10))
        assertTrue(ApiRules.hasMore(JSONObject(), 1, true))
    }
    @Test fun captchaOnlyAcceptsExpectedProtocolAndSafeProof() {
        val root = JSONObject().put("messageStatus", "err_request_captcha_v2")
            .put("messageExtra", JSONObject().put("captchaId", "abcdefghijklmnop").put("captchaField", ""))
        val challenge = CaptchaChallenge.parse(root)!!
        assertEquals("NEC:abcdefgh:proof", challenge.proof("proof"))
        assertNull(challenge.proof("proof\r\nCookie:x"))
        assertNull(challenge.proof(" "))
        root.getJSONObject("messageExtra").put("captchaField", "Cookie")
        assertNull(CaptchaChallenge.parse(root))
        assertEquals("uid=10; SESSID=new", ApiClient.withCookie("uid=10; SESSID=old", "SESSID", "new"))
        assertEquals("uid=10", ApiClient.withCookie("uid=10; SESSID=old", "SESSID", ""))
    }

    @Test fun captchaNullMetadataHasTheSameDefaultsAsMissingMetadata() {
        val metadata = JSONObject().put("captchaId", "abcdefghijklmnop").put("captchaType", JSONObject.NULL).put("captchaField", JSONObject.NULL)
        val root = JSONObject().put("messageStatus", "err_request_captcha_v2").put("messageExtra", JSONObject.NULL).put("extra", metadata)
        assertEquals(CaptchaChallenge("abcdefghijklmnop", "_v2_post_token"), CaptchaChallenge.parse(root))
        metadata.put("captchaField", "")
        assertEquals("", CaptchaChallenge.parse(root)!!.field)
        metadata.put("captchaType", "other")
        assertNull(CaptchaChallenge.parse(root))
        metadata.put("captchaType", "NEC").put("captchaId", JSONObject.NULL)
        assertNull(CaptchaChallenge.parse(root))
    }
}
