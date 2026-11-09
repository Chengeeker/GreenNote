package com.green.note.content

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HomeFeedHeaderTest {
    @Test fun originalDefaultNavigationAndDispatchAreRetained() {
        val expected=JSONObject(javaClass.classLoader!!.getResourceAsStream("home-header-defaults.json")!!.bufferedReader().readText())
        for(channel in listOf("headline","hot","tutorial","video"))assertEquals(expected.getJSONArray(channel).toString(),JSONArray(homeHeaderDefaults(channel)).toString())
        assertEquals(listOf("carousel","iconPages","mini"),homeHeaderParts("headline",emptyList()).map{it.kind})
        assertEquals(listOf("rank","news","capsules","selector"),homeHeaderParts("hot",emptyList()).map{it.kind})
        val server=JSONObject().put("entityTemplate","iconGridCard").put("entities",JSONArray().put(JSONObject().put("title","server")))
        assertSame(server,homeHeaderParts("headline",listOf(server))[1].cards.single())
        val feed=JSONObject().put("entityType","feed")
        val empty=JSONObject().put("entityTemplate","iconMiniScrollCard").put("entities",JSONArray())
        val banner=JSONObject().put("entityTemplate","image_1").put("entities",JSONArray())
        assertEquals(listOf("carousel"),homeHeaderParts("other",listOf(feed,empty,banner)).map{it.kind})
    }
    @Test fun dartStringHashMatchesActualRetainedDartRuntime() {
        val vectors=mapOf("荣耀Magic7" to 280391720,"周鸿祎" to 546136364,"华为Mate70" to 91716890,"百瓦快充" to 239661052,"苹果优惠" to 670430271,"鸿蒙NEXT" to 1000163861,"a" to 170824770,"abc" to 756227931,"iPhone" to 549460473,"#" to 1058995764,"😀" to 472421242)
        vectors.forEach{(value,hash)->assertEquals(value,hash,homeDartStringHash(value))}
    }
    @Test fun newsNestedImagesAndTagAliasesFollowOriginalFallbackOrder() {
        val row=JSONObject().put("title","").put("url","/t/%E5%8D%8E%E4%B8%BAMate70?foo=1").put("pic","ignored.gif").put("target_row",JSONObject().put("logo","nested.png"))
        assertEquals("华为Mate70",homeNewsTitle(row,0));assertEquals("华为Mate70",homeNewsTag(row,homeNewsTitle(row,0)));assertEquals("nested.png",homeNewsImage(row))
        assertEquals("荣耀WIN2",homeNewsTag(JSONObject(),"最新荣耀WIN2消息"))
        assertEquals("exact",homeNewsTag(JSONObject().put("tag","#exact#"),"华为"))
        assertEquals("ABC+DEF",homeNewsTag(JSONObject().put("url","/t/ABC+DEF"),""))
        assertEquals("nested",homeNewsTag(JSONObject().put("targetRow",JSONObject().put("title","#nested#")),""))
        assertEquals("荣耀Magic7",homeNewsTitle(JSONObject(),0))
    }
    @Test fun carouselUsesOnlyImageChildrenAndOriginalFallback() {
        val card=JSONObject().put("pic","parent.jpg").put("entities",JSONArray().put(JSONObject().put("title","empty")).put(JSONObject().put("image","child.jpg")))
        assertEquals(listOf("child.jpg"),homeCarouselItems(listOf(card)).map{it.text("image")})
        assertEquals(2,homeCarouselItems(listOf(JSONObject().put("entities",JSONArray()))).size)
    }
}
