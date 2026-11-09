package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TopicVisualDataTest {
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
