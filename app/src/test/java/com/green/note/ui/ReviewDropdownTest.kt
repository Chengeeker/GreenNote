package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class ReviewDropdownTest {
    @Test fun selectedItemIsVerticallyAlignedToItsAnchor() {
        val result=reviewDropdownPlacement(300f,356f,800f,5,2)
        assertEquals(200f,result.top,0f)
        assertEquals(256f,result.height,0f)
        assertEquals(328f,result.top+8+2*48+24,0f)
    }
    @Test fun edgePlacementClampsAndLongMenusRetainSelectedScroll() {
        val top=reviewDropdownPlacement(12f,68f,800f,5,4)
        assertEquals(12f,top.top,0f)
        val long=reviewDropdownPlacement(300f,356f,600f,20,10)
        assertEquals(504f,long.height,0f)
        assertTrue(long.scroll>0f)
        assertTrue(long.top>=0f)
        assertTrue(long.top+long.height<=600f)
    }
}
