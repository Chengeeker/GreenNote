package com.green.note.content

import org.junit.Assert.*
import org.junit.Test

class MarketRequestTest {
    @Test fun recommendationDefaultsPreserveExplicitFilters() {
        assertEquals(ContentRequest("/v6/apk/recommendList", mapOf("apkType" to "1", "title" to "好软推荐")), marketRequest("/apk/recommendList"))
        assertEquals("2", marketRequest("/apk/recommendList?apkType=2").query["apkType"])
        assertEquals("V8_MARKET_GAME", marketRequest("/page?url=V8_MARKET_GAME").query["url"])
        assertEquals("#/apk/topList", marketRequest("#/apk/topList").query["url"])
    }
}
