package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ContentProtocolTest {
    @Test fun videoKeepsProviderRequestsAndResolvesLocalVideo() {
        val remote = feedVideo(JSONObject("""{"id":"7","username":"author","media_info":{"requestParams":{"provider":{"fromType":"weibo","id":"abc"}}}}"""))!!
        assertEquals("weibo", JSONObject(remote.getString("requestParams")).getString("fromType"))
        assertEquals("author", remote.getString("author"))
        val local = feedVideo(JSONObject("""{"media_info":{"requestParams":{"fromType":"localVideo","0":"https://example.test/video.mp4"}}}"""))!!
        assertEquals("https://example.test/video.mp4", local.getString("url"))
        assertEquals("", local.getString("requestParams"))
        assertNull(feedVideo(JSONObject("""{"message":"ordinary message","url":"https://example.test/article"}""")))
    }
    @Test fun chatHidesMetadataAndKeepsPrivateImageEndpoint() {
        assertEquals("follow", chatKind(JSONObject("""{"entityType":"messageExtra","entityTemplate":"float"}""")))
        assertEquals("hidden", chatKind(JSONObject("""{"entityType":"card","message":"not a chat"}""")))
        assertEquals("https://api.coolapk.com/v6/message/showImage?id=35&type=n", chatPicture(JSONObject("""{"id":"35","message_pic":"private-token"}""")))
        assertEquals("", chatPicture(JSONObject("""{"pic":"javascript:alert(1)"}""")))
        assertNotEquals(chatKey(JSONObject("""{"entityType":"messageExtra","entityId":"a","title":"same"}""")), chatKey(JSONObject("""{"entityType":"messageExtra","entityId":"b","title":"same"}""")))
    }
    @Test fun articleKeepsImageOrderCaptionsAndRejectsUnsafeLinks() {
        val row = JSONObject("""{"message_raw_output":[{"type":"text","message":"before"},{"type":"image","url":"https://example.test/a.jpg","description":"caption"},{"type":"shareUrl","url":"javascript:alert(1)"},{"type":"text","message":"after"}]}""")
        val result = articleParts(row)
        assertEquals(listOf("text", "image", "text"), result.map { it.type })
        assertEquals("caption", result[1].caption)
        assertFalse(validWebUrl("https://user:secret@example.test/x"))
        assertFalse(validWebUrl("file:///private/data"))
    }
    @Test fun chatImageFallbackUsesOriginalNetworkImageNormalization() {
        mapOf("http://image.coolapk.com/a.jpg" to "https://image.coolapk.com/a.jpg",
            "//image.coolapk.com/a.jpg" to "https://image.coolapk.com/a.jpg",
            "image.coolapk.com/a.jpg" to "https://image.coolapk.com/a.jpg",
            "/v6/message/showImage?id=7" to "https://api.coolapk.com/v6/message/showImage?id=7",
            "2026/11/a.jpg" to "https://image.coolapk.com/2026/11/a.jpg").forEach { (raw, expected) ->
            assertEquals(expected, chatPicture(JSONObject().put("pic", raw)))
        }
        assertEquals("", chatPicture(JSONObject().put("pic", "https://user:secret@example.test/a.jpg")))
        assertEquals("", chatPicture(JSONObject().put("pic", "file:///private/a.jpg")))
        assertEquals("https://api.coolapk.com/v6/message/showImage?id=35&type=n", chatPicture(JSONObject().put("id", "35").put("message_pic", "http://example.test/a.jpg")))
    }
    @Test fun pollPreservesIndexedFieldsAndExistingVoteFlags() {
        assertEquals(mapOf("id" to "12", "anonymous_status" to "1", "select_option[0]" to "4", "select_option[1]" to "9"), voteForm("12", listOf("4", "9"), true))
        assertTrue(hasVoted(JSONObject("""{"user_vote":["4"]}""")))
        assertFalse(hasVoted(JSONObject("""{"user_vote":[]}""")))
    }
    @Test fun digitalTabsHonorServerSelectionWithoutFlatteningProductCards() {
        val result = digitalTabs(JSONObject("""{"data":[{"entityTemplate":"iconTabLinkGridCard","extraData":"{\"selectedTab\":0}","entities":[{"title":"old","url":"/page?a"},{"title":"selected","url":"/page?b","selected":1}]}]}"""), true)
        assertEquals(2, result.first.size)
        assertEquals(1, result.second)
        val route = digitalCategoryUrl(JSONObject("""{"id":"1001"}"""), "评分")
        assertTrue(route.contains("id%3D1001"))
        assertTrue(route.contains("limitField%3Downer_star_total_count-80"))
        assertEquals(19, profileTabs("3", true).size)
    }
    @Test fun topicRoutesKeepOriginalSortAndVersionBoundaries() {
        val plain = topicProfile("风光摄影")
        assertFalse(plain.optBoolean("hasRating"))
        assertEquals("hot", topicRequest("风光摄影", plain, 0, "default", "").query["listType"])
        assertEquals("lastupdate_desc", topicRequest("风光摄影", plain, 2, "default", "").query["listType"])
        val system = topicProfile("ColorOS 16")
        assertTrue(system.optBoolean("isSystem"))
        assertEquals("OPPO", topicRequest("ColorOS 16", system, 2, "default", "").query["searchValue"])
        assertEquals("/v6/page/dataList", topicRequest("ColorOS 16", system, 3, "hot", "77").path)
        assertEquals("77", topicRequest("ColorOS 16", system, 3, "hot", "77").query["id"])
        assertEquals("hyperos" to "3", systemIdentity("小米 澎湃OS 3"))
        assertNotEquals(systemIdentity("ColorOS 15"), systemIdentity("ColorOS 16"))
        assertNull(systemIdentity("OPPO Find X9"))
    }
    @Test fun publicProfileTabsAndGenderAgeFollowTheOfficialHeaderOrder() {
        val tabs = profileTabs("3", false)
        assertEquals(listOf("主页", "动态", "点评", "图文", "问答", "酷图", "二手"), tabs.take(7).map { it.first })
        assertEquals("/v6/user/replyList", tabs.first { it.first == "回复" }.second?.path)
        val user = JSONObject("""{"gender":0,"birth_year":1998,"astro":"处女座","logintime":"4小时前"}""")
        assertEquals(listOf("♀ 95后" to "female", "处女座" to "", "4小时前活跃" to ""), profileChips(user))
    }
    @Test fun profileFlingKeepsSlowGesturesAndCompressesFastOnesInDp() {
        assertEquals(500f, profileFlingVelocity(500f, 3.5f), 1f)
        val medium = profileFlingVelocity(6000f, 3.5f)
        val fast = profileFlingVelocity(12000f, 3.5f)
        assertTrue(fast > medium && fast < medium * 2)
        assertEquals(-fast, profileFlingVelocity(-12000f, 3.5f), .01f)
        assertEquals(profileFlingVelocity(12000f / 3.5f, 1f), fast / 3.5f, .01f)
        assertTrue(profileFlingVelocity(100000f, 3.5f) <= 3600f * 3.5f)
    }
    @Test fun mixedImageMetadataRetainsOnlyAddressesAndStableOrder() {
        val row = JSONObject("""{"picArr":[{"url":"https://a.test/1"},"https://a.test/2"],"imageUriList":[{"image":"https://a.test/3"}],"pic":"https://a.test/2,https://a.test/4"}""")
        assertEquals(listOf("https://a.test/1", "https://a.test/2", "https://a.test/3", "https://a.test/4"), feedImages(row))
    }
    @Test fun discoveryFlexRoutesDoNotSendExternalPagesAsApiRequests() {
        assertEquals(ContentRequest("/v6/user/dyhSubscribe"), discoveryRequest("/user/dyhSubscribe"))
        assertEquals("#/feed/hotList", discoveryRequest("#/feed/hotList").query["url"])
        assertEquals("/feed/list?uid=", discoveryRequest("/feed/list?uid=\${uid}").query["url"])
        assertEquals("activities", homeDestination("", "/page?url=V11_ACTIVITIES")?.kind)
        assertNull(homeDestination("unrelated", "/page?url=unknown"))
        assertFalse(isActivityDocument("https://evil.test/activity/1"))
        assertTrue(isActivityDocument("https://m.coolapk.com/activity/1"))
    }
    @Test fun emotionAliasesKeepSourceCodesAndNumericBounds() {
        assertEquals("c-huaji", contentEmojiCode("[手动滑稽]"))
        assertEquals("c-100", contentEmojiCode("100"))
        assertNull(contentEmojiCode("101"))
    }
}
