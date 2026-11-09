package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AccountTopicDataTest {
    @Test fun countsStripOnlySourceSuffixAndUseTenThousandThreshold() {
        assertEquals("1.0万", accountCount(JSONObject().put("count", "10000条动态"), "count"))
        assertEquals("12000", accountCount(JSONObject().put("count", "12000讨论"), "count", compact = false))
        assertEquals("讨论热度", accountCount(JSONObject().put("count", "讨论热度"), "count"))
    }
    @Test fun categoryUsesDeclaredThenTargetThenEntityThenUrl() {
        assertEquals("数码", accountCategory(JSONObject().put("url", "#/product/123")))
        assertEquals("用户", accountCategory(JSONObject().put("target_type", "user").put("entityType", "apk")))
        assertEquals("话题", accountCategory(JSONObject().put("typeName", "话题").put("targetType", "user")))
    }
}
