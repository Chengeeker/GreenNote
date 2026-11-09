package com.green.note.ui

import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.junit.Assert.assertEquals
import org.junit.Test

class ReviewLinearDensityTest {
    @Test fun largeScoreUsesLinearConversionsThroughDensityInterface() {
        val density: Density = ReviewLinearDensity(3f, 1.2f)
        with(density) {
            assertEquals(45.6f, 38.sp.toDp().value, .0001f)
            assertEquals(136.8f, 38.sp.toPx(), .0001f)
            assertEquals(38f, 45.6.dp.toSp().value, .0001f)
            assertEquals(38f, 38.sp.toDp().toSp().value, .0001f)
            assertEquals(38f, 136.8f.toSp().value, .0001f)
        }
    }

    @Test fun normalAndReducedScaleKeepTheirLinearValuesWithoutChangingPhysicalDp() {
        for (scale in listOf(1f, .85f)) {
            val density: Density = ReviewLinearDensity(3f, scale)
            with(density) {
                assertEquals(38f * scale, 38.sp.toDp().value, .0001f)
                assertEquals(38f * scale * 3f, 38.sp.toPx(), .0001f)
                assertEquals(38f, 38.sp.toDp().toSp().value, .0001f)
                assertEquals(30f, 10.dp.toPx(), .0001f)
            }
        }
    }
}
