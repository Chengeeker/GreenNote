package com.green.note.ui
import org.junit.Assert.*
import org.junit.Test
class ReviewSwitchMotionTest {
    @Test fun originalThumbPassesThroughWideMiddleAndOvershootsTrack(){
        assertEquals(16f,ReviewSwitchMotion.thumb(0f,true).width,0f)
        assertEquals(34f,ReviewSwitchMotion.thumb(.11f,true).width,.0001f)
        assertEquals(22f,ReviewSwitchMotion.thumb(.11f,true).height,.0001f)
        assertEquals(24f,ReviewSwitchMotion.thumb(1f,true).width,0f)
        assertEquals(34f,ReviewSwitchMotion.thumb(.89f,false).width,.0001f)
        assertTrue(ReviewSwitchMotion.position(.7f,true)>1f)
        assertEquals(1-ReviewSwitchMotion.position(.7f,true),ReviewSwitchMotion.position(.3f,false),.0001f)
    }
}
