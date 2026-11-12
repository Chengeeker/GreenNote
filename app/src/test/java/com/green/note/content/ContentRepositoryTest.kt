package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ContentRepositoryTest {
    @Test fun notificationAndCommunityReplyListsAlsoKeepShortPagesAndTheFirstCursor() = kotlinx.coroutines.runBlocking {
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                val page = query.getValue("page")
                val root = JSONObject("""{"data":[{"id":"$page","entityType":"feed_reply","message":"短页"}]}""")
                if (page == "2") {
                    assertEquals("1", query["firstItem"]); assertEquals("1", query["lastItem"])
                    root.put("hasMore", false)
                }
                return root
            }
        }
        val repository = ContentRepository(api)
        for (path in listOf("/v6/feed/replyList", "/v6/feed/hotReplyList", "/v6/album/replyList")) {
            val request = ContentRequest(path, mapOf("id" to "7"))
            val first = repository.page(request, 1)
            assertTrue(first.more)
            val second = repository.page(request, 2, first.first, first.last)
            assertEquals("1", second.first); assertEquals("2", second.last)
            assertFalse(second.more)
        }
        assertFalse(repository.page(ContentRequest("/v6/user/feedList"), 1).more)
    }

    @Test fun routeDecodesQueryWithoutLosingEmbeddedFragments() {
        assertEquals(ContentRequest("/v6/page/dataList", mapOf("url" to "V11_VERTICAL_TOPIC", "title" to "话题")),
            contentRequest("/page?url=V11_VERTICAL_TOPIC&title=%E8%AF%9D%E9%A2%98"))
        assertEquals("#/feed/hotList", contentRequest("#/feed/hotList").query["url"])
        assertEquals("/v6/user/space", contentRequest("/user/space?uid=3").path)
        listOf("https://other.test/path", "//other.test/path").forEach { route ->
            assertThrows(IllegalArgumentException::class.java) { contentRequest(route) }
        }
    }
    @Test fun cardsOwnChildrenAndCursorTraversesInOrder() {
        val root = JSONObject("""{"data":[{"entityType":"card","id":"c","entities":[{"id":"first"},{"id":"last"}]}],"hasMore":"0"}""")
        val page = parsePage(root, 2)
        assertEquals(1, page.rows.size)
        assertEquals("first", page.first)
        assertEquals("last", page.last)
        assertFalse(page.more)
    }
    @Test fun feedsDeduplicateWithoutIncludingContainers() {
        val root = JSONObject("""{"data":[{"entityType":"card","id":"card","message":"heading","entities":[{"id":"1","message":"body"},{"id":"1","message":"body"}]}]}""")
        assertEquals(listOf("1"), extractFeeds(root).map { it.text("id") })
    }
    @Test fun explicitPaginationOverridesSizeAndFalseIsNotNull() {
        assertFalse(parsePage(JSONObject("""{"data":[{"id":"1"}],"hasMore":false,"has_more":true}"""), 1, allowShort = true).more)
        assertTrue(parsePage(JSONObject("""{"data":[{"id":"1"}],"hasMore":"1"}"""), 1).more)
    }
}
