package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream
import okio.ByteString.Companion.toByteString

class SearchDataTest {
    @Test fun hotGroupsSkipSponsorsAndKeywordsNeverIncludeGroupHeadings() {
        val value = JSONObject("""{"data":[{"title":"榜单","entities":[{"title":"甲","hotNum":"8万"},{"searchValue":"乙"},{"title":"广告","entityTemplate":"sponsorCard"}]},{"title":"广告组","sponsorType":1,"entities":[{"title":"隐藏"}]}]}""")
        val groups = SearchData.groups(value)
        assertEquals(listOf("榜单"), groups.map { it.title })
        assertEquals(listOf("甲", "乙"), groups.single().items.map(SearchData::title))
        assertEquals(listOf("甲", "乙"), SearchData.keywords(value))
    }
    @Test fun legacyHistorySupportsBothOriginalFormatsWithoutObjectDeserialization() {
        val values = arrayListOf("中文", "two", "中文", "three", "three")
        val bytes = ByteArrayOutputStream().apply { ObjectOutputStream(this).use { it.writeObject(values) } }.toByteArray()
        val prefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
        assertEquals(values, SearchHistory.decodeLegacy(prefix + bytes.toByteString().base64()))
        assertEquals(listOf("甲", "乙"), SearchHistory.decodeLegacy(prefix + "![\"甲\",\"乙\"]"))
        try { SearchHistory.decodeLegacy(prefix + "AAAA"); fail("malformed legacy history accepted") } catch (_: Exception) { }
    }
}
