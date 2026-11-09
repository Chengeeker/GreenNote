package com.green.note.ui

import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import androidx.compose.ui.unit.dp
import org.junit.Assert.*
import org.junit.Test

class FractionalVerticalPaddingTest {
    private val scope = object : MeasureScope {
        override val density = 3f
        override val fontScale = 1f
        override val layoutDirection = LayoutDirection.Ltr
    }
    private val intrinsic = object : IntrinsicMeasureScope {
        override val density = 3f
        override val fontScale = 1f
        override val layoutDirection = LayoutDirection.Ltr
    }

    @Test fun sixActuallyMeasuredScoreRowsReserveNinePixelsEachWithoutLayers() {
        val positions = mutableListOf<IntOffset>()
        var measured = 0
        val child = child(onMeasure = { constraints ->
            measured++
            assertEquals(91, constraints.maxHeight)
        }, onPlace = { positions += it })
        val modifier = FractionalVerticalPadding(1.5.dp)
        val rows = List(6) { with(modifier) { scope.measure(child, Constraints(maxWidth = 220, maxHeight = 100)) } }
        assertEquals(6, measured)
        assertEquals(324, rows.sumOf { it.height }) // 6 * (45px label + 9px padding), not 330.
        assertTrue(rows.all { it.width == 120 && it.height == 54 })
        rows.forEach { it.placeChildren() }
        assertEquals(List(6) { IntOffset(0, 4) }, positions) // Remaining .5px is translated by draw().
    }

    @Test fun fourIntrinsicsStayFiniteAndAgreeWithUnboundedMeasurement() {
        val modifier = FractionalVerticalPadding(1.5.dp)
        with(modifier) {
            val child = child()
            assertEquals(120, intrinsic.minIntrinsicWidth(child, Constraints.Infinity))
            assertEquals(120, intrinsic.maxIntrinsicWidth(child, Constraints.Infinity))
            assertEquals(54, intrinsic.minIntrinsicHeight(child, Constraints.Infinity))
            assertEquals(54, intrinsic.maxIntrinsicHeight(child, Constraints.Infinity))
            val actual = scope.measure(child, Constraints())
            assertEquals(120, actual.width)
            assertEquals(54, actual.height)
            val infinite = child(intrinsicValue = Constraints.Infinity)
            assertTrue(intrinsic.minIntrinsicWidth(infinite, Constraints.Infinity) < Constraints.Infinity)
            assertTrue(intrinsic.maxIntrinsicWidth(infinite, Constraints.Infinity) < Constraints.Infinity)
            assertTrue(intrinsic.minIntrinsicHeight(infinite, Constraints.Infinity) < Constraints.Infinity)
            assertTrue(intrinsic.maxIntrinsicHeight(infinite, Constraints.Infinity) < Constraints.Infinity)
        }
    }

    private fun child(intrinsicValue: Int? = null, onMeasure: (Constraints) -> Unit = {}, onPlace: (IntOffset) -> Unit = {}): Measurable = object : Measurable {
        override val parentData: Any? = null
        override fun minIntrinsicWidth(height: Int) = intrinsicValue ?: 120
        override fun maxIntrinsicWidth(height: Int) = intrinsicValue ?: 120
        override fun minIntrinsicHeight(width: Int) = intrinsicValue ?: 45
        override fun maxIntrinsicHeight(width: Int) = intrinsicValue ?: 45
        override fun measure(constraints: Constraints): Placeable {
            onMeasure(constraints)
            return object : Placeable() {
                init { measuredSize = IntSize(constraints.constrainWidth(120), constraints.constrainHeight(45)) }
                override fun get(alignmentLine: AlignmentLine) = AlignmentLine.Unspecified
                override fun placeAt(position: IntOffset, zIndex: Float, layerBlock: (GraphicsLayerScope.() -> Unit)?) {
                    assertNull("Padding must not allocate a layer per score row", layerBlock)
                    onPlace(position)
                }
            }
        }
    }
}
