package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CommunityFormTest {
    @Test fun movingAnItemPreservesItsIdentityRankAndSubmittedOrder() {
        val entries = listOf(AlbumItem("a", "甲", level = 5), AlbumItem("b", "乙", "说明", "image", 1))
        val moved = albumMoveUp(entries, 1)
        assertEquals(listOf("b", "a"), moved.map { it.id })
        assertEquals(listOf("a", "b"), entries.map { it.id })
        val form = albumForm("标题", "", moved, true, JSONObject("""{"entityType":"product","id":7}"""))
        assertEquals("1", form["productItems[0][level]"])
        assertEquals("说明", form["productItems[0][item_description]"])
        assertEquals("image", form["productItems[0][item_logo]"])
        assertEquals("0", form["productItems[0][display_order]"])
        assertEquals("product_phone", form["targetType"])
        assertEquals("7", form["targetId"])
        assertSame(entries, albumMoveUp(entries, 0))
    }
    @Test fun albumUsesOriginalIndexedFieldsAndValidatesRanks() {
        val form = albumForm(" 标题 ", "说明", listOf(AlbumItem("123", "产品", level = 5)), true, null)
        assertEquals("标题", form["title"])
        assertEquals("5", form["productItems[0][level]"])
        assertEquals("0", form["productItems[0][display_order]"])
        assertEquals("123", form["productItems[0][item_id]"])
        assertThrows(IllegalArgumentException::class.java) { albumForm("标题", "", listOf(AlbumItem(name = "x", level = 6)), true, null) }
        assertThrows(IllegalArgumentException::class.java) { albumForm("标题", "", emptyList(), false, null) }
    }
    @Test fun ownerCountsAndScoresWinOnlyWhenOwnerCountIsPositive() {
        val row = JSONObject("""{"owner_star_total_count":4,"owner_star_average_score":8.5,"star_total_count":10,"rating_average_score":7}""")
        assertEquals(4, ratingCount(row)); assertEquals(8.5, ratingScore(row), .001)
        row.put("owner_star_total_count", 0)
        assertEquals(10, ratingCount(row)); assertEquals(7.0, ratingScore(row), .001)
    }
}
