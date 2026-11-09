package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DiscoveryLanesTest {
    private fun picture(id: String, size: String) = JSONObject().put("entityType", "feed").put("id", id).put("pic", "https://example.test/$id@$size.jpg")

    @Test fun picturesUseMetadataHeightsWithStableFirstLaneTies() {
        val rows = listOf(picture("1", "200x100"), picture("2", "100x200"), picture("3", "100x100"), picture("4", "200x100"), picture("5", "100x200"))
        val lanes = discoveryLanes(rows, true)
        assertEquals(listOf(listOf("1", "4", "5"), listOf("2"), listOf("3")), lanes.map { lane -> lane.map { it.row.getString("id") } })
        val appended = discoveryLanes(rows + picture("6", "100x100"), true)
        lanes.indices.forEach { assertEquals(lanes[it].map { tile -> tile.key }, appended[it].take(lanes[it].size).map { tile -> tile.key }) }
    }

    @Test fun tradingCardsStayInAlternatingColumnsRegardlessOfImageHeight() {
        val lanes = discoveryLanes(listOf(picture("1", "1x9"), picture("2", "9x1"), picture("3", "1x1")), false)
        assertEquals(listOf(listOf("1", "3"), listOf("2")), lanes.map { lane -> lane.map { it.row.getString("id") } })
    }
}
