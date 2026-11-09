package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AccountHomeTest {
    @Test fun shallowBlankFeedCountDoesNotErasePublicNestedCount() {
        val space = JSONObject().put("data", JSONObject().put("feed_num", "").put("userInfo", JSONObject().put("feed_num", "42").put("username", "甲")))
        val profile = JSONObject().put("data", JSONObject().put("fans_num", "8").put("userInfo", JSONObject().put("level", "6")))
        val merged = mergeAccountHomeProfile(space, profile)
        assertEquals("42", merged.getString("feed_num"))
        assertEquals("6", merged.getString("level"))
        assertEquals("8", merged.getString("fans_num"))
    }
}
