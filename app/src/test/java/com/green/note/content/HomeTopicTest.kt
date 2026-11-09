package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HomeTopicTest {
    @Test fun topicKeywordsMustStayBehindPageDataList() {
        val request = homeTopicTarget("/page?url=%23%2Ftopic%2FtagList%3Fkeywords%3DC%2B%2B", "编程")
        assertEquals("/v6/page/dataList", request.path)
        assertEquals("#/topic/tagList?keywords=C++", request.query["url"])
        assertEquals("编程", request.query["title"])
        assertEquals("#/topic/tagList?keywords=a+b", homeTopicTarget("#/topic/tagList?keywords=a+b", "").query["url"])
    }
    @Test fun heatPreservesServerLabelsAndFormatsOnlyLargeNumbers() {
        assertEquals("1.2万", homeTopicHeat(JSONObject().put("hot_num", 12345)))
        assertEquals("9999", homeTopicHeat(JSONObject().put("hotNumTxt", "9999热度")))
        assertEquals("2.3万", homeTopicHeat(JSONObject().put("hot_num_txt", "2.3万 热度")))
        assertEquals("", homeTopicHeat(JSONObject()))
    }
    @Test fun mainChannelReentryRetainsCurrentGridButCategoryChangeStartsNewPage() = kotlinx.coroutines.runBlocking {
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?) =
                JSONObject("""{"data":[{"entityType":"topic","id":"one","title":"One"}],"hasMore":false}""")
        }
        val state = HomeTopicState(api)
        val first = homeTopicTarget("first", "First"); val other = homeTopicTarget("other", "Other")
        val grid = state.grid(first); grid.load()
        state.selected = 2
        assertSame(grid, state.grid(first)); assertEquals(1, state.grid(first).rows.size); assertEquals(2, state.selected)
        assertNotSame(grid, state.grid(other)); assertTrue(state.grid(other).rows.isEmpty())
    }
}
