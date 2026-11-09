package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ContentEntityTest {
    private fun row(type: String, id: String = "42") = JSONObject().put("entityType", type).put("id", id)

    @Test fun specialEntitiesReachExistingDetailPages() {
        mapOf("event" to "event", "eventDetail" to "event", "feedReply" to "reply_thread",
            "feed_reply" to "reply_thread", "rating" to "product", "productRating" to "product",
            "dyhItem" to "dyh", "user_follow" to "user", "category" to "raw").forEach { (type, destination) ->
            assertEquals(type, EntityDestination(destination, "42"), contentEntityDestination(row(type)))
        }
        assertEquals(EntityDestination("apk", "com.example.app"), contentEntityDestination(row("application").put("apk_name", "com.example.app")))
        assertEquals(EntityDestination("collection", "7"), contentEntityDestination(JSONObject().put("entityType", "collection").put("collectionId", "7")))
    }

    @Test fun authorUidNeverReplacesObjectIdentity() {
        listOf("feedReply", "product", "rating", "event", "dyh").forEach { type ->
            assertEquals(type, "42", contentEntityDestination(row(type).put("uid", "author"))!!.id)
        }
        assertEquals("author", contentEntityDestination(row("user_follow").put("uid", "author"))!!.id)
    }

    @Test fun genericMessageFieldDoesNotTurnUsersOrCollectionsIntoFeeds() {
        listOf("user", "collection", "feedReply", "rating").forEach { type ->
            assertFalse(type, contentEntityIsFeed(row(type).put("message", "description")))
        }
        listOf("feed", "feed_article", "dyhArticle").forEach { type ->
            assertEquals(EntityDestination("feed", "42"), contentEntityDestination(row(type).put("url", "/t/topic")))
        }
        assertTrue(contentEntityIsFeed(JSONObject().put("message", "ordinary feed")))
        assertEquals("10热度 · 20讨论", contentEntitySummary(row("product").put("hotNumTxt", "10").put("commentnum", "20")))
    }

    @Test fun topicIdentityUsesCanonicalNameInsteadOfNumericLink() {
        assertEquals(EntityDestination("topic", "风光摄影"), contentEntityDestination(row("topic_relation").put("url", "/t/123").put("tagName", "风光摄影")))
        assertEquals("风光摄影", carouselTopicTag(row("tag").put("url", "/t/%E9%A3%8E%E5%85%89%E6%91%84%E5%BD%B1?x=1")))
        assertEquals("测试话题", carouselTopicTag(row("topic").put("tag", "123").put("title", "测试话题")))
        assertEquals("", carouselTopicTag(row("topic").put("url", "/t/123").put("title", "123")))
    }

    @Test fun templateServerRoutesOnlyBecomeListsWhenIdentityIsAbsent() {
        val item = JSONObject().put("_composeApiTemplateItem", true).put("url", "V15_HOME_TAB_TEST")
        assertEquals("V15_HOME_TAB_TEST", contentTemplateListRoute(item))
        assertEquals("", contentTemplateListRoute(JSONObject(item.toString()).put("id", "42")))
        assertEquals("", contentTemplateListRoute(JSONObject(item.toString()).put("entityType", "topic")))
        assertEquals("", contentTemplateListRoute(JSONObject(item.toString()).put("url", "/t/话题")))
        assertEquals("", contentTemplateListRoute(JSONObject().put("url", "V15_HOME_TAB_TEST")))
    }

    @Test fun goodsMainLinkAndExplicitBuyLinkKeepTheirOwnTargets() {
        assertEquals("https://example.test/detail", contentGoodsTarget(JSONObject().put("goods_url", "https://example.test/detail").put("goods_buy_url", "https://example.test/buy")))
        assertEquals("https://example.test/buy", contentGoodsTarget(JSONObject().put("url", "https://example.test/buy")))
    }
}
