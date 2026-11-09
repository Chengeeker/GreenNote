package com.green.note.content

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ArticlePreviewTest {
    @Test fun previewStopsAtVisibleLimitWithoutBreakingLinksOrSurrogates() {
        val raw = "<p><a href=\"/t/topic\">" + "😀".repeat(1100) + "</a></p>" + "x".repeat(100_000)
        val clipped = clipContentPreview(raw, 1000)
        assertTrue(clipped.endsWith("</a>")); assertTrue(clipped.length < 2200)
        assertFalse(clipped.contains("x")); assertFalse(Character.isHighSurrogate(clipped[clipped.length - 5]))
    }
    @Test fun imageOrderRetainsRepeatedUrlsAndIndicesInLongArticle() {
        val blocks = JSONArray()
        repeat(40) { index -> repeat(3) { blocks.put(JSONObject().put("type", "text").put("message", "paragraph $index")) }; blocks.put(JSONObject().put("type", "image").put("url", "https://example.test/${index % 2}.jpg").put("description", "$index")) }
        val parts = articleParts(JSONObject().put("message_raw_output", blocks))
        assertEquals(160, parts.size)
        val indices = articleImageIndices(parts)
        assertEquals((0..39).toList(), indices.filter { it >= 0 })
        assertEquals("https://example.test/0.jpg", parts[11].url)
        assertEquals("2", parts[11].caption)
    }
    @Test fun previewDropsScriptsAndPreservesCompleteEntities() {
        assertEquals("&amp;a", clipContentPreview("<script>fake</script>&amp;abcd", 2))
        assertEquals("", clipContentPreview("abc", 0))
    }
}
