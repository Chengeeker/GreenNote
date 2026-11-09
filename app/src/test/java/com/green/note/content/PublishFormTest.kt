package com.green.note.content

import org.junit.Assert.*
import org.junit.Test

class PublishFormTest {
    @Test fun voteRejectsDuplicatesBeforeFormCreation() {
        val vote = PublishForm("vote", "说明", "标题", voteOptions = listOf(" A ", "A"))
        assertEquals("投票选项不能重复", vote.validationError())
        assertThrows(IllegalStateException::class.java) { vote.body(100) }
    }
    @Test fun voteMatchesOriginalFieldProtocol() {
        val body = PublishForm("vote", "说明", "标题", voteOptions = listOf(" A ", "B"), voteDays = 7).body(100)
        assertEquals("标题", body["message"])
        assertEquals("说明", body["vote_message"])
        assertEquals("604900", body["vote_end_time"])
        assertEquals("A", body["vote_option[0]"])
        assertEquals("1", body["vote_max_select_num"])
    }
    @Test fun picturesAndSecondHandValidateBeforePosting() {
        assertNotNull(PublishForm("picture", "", pictures = listOf("url")).validationError())
        assertNotNull(PublishForm("ershou", "描述", "标题", listOf("url"), price = "NaN").validationError())
        val body = PublishForm("picture", "", pictures = listOf("https://test/p.jpg"), category = "数码日常").body(0)
        assertEquals("分享图片", body["message"])
        assertEquals("数码日常", body["tag"])
    }
}
