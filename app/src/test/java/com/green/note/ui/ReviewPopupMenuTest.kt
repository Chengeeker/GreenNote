package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class ReviewPopupMenuTest {
    @Test fun intrinsicMenuWidthUsesFlutterFiftySixDpStepsAndBounds() {
        assertEquals(112,popupSteppedWidth(60,1f,500))
        assertEquals(168,popupSteppedWidth(113,1f,500))
        assertEquals(280,popupSteppedWidth(400,1f,500))
        assertEquals(336,popupSteppedWidth(226,2f,1000))
        assertEquals(90,popupSteppedWidth(200,1f,90))
    }
    @Test fun closingUsesFlutterReverseIntervalBeforeOpacityAndSizeIntervals() {
        assertEquals(.5f,popupRouteProgress(.5f,true),0f)
        assertEquals(1f,popupRouteProgress(.8f,false),0f)
        assertEquals(.75f,popupRouteProgress(.5f,false),.0001f)
        assertEquals(.3f,popupRouteProgress(.2f,false),.0001f)
        assertEquals(.9f,popupInterval(popupRouteProgress(.2f,false),0f,1f/3f),.0001f)
        assertEquals(0f,popupInterval(.1f,.25f,.625f),0f)
        assertEquals(1f,popupInterval(.625f,.25f,.625f),0f)
    }
}
