package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class ReviewSliderGeometryTest {
    @Test fun originalDiscreteTrackPadsTickAndThumbButNotGestureRange(){
        assertEquals(26f,ReviewSliderGeometry.thumbX(200f,0f),0f)
        assertEquals(174f,ReviewSliderGeometry.thumbX(200f,1f),0f)
        assertEquals(.5f,ReviewSliderGeometry.fractionAt(200f,100f),0f)
        assertEquals(0f,ReviewSliderGeometry.fractionAt(200f,0f),0f)
        assertEquals(1.25f,ReviewSliderGeometry.discrete(5f,.8f..1.25f,9),.00001f)
        assertEquals(1f,ReviewSliderGeometry.discrete(.977f,.8f..1.25f,9),.00001f)
    }
    @Test fun valueIndicatorKeepsOriginalPaintWidthAndWindowShift(){
        assertEquals(40f,ReviewSliderGeometry.indicatorWidth(32f,1f),0f)
        assertEquals(20f,ReviewSliderGeometry.indicatorWidth(32f,.5f),0f)
        assertEquals(0f,ReviewSliderGeometry.labelShift(100f,200f,40f,1f),0f)
        assertEquals(18f,ReviewSliderGeometry.labelShift(10f,200f,40f,1f),0f)
        assertEquals(-18f,ReviewSliderGeometry.labelShift(190f,200f,40f,1f),0f)
    }
    @Test fun videoContinuousTrackDoesNotAddDiscreteEndPadding(){
        assertEquals(14f,ReviewSliderGeometry.thumbX(200f,0f,14f,3.5f,false),0f)
        assertEquals(186f,ReviewSliderGeometry.thumbX(200f,1f,14f,3.5f,false),0f)
        assertEquals(.5f,ReviewSliderGeometry.fractionAt(200f,100f,14f),0f)
    }
}
