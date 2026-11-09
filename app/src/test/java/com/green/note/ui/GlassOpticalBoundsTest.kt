package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class GlassOpticalBoundsTest {
    @Test fun lensCentreTracksEveryNavigationSlotAndNeverTheAtlasCentre() {
        for(x in listOf(20f,100f,260f,340f)) {
            val bounds=GlassOpticalBounds.from(x,20f,x+72f,68f,1f)
            assertEquals(.5f,bounds.normalized(x+36f,44f).first,.00001f)
            assertEquals(.5f,bounds.normalized(x+36f,44f).second,.00001f)
            assertEquals(26f,bounds.maximumRefractionReach,.00001f)
        }
    }
    @Test fun physicalBorderAndReachScaleWithDensity() {
        val one=GlassOpticalBounds.from(20f,20f,92f,68f,1f)
        val three=GlassOpticalBounds.from(60f,60f,276f,204f,3f)
        assertEquals(one.left*3,three.left,.00001f)
        assertEquals(one.width*3,three.width,.00001f)
        assertEquals(one.maximumRefractionReach*3,three.maximumRefractionReach,.00001f)
    }
    @Test fun expansionChangesTheLensExtentWhileKeepingItsCentreStable() {
        val rest=GlassOpticalBounds.from(100f,20f,172f,68f,1f)
        val expanded=GlassOpticalBounds.from(88f,12f,184f,76f,1f)
        assertEquals(rest.normalized(136f,44f),expanded.normalized(136f,44f))
        assertTrue(expanded.maximumRefractionReach>rest.maximumRefractionReach)
    }
}
