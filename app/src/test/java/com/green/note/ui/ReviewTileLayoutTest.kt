package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class ReviewTileLayoutTest {
    @Test fun denseThreeLineUsesItsOwnBaselinesAndHeight() {
        val layout=reviewTileGeometry(20f,16f,30f,14f,4f,isThreeLine=true)
        assertEquals(76f,layout.height,0f)
        assertEquals(22f,layout.titleY+16f,0f)
        assertEquals(42f,layout.subtitleY+14f,0f)
    }
    @Test fun denseTwoLineTitlesKeepFlutterBaselines() {
        val layout=reviewTileGeometry(21.6f,16f,19.6f,14f,4f)
        assertEquals(64f,layout.height,0f)
        assertEquals(28f,layout.titleY+16f,0f)
        assertEquals(48f,layout.subtitleY+14f,0f)
    }
    @Test fun largeMultilineTextExpandsWithoutOverlappingOrClipping() {
        val layout=reviewTileGeometry(54f,20f,49f,18f,8f)
        assertEquals(119f,layout.height,0f)
        assertEquals(8f,layout.titleY,0f)
        assertEquals(62f,layout.subtitleY,0f)
        assertEquals(8f,layout.height-layout.subtitleY-49f,0f)
    }
    @Test fun oneLineTileRetainsDenseMinimumAtEveryDensity() {
        assertEquals(48f,reviewTileGeometry(20f,15f,null,0f,8f).height,0f)
        assertEquals(144f,reviewTileGeometry(60f,45f,null,0f,24f,3f).height,0f)
        assertEquals(76f,reviewTileGeometry(60f,45f,null,0f,8f).height,0f)
    }
}
