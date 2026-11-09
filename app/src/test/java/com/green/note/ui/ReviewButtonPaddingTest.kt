package com.green.note.ui
import org.junit.Assert.assertEquals
import org.junit.Test
class ReviewButtonPaddingTest {
    @Test fun originalPaddingInterpolatesAtOneTwoAndThreeTimesDefaultLabel(){
        assertEquals(24f,reviewButtonPadding(.8f,24f,12f,6f),0f)
        assertEquals(18f,reviewButtonPadding(1.5f,24f,12f,6f),0f)
        assertEquals(12f,reviewButtonPadding(2f,24f,12f,6f),0f)
        assertEquals(9f,reviewButtonPadding(2.5f,24f,12f,6f),0f)
        assertEquals(6f,reviewButtonPadding(4f,24f,12f,6f),0f)
    }
}
