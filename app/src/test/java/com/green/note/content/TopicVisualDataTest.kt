package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TopicVisualDataTest {
    @Test fun creatorReadsNestedUserAndKeepsLegacyStringFallback() {
        val creator = JSONObject().put("userAvatar", "https://example.com/creator.jpg")
            .put("userInfo", JSONObject().put("username", "话题创建者"))
        val row = JSONObject().put("creator", creator).put("username", "话题管理者")
        assertEquals("话题创建者" to "https://example.com/creator.jpg", topicCreator(row))
        assertEquals("" to "", topicCreator(row.put("hidden_creator", 1)))
        assertEquals("话题管理者" to "", topicCreator(row.put("hidden_creator", 0).put("creator", JSONObject())))
        assertEquals("旧版创建者" to "https://example.com/legacy.jpg", topicCreator(JSONObject()
            .put("creator", "旧版创建者").put("creator_avatar", "https://example.com/legacy.jpg")))
    }

    @Test fun emptyStatisticsDoNotCreateSeparatorsOrInventCounts() {
        assertEquals("", topicStats(JSONObject()))
        assertEquals("3 关注", topicStats(JSONObject().put("follow_num", "3")))
        assertEquals("1.5万 讨论", topicStats(JSONObject().put("feed_num", "15000")))
        assertEquals("10000 关注 · 8 讨论", topicStats(JSONObject().put("follow_num", "10000").put("feedNum", "8")))
    }

    @Test fun topicProfilesKeepOriginalActivityLabelsButNoFabricatedScores() {
        val profile = topicProfile("OriginOS 6")
        assertEquals("OriginOS 6原子岛与蓝心小V体验征集", profile.getString("activityTitle"))
        assertFalse(profile.has("score"))
        assertFalse(profile.has("dimensionScores"))
        assertFalse(topicProfile("普通话题").has("activityTitle"))
    }
}
