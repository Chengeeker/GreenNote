package com.green.note.settings

import org.junit.Assert.assertEquals
import org.junit.Test

class CacheSegmentTest {
    @Test fun tinyNonzeroCategoryKeepsOriginalMinimumUnit(){
        val stats=CacheStats(images=999999,network=1)
        assertEquals(999f,stats.segmentWeight(stats.images),0f)
        assertEquals(1f,stats.segmentWeight(stats.network),0f)
        assertEquals(0f,stats.segmentWeight(0),0f)
        assertEquals(0f,CacheStats().segmentWeight(1),0f)
    }
}
