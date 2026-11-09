package com.green.note.content

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class RatingSquareTest {
    @Test fun titleCardsCollectOnlyConsecutiveNodesWithoutMutatingTheResponse() {
        val title = JSONObject().put("entityTemplate", "titleCard").put("title", "机型").put("entities", JSONArray())
        val node = JSONObject().put("id", "1").put("entityType", "product")
        val other = JSONObject().put("entityType", "banner").put("id", "2")
        val trailing = JSONObject().put("entityType", "topic").put("id", "3")
        val cards = ratingCards(listOf(JSONObject().put("entityTemplate", "configCard"), title, node, other, trailing))
        assertEquals(3, cards.size)
        assertEquals("1", cards.first().getJSONArray("entities").getJSONObject(0).getString("id"))
        assertEquals(0, title.getJSONArray("entities").length())
        assertEquals("3", cards.last().getString("id"))
    }
    @Test fun deviceMatchingNormalizesOnlyVersionZeroSuffixAndWhitespace() {
        assertEquals(ratingDeviceKey("OriginOS 7.0", true), ratingDeviceKey("originos7", true))
        assertNotEquals(ratingDeviceKey("OriginOS 7.1", true), ratingDeviceKey("OriginOS 7", true))
        assertNotEquals(ratingDeviceKey("Phone 7.0", false), ratingDeviceKey("Phone 7", false))
        assertEquals("phone7pro", ratingDeviceKey("Phone 7 Pro", false))
    }
    @Test fun ownerStatisticsTakePrecedenceOnlyWhenOwnersExist() {
        val row = JSONObject().put("owner_star_total_count", 3).put("owner_star_average_score", 9.2).put("star_total_count", 10).put("rating_average_score", 8.1)
        assertEquals(3, ratingCount(row)); assertEquals(9.2, ratingScore(row), .001)
        row.put("owner_star_total_count", 0)
        assertEquals(10, ratingCount(row)); assertEquals(8.1, ratingScore(row), .001)
    }
}
