package com.green.note.content

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CrowdTestActionTest {
    @Test fun nativeActionMatchesOriginalDartBoundaries() {
        val source = requireNotNull(javaClass.getResourceAsStream("/crowd-test-action-fixtures.json")).bufferedReader().use { it.readText() }
        val fixtures = JSONArray(source)
        assertEquals(20, fixtures.length())
        for (i in 0 until fixtures.length()) {
            val fixture = fixtures.getJSONObject(i)
            val expected = fixture.getJSONObject("expected")
            val actual = crowdTestAction(fixture.getJSONObject("event"), fixture.getLong("now"))
            assertEquals(fixture.getString("name"), CrowdTestAction(expected.getString("label"), expected.getBoolean("canRegister"), expected.getString("actionUrl"), expected.getString("winnersUrl")), actual)
        }
    }
    @Test fun invalidTimesAndCredentialBearingUrlsCannotRegister() {
        assertEquals(12L, eventTime(JSONObject().put("a", "0").put("b", "9223372036854775808").put("c", "12"), "a", "b", "c"))
        assertNull(eventTime(JSONObject().put("a", -1), "a"))
        assertFalse(validCrowdTestRegistrationUrl("https://account:password@example.test/form"))
        assertFalse(validCrowdTestRegistrationUrl("//example.test/form"))
        assertTrue(validCrowdTestRegistrationUrl("https://m.coolapk.com/activity/register?id=7"))
    }
}
