package com.green.note.account

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SessionRevisionTest {
    @Test fun localFavoritesAndDisplayEditsDoNotInvalidateTheActiveSession() {
        val before = AccountState(mode = AccountMode.ANONYMOUS, revision = 9, sessionRevision = 3)
        val favorite = JSONObject(before.localJson).put("favorites", JSONObject().put("42", JSONObject().put("id", "42")))
        assertEquals(3L, nextSessionRevision(before, before.copy(localJson = favorite.toString(), revision = 10)))
        assertEquals(3L, nextSessionRevision(before, before.copy(username = "新名字", avatar = "new")))
        assertThrows(IllegalStateException::class.java) { requireAccountGeneration(before, before.copy(revision = 10)) }
    }
    @Test fun modeCookieProfileAndPublicIdentityChangesInvalidateOldRequests() {
        val before = AccountState(mode = AccountMode.ANONYMOUS, sessionRevision = 3)
        assertEquals(4L, nextSessionRevision(before, before.copy(mode = AccountMode.GUEST)))
        assertEquals(4L, nextSessionRevision(before, before.copy(localJson = JSONObject(before.localJson).put("activeProfileId", "other").toString())))
        assertEquals(4L, nextSessionRevision(before, before.copy(localJson = JSONObject(before.localJson).put("publicIdentity", JSONObject().put("uid", "99")).toString())))
        val official = AccountState(mode = AccountMode.COOKIE, uid = "7", cookie = "uid=7", sessionRevision = 8)
        assertEquals(9L, nextSessionRevision(official, official.copy(cookie = "uid=8", uid = "8")))
        assertEquals(8L, nextSessionRevision(official, official.copy(username = "昵称")))
    }
}
