package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class DetailEntryRegressionTest {
    @Test fun detailRetainsUsablePreviewFieldsAndReplacesFreshValues() {
        val seed = JSONObject("""{"id":"1","title":"Preview","message":"Excerpt","pic":"image.jpg","likenum":9}""")
        val detail = JSONObject("""{"id":"1","title":"","message":"Full article","pic":null,"likenum":0}""")
        val merged = mergeFeedDetail(seed, detail)
        assertEquals("Preview", merged.getString("title"))
        assertEquals("image.jpg", merged.getString("pic"))
        assertEquals("Full article", merged.getString("message"))
        assertEquals(0, merged.getInt("likenum"))
        assertEquals("Excerpt", seed.getString("message"))
    }

    @Test fun followedTopicsUsesPageDataListWithTheOriginalFragmentAndKeepsQuery() {
        val request = contentRequest("/v6/topic/myFollowTopicList?page=2&lastItem=42")
        assertEquals("/v6/page/dataList", request.path)
        assertEquals("#/topic/userFollowTagList?&title=我关注的话题", request.query["url"])
        assertEquals("2", request.query["page"])
        assertEquals("42", request.query["lastItem"])
    }
}
