package com.green.note.content

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TodayHeadlineCardsTest {
    private fun card(title:String,template:String="iconGridCard",vararg children:JSONObject)=JSONObject().put("title",title).put("entityTemplate",template).put("entities",JSONArray(children.toList()))
    @Test fun originalNoticeAndTopicPriorityWinsOverGridTemplates() {
        val image=JSONObject().put("pic","https://example.test/a.jpg")
        assertEquals(TodayCardKind.NOTICE,todayCardKind(card("<b>爆料信息不一定准确</b>","imageTextGridCard",image)))
        assertEquals(TodayCardKind.TOPICS,todayCardKind(card("🔥今日话题","imageTextGridCard",image)))
        assertEquals(TodayCardKind.FEATURES,todayCardKind(card("专题","iconLinkGridCard",image)))
        assertEquals(TodayCardKind.GENERAL,todayCardKind(card("今日话题")))
    }
    @Test fun imageGridRequiresOriginalAliasAndNullableFallbackSemantics() {
        val emptyFirst=JSONObject().put("pic","").put("logo","https://example.test/logo")
        assertEquals("",todayFeatureImage(emptyFirst))
        assertEquals(TodayCardKind.GENERAL,todayCardKind(card("推荐","iconGridCard",emptyFirst)))
        assertEquals(TodayCardKind.FEATURES,todayCardKind(card("推荐","imageTextGridCard",emptyFirst)))
        assertEquals(TodayCardKind.FEATURES,todayCardKind(card("推荐","iconMiniGridCard",JSONObject().put("feed_pic","/a.jpg"))))
        assertEquals(TodayCardKind.GENERAL,todayCardKind(card("推荐","imageTextGridCard")))
    }
    @Test fun serverColorsPreserveArgbAndFallbackSequence() {
        assertEquals(0xFF123456L,todayFeatureColor(JSONObject().put("bgColor",0x123456),0))
        assertEquals(0x80123456L,todayFeatureColor(JSONObject().put("bg_color","#80123456"),0))
        assertEquals(0xFFABCDEF,todayFeatureColor(JSONObject().put("backgroundColor","abcdef"),0))
        assertEquals(0xFF496236L,todayFeatureColor(JSONObject().put("color","invalid"),5))
    }
    @Test fun topicTagsAndHeadlineLinksKeepOriginalRoutingWithoutMutatingRows() {
        assertEquals("A+B",todayTopicTag(JSONObject().put("url","/t/A+B")))
        assertEquals("测试",todayTopicTag(JSONObject().put("url","/t/%E6%B5%8B%E8%AF%95?type=hot")))
        assertEquals("备用",todayTopicTag(JSONObject().put("url","/t/123").put("tagName","#备用#")))
        val raw=JSONObject().put("title","#今日话题#").put("targetType","topic").put("href","#/page?url=V9_NEWS_TEST")
        val before=raw.toString();val target=todayHeadlineTarget(raw)
        assertEquals(before,raw.toString());assertEquals("topic",target.text("entityType"));assertEquals("今日话题",target.text("tag"))
        assertEquals("https://example.test/",todayHeadlineTarget(JSONObject().put("goods_buy_url","https://example.test/")).text("url"))
    }
}
