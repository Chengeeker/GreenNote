package com.green.note.content

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NativeEntityDetailsTest {
    @Test fun onlyReleasedPhonesUseFourFooterActions() {
        fun labels(category: Int, released: Int, url: String = "", compare: Int = 0) =
            productFooterActions(JSONObject().put("category_id", category).put("release_status", released)
                .put("sell_url", url).put("is_can_compare", compare)).map { it.label }
        val store = "https://item.jd.com/123.html"
        assertEquals(listOf("对比", "关注", "打分", "购买"), labels(1000, 1))
        assertEquals(listOf("对比", "关注", "未发布"), labels(1000, 0, store, compare = 1))
        assertEquals(listOf("关注", "打分", "购买"), labels(1001, 1, store, compare = 1))
        assertEquals(listOf("关注", "打分"), labels(1005, 1))
        assertEquals(listOf("关注", "未发布"), labels(1001, 0, store, compare = 1))
    }

    @Test fun tabletUsesServerDimensionsInOrderWithOwnerScores() {
        val tablet = JSONObject("""{"category_id":1001,"rating_item_info":[
            {"id":"v4_score_item_1","name":"屏幕","average_score":"7.9","owner_average_score":"8.1"},
            {"id":"v4_score_item_2","name":"续航","average_score":"9.3","owner_average_score":"9.3"},
            {"id":"v4_score_item_7","name":"音质","average_score":"7.6","owner_average_score":"7.8"}
        ]}""")
        assertEquals(listOf("屏幕" to 8.1f, "续航" to 9.3f, "音质" to 7.8f), productDimensionScores(tablet))
    }

    @Test fun productRatingUsesPublishedOwnerDimensionsAndKeepsMissingScoresEmpty() {
        val detail = JSONObject("""{
            "owner_star_total_count":1551,"owner_star_average_score":"9.0","rating_average_score":"8.5",
            "rating_average_score_1":"0.0","score_battery":"7.3",
            "rating_item_info":[
                {"id":"v4_score_item_3","name":"性能","average_score":"9.0","owner_average_score":"9.3"},
                {"id":"v4_score_item_1","name":"续航","average_score":"9.3","owner_average_score":"9.6"},
                {"id":"v4_score_item_2","name":"影像","average_score":"7.2","owner_average_score":"7.4"},
                {"id":"v4_score_item_4","name":"屏幕","average_score":"8.7","owner_average_score":"9.0"},
                {"id":"v4_score_item_5","name":"外观质感","average_score":"8.7","owner_average_score":"9.0"},
                {"id":"v4_score_item_6","name":"性价比","average_score":"7.9","owner_average_score":"8.1"}
            ]
        }""")
        assertEquals(9.0, ratingScore(detail), 0.0)
        assertEquals(listOf(9.6f, 7.4f, 9.3f, 9f, 9f, 8.1f), productDimensionScores(detail).map { it.second })
        val partial = JSONObject("""{"rating_item_info":[{"name":"续航","owner_average_score":"0.0","average_score":"8.1"}],"score_2":"7.2","rating_average_score_3":"0.0"}""")
        assertEquals(listOf(8.1f, 7.2f, null, null, null, null), productDimensionScores(partial).map { it.second })
    }

    @Test fun selectorUsesServerFiltersSortsAndProductIdentity() {
        val html = """<div class="phone-item" data-product-id="42"><h3 class="phone-name"> A &amp; B </h3><div class="phone-image"><img src="//img.example/a.jpg"></div><div class="phone-price"> ¥ 1234 </div><div class="phone-specs"> chip | 6000mAh </div><div class="phone-specs-tags"><span class="tag-item">评分 9.1</span></div></div><div class="filter-section" data-group="brand"><div class="filter-section-title">品牌<svg>remove</svg></div><button class="filter-modal-item" data="a"> A </button></div><button class="filter-item" data="hot_num">热度</button><button class="filter-item" data="child">子项</button><button class="modal-item" data="score_1">续航</button>"""
        val result = NativeProductSource.parse(html)
        assertEquals("42", result.items.single().getString("id"))
        assertEquals("A & B", result.items.single().getString("title"))
        assertEquals("¥1234", result.items.single().getString("price"))
        assertEquals("品牌", result.filters.single().getString("title"))
        assertEquals(mapOf("hot_num" to "热度"), result.sorts)
        assertEquals("续航", result.subScores["score_1"])
    }
    @Test fun configFlattenPreservesSectionsArraysAndDepthBound() {
        val source = JSONObject().put("屏幕", JSONObject().put("尺寸", "6.3英寸").put("色彩", JSONArray(listOf("红", "蓝"))).put("其他", JSONObject().put("亮度", "1000")))
        val rows = productConfigRows(source)
        assertEquals(listOf("屏幕" to null, "尺寸" to "6.3英寸", "色彩" to "红、蓝", "其他 / 亮度" to "1000").toSet(), rows.toSet())
        assertEquals(4, rows.size)
    }
    @Test fun comparisonNeverFabricatesMissingHardware() {
        val empty = comparisonSpecs(JSONObject().put("id", "42"), JSONObject())
        assertTrue(empty.values.flatMap { it.values }.all(String::isEmpty))
        val actual = comparisonSpecs(JSONObject().put("battery", "6000mAh"), JSONObject().put("硬件", JSONObject().put("处理器", "真实芯片")))
        assertEquals("真实芯片", actual["性能"]?.get("芯片"))
        assertEquals("6000mAh", actual["续航"]?.get("电池"))
        assertFalse(actual.toString().contains("LPDDR5X"))
    }
    @Test fun metricsDoNotTreatUnavailableCountsAsNumbers() {
        assertEquals("约 5 万", EntityDetails.count("约 5 万"))
        assertEquals("1亿", EntityDetails.count("100000000"))
        assertEquals("23万", EntityDetails.count("230000"))
        assertEquals("今天", EntityDetails.update("100", 100000))
    }
    @Test fun specAliasesNormalizeNestedServerKeysAndIgnoreMissingValues() {
        val source = JSONObject().put("硬件", JSONObject().put("CPU_型号", "芯片甲").put("屏幕-尺寸", "6.3英寸").put("battery", "-"))
        assertEquals("芯片甲", productSpecValue(source, listOf("cpu型号", "processor")))
        assertEquals("6.3英寸", productSpecValue(source, listOf("屏幕尺寸")))
        assertEquals("", productSpecValue(source, listOf("battery")))
    }
}
