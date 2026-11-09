package com.green.note.content

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
import kotlin.math.floor
import kotlin.math.roundToInt
import org.junit.Assert.*
import org.junit.Test

class TopicDimensionPaddingTest {
    private fun scope(scale: Float) = object : MeasureScope {
        override val density = scale
        override val fontScale = 1f
        override val layoutDirection = LayoutDirection.Ltr
    }

    @Test fun actualRowsCarryFractionalColumnBoundariesAtDifferentDensities() {
        for (density in listOf(1f, 1.25f, 1.5f, 2.625f, 3f, 3.5f, 4f)) {
            val scope = scope(density)
            // The mixed Latin/CJK AI label is taller than the other three labels.
            val childHeights = listOf(45, 48, 45, 45)
            var physicalTop = 0
            var flutterTop = 0.0
            val actualHeights = mutableListOf<Int>()
            for (index in childHeights.indices) {
                val modifier = TopicDimensionPadding(2.2.dp, index)
                var placement: IntOffset? = null
                val result = with(modifier) {
                    scope.measure(child(childHeights[index]) { placement = it }, Constraints(maxWidth = 220))
                }
                result.placeChildren()
                val top = modifier.contentTop(density)
                val drawRemainder = top - floor(top)
                val actualContentTop = physicalTop + placement!!.y + drawRemainder
                assertEquals("Content origin must follow the unrounded Flutter column at density=$density row=$index",
                    (flutterTop + 2.2 * density).toFloat(), actualContentTop, .0001f)
                assertEquals(120, result.width)
                physicalTop += result.height
                actualHeights += result.height
                flutterTop += childHeights[index] + 4.4 * density
            }
            assertEquals("Only the complete column's subpixel remainder is rounded", flutterTop.roundToInt(), physicalTop)
            if (density == 3f) {
                assertEquals(listOf(58, 61, 59, 58), actualHeights)
                assertEquals(236, physicalTop) // 183px text + 52.8px padding rounds once.
            }
        }
    }

    @Test fun allIntrinsicQueriesAgreeWithUnboundedMeasurementAndStayFinite() {
        val scope = scope(3f)
        val intrinsic: IntrinsicMeasureScope = scope
        for (index in 0..3) {
            with(TopicDimensionPadding(2.2.dp, index)) {
                val item = child(45)
                val actual = scope.measure(item, Constraints())
                assertEquals(actual.width, intrinsic.minIntrinsicWidth(item, Constraints.Infinity))
                assertEquals(actual.width, intrinsic.maxIntrinsicWidth(item, Constraints.Infinity))
                assertEquals(actual.height, intrinsic.minIntrinsicHeight(item, Constraints.Infinity))
                assertEquals(actual.height, intrinsic.maxIntrinsicHeight(item, Constraints.Infinity))
                val infinite = child(45, intrinsicValue = Constraints.Infinity)
                assertTrue(intrinsic.minIntrinsicWidth(infinite, Constraints.Infinity) < Constraints.Infinity)
                assertTrue(intrinsic.maxIntrinsicWidth(infinite, Constraints.Infinity) < Constraints.Infinity)
                assertTrue(intrinsic.minIntrinsicHeight(infinite, Constraints.Infinity) < Constraints.Infinity)
                assertTrue(intrinsic.maxIntrinsicHeight(infinite, Constraints.Infinity) < Constraints.Infinity)
            }
        }
    }

    private fun child(height: Int, intrinsicValue: Int? = null, onPlace: (IntOffset) -> Unit = {}): Measurable = object : Measurable {
        override val parentData: Any? = null
        override fun minIntrinsicWidth(height: Int) = intrinsicValue ?: 120
        override fun maxIntrinsicWidth(height: Int) = intrinsicValue ?: 120
        override fun minIntrinsicHeight(width: Int) = intrinsicValue ?: height
        override fun maxIntrinsicHeight(width: Int) = intrinsicValue ?: height
        override fun measure(constraints: Constraints): Placeable = object : Placeable() {
            init { measuredSize = IntSize(constraints.constrainWidth(120), constraints.constrainHeight(height)) }
            override fun get(alignmentLine: AlignmentLine) = AlignmentLine.Unspecified
            override fun placeAt(position: IntOffset, zIndex: Float, layerBlock: (GraphicsLayerScope.() -> Unit)?) {
                assertNull("Four static rating rows must not allocate separate graphics layers", layerBlock)
                onPlace(position)
            }
        }
    }
}
