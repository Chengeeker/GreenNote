package com.green.note.content

import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HomeChannelsTest {
    @Test fun allOriginalChannelsImportWithoutSearchHistoryTwentyItemLimit() {
        val ids = ArrayList((defaultHomeChannels + moreHomeChannels).map(HomeChannel::id))
        assertEquals(22, ids.size)
        val bytes = ByteArrayOutputStream().apply { ObjectOutputStream(this).use { it.writeObject(ids) } }.toByteArray()
        val encoded = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu" + bytes.toByteString().base64()
        assertEquals(ids, SearchHistory.decodeLegacy(encoded, maxItems = 22))
        assertEquals(ids, restoreHomeChannels(SearchHistory.decodeLegacy(encoded, 22)).map(HomeChannel::id))
        try { SearchHistory.decodeLegacy(encoded); fail("Search history unexpectedly accepted a larger binary list") } catch (_: IllegalArgumentException) { }
    }

    @Test fun unknownLegacyChannelsNeverProduceAnEmptyPagerAndOriginalOrderIsRetained() {
        assertEquals(defaultHomeChannels, restoreHomeChannels(listOf("unknown")))
        assertEquals(listOf("photo", "headline", "latest"), restoreHomeChannels(listOf("photo", "unknown", "headline", "photo", "latest")).map(HomeChannel::id))
    }

    @Test fun mainInitSeparatesNamespacesAndPreservesOriginalRouteAliases() {
        val routes = parseMainTabRoutes(JSONObject("""{"data":[{"title":"首页TAB配置","entities":[{"title":"头条","url":"/removed"},{"title":"快讯","url":"/main/headline"},{"title":"话题","url":"/server/topic"}]},{"title":"发现","entities":[{"title":"好物","page_name":"/rank"},{"title":"二手","url":"/second"},{"title":"未知","url":"/unknown"}]},{"title":"首页","entities":[{"title":"关注","url":"/should-not-replace-first-config"}]}]}"""))
        assertEquals("/v6/main/headline", routes.home["headline"])
        assertEquals("/v6/main/headline", routes.home["news"])
        assertFalse(routes.home.containsKey("follow"))
        assertEquals(mapOf("好物榜" to "/rank", "二手" to "/second"), routes.discovery)
    }
}
