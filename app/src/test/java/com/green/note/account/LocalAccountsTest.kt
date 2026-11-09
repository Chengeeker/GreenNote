package com.green.note.account

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LocalAccountsTest {
    @Test fun dropsCredentialsAndUnknownFieldsFromBackup() {
        val raw = LocalAccounts.empty().put("cookie", "private").put("token", "private")
        raw.getJSONObject("favorites").put("12", JSONObject().put("id", "12").put("message", "saved").put("cookie", "private"))
        val clean = LocalAccounts.validate(raw)
        assertFalse(clean.has("cookie"))
        assertFalse(clean.toString().contains("private"))
        assertEquals("saved", clean.getJSONObject("favorites").getJSONObject("12").getString("message"))
    }
    @Test fun rejectsMismatchWithoutChangingInput() {
        val raw = LocalAccounts.empty()
        raw.getJSONObject("follows").put("12", JSONObject().put("uid", "13"))
        val original = raw.toString()
        assertThrows(IllegalArgumentException::class.java) { LocalAccounts.validate(raw) }
        assertEquals(original, raw.toString())
    }
    @Test fun oldFormatBecomesIndependentProfile() {
        val raw = LocalAccounts.emptyProfile().put("version", 1)
        val clean = LocalAccounts.validate(raw)
        assertEquals(1, clean.getJSONArray("profiles").length())
        assertEquals("anon_1", clean.getString("activeProfileId"))
    }
    @Test fun duplicateIdsAndInvalidNamesAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { LocalAccounts.canonical(listOf(LocalAccounts.emptyProfile(), LocalAccounts.emptyProfile()), "anon_1") }
        assertThrows(IllegalArgumentException::class.java) { LocalAccounts.validate(LocalAccounts.empty().put("name", " ")) }
        assertThrows(IllegalArgumentException::class.java) { LocalAccounts.validate(LocalAccounts.empty().put("avatar", "malformed")) }
    }
    @Test fun cookieRequiresRealUidAndTokenAndRejectsInjection() {
        assertTrue(OfficialLoginSession.hasAccountCookie("uid=123; token=x=y; username=test"))
        listOf("uid=0; token=x", "uid=10000; token=x", "uid=abc; token=x", "uid=123; token=expired", "uid=123; token=x\nHeader: injected").forEach {
            assertFalse(it, OfficialLoginSession.hasAccountCookie(it))
        }
    }
}
