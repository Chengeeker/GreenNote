package com.green.note.ui

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReviewProgressTest {
    private fun fixture()=JSONObject(checkNotNull(javaClass.getResource("/progress/flutter_year2023.json")).readText())
    @Test fun circularMatchesDartPainterAcrossExpansionContractionAndIndependentRotations() {
        val samples=fixture().getJSONArray("circular")
        for(index in 0 until samples.length()) {
            val sample=samples.getJSONObject(index);val frame=ReviewProgressMotion.circular(sample.getDouble("ms"))
            assertEquals("start at ${sample.getDouble("ms")}",sample.getDouble("start").toFloat(),frame.startDegrees,.0001f)
            assertEquals("sweep at ${sample.getDouble("ms")}",sample.getDouble("sweep").toFloat(),frame.sweepDegrees,.0001f)
        }
    }
    @Test fun linearMatchesAllFourFlutterCubicIntervalsAndWrapsAt1800ms() {
        val samples=fixture().getJSONArray("linear")
        for(index in 0 until samples.length()) {
            val sample=samples.getJSONObject(index);val frame=ReviewProgressMotion.linear(sample.getDouble("ms"))
            assertEquals(sample.getDouble("firstHead").toFloat(),frame.firstHead,.000001f)
            assertEquals(sample.getDouble("firstTail").toFloat(),frame.firstTail,.000001f)
            assertEquals(sample.getDouble("secondHead").toFloat(),frame.secondHead,.000001f)
            assertEquals(sample.getDouble("secondTail").toFloat(),frame.secondTail,.000001f)
        }
    }
    @Test fun determinateArcClampsAndRetainsFlutterEpsilonInsteadOfDrawingFullCircle() {
        assertEquals(0f,ReviewProgressMotion.circular(1000.0,-1f).sweepDegrees,0f)
        val full=ReviewProgressMotion.circular(1000.0,2f)
        assertEquals(-90f,full.startDegrees,0f)
        assertEquals(359.9427f,full.sweepDegrees,.0001f)
        assertEquals(full.sweepDegrees/2,ReviewProgressMotion.circular(0.0,.5f).sweepDegrees,.0001f)
    }
}
