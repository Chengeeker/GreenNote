package com.green.note.content

import org.json.JSONObject

internal data class DiscoveryTile(val row: JSONObject, val imageIndex: Int) {
    val key: String = "${entityKey(row)}:$imageIndex"
    val urls: List<String> = feedImages(row).ifEmpty { listOf(row.text("message_cover", "cover", "pic")).filter(String::isNotEmpty) }
    val ratio: Float get() = discoveryPictureRatio(row, urls.getOrNull(imageIndex).orEmpty())
}

internal fun discoveryLanes(rows: List<JSONObject>, pictures: Boolean): List<List<DiscoveryTile>> {
    val lanes = List(if (pictures) 3 else 2) { mutableListOf<DiscoveryTile>() }
    val heights = DoubleArray(lanes.size)
    rows.forEachIndexed { index, row ->
        if (pictures) {
            val first = DiscoveryTile(row, 0)
            first.urls.indices.forEach { image ->
                val tile = if (image == 0) first else DiscoveryTile(row, image)
                val lane = heights.indices.minBy { heights[it] }
                lanes[lane].add(tile)
                heights[lane] += 1.0 / tile.ratio
            }
        } else lanes[index % 2].add(DiscoveryTile(row, 0))
    }
    return lanes
}
