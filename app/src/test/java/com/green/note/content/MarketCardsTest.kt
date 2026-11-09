package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MarketCardsTest {
    @Test fun packagesAlbumsAndListsRemainDistinctAndInputIsNotMutated() {
        val apk=JSONObject("""{"entityType":"apk","id":"123","apkname":"example.package","url":"/apk/example.package"}""")
        val before=apk.toString();assertEquals("example.package",marketCardTarget(apk).text("id"));assertEquals(before,apk.toString())
        val album=marketCardTarget(JSONObject().put("url","/album/123"));assertEquals("album",album.text("entityType"));assertEquals("123",album.text("id"))
        listOf("/apk/recommendList","/album/list","#market_rank","/page?url=V8_MARKET_APP","/v6/apk/list").forEach{assertTrue(it,marketCardTarget(JSONObject().put("url",it)).optBoolean("_composeMarketList"))}
        assertFalse(marketCardTarget(JSONObject().put("url","https://example.test/")).optBoolean("_composeMarketList"))
    }
    @Test fun malformedRatiosAndVideoMetadataUseOriginalFallbacks() {
        assertEquals(2f,marketImageRatio(JSONObject().put("extraData","{\"dimensionRatio\":\"4:2\"}")),0f)
        for(ratio in listOf("0:1","1:0","NaN:2","Infinity:2","4","1:2:3"))assertEquals(16f/9f,marketImageRatio(JSONObject().put("extraDataArr",JSONObject().put("dimensionRatio",ratio))),0f)
        assertEquals(0,marketVideo(JSONObject().put("videoParams","{broken")).length())
        assertEquals("https://example.test/a.mp4",marketVideo(JSONObject().put("extraDataArr",JSONObject().put("videoParams","{\"url\":\"https://example.test/a.mp4\"}"))).text("url"))
        assertEquals("01:01:01",marketDuration("3661000"));assertEquals("00:00:00",marketDuration("invalid"))
    }
}
