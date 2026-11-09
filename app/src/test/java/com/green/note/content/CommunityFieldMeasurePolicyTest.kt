package com.green.note.content

import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.LayoutIdParentData
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import org.junit.Assert.*
import org.junit.Test

class CommunityFieldMeasurePolicyTest {
    private val intrinsic = object : IntrinsicMeasureScope {
        override val density = 1f
        override val fontScale = 1f
        override val layoutDirection = LayoutDirection.Ltr
    }
    private val measureScope = object : MeasureScope {
        override val density = 1f
        override val fontScale = 1f
        override val layoutDirection = LayoutDirection.Ltr
    }
    private var measures = 0
    private fun child(id: String, naturalWidth: Int, lineHeight: Int, wraps: Boolean = false): Measurable = object : Measurable {
        override val parentData = object : LayoutIdParentData { override val layoutId: Any = id }
        override fun minIntrinsicWidth(height: Int) = naturalWidth
        override fun maxIntrinsicWidth(height: Int) = naturalWidth
        private fun height(width: Int) = if (!wraps || width == Constraints.Infinity) lineHeight else
            ((naturalWidth + width.coerceAtLeast(1) - 1) / width.coerceAtLeast(1)).coerceAtLeast(1) * lineHeight
        override fun minIntrinsicHeight(width: Int) = height(width)
        override fun maxIntrinsicHeight(width: Int) = height(width)
        override fun measure(constraints: Constraints): Placeable {
            measures++
            assertTrue("No fixed infinite width reaches a child", constraints.minWidth != Constraints.Infinity)
            val width = constraints.constrainWidth(naturalWidth)
            val measuredHeight = constraints.constrainHeight(height(width))
            return object : Placeable() {
                init { measuredSize = IntSize(width, measuredHeight) }
                override fun get(alignmentLine: AlignmentLine) = AlignmentLine.Unspecified
                override fun placeAt(position: IntOffset, zIndex: Float, layerBlock: (GraphicsLayerScope.() -> Unit)?) = Unit
            }
        }
    }
    private fun fields() = listOf(child("input", 180, 24, true), child("label", 60, 16), child("prefix", 48, 48), child("suffix", 48, 48))
    private fun policy(floating: Float = 1f, labelHeight: Int = 16) = CommunityFieldMeasurePolicy(floating, labelHeight, 8, 48, 4)

    @Test fun allFourIntrinsicQueriesBypassMeasureAndRemainFinite() {
        val children = fields()
        with(policy()) {
            assertEquals(280, intrinsic.minIntrinsicWidth(children, Constraints.Infinity))
            assertEquals(280, intrinsic.maxIntrinsicWidth(children, Constraints.Infinity))
            assertEquals(56, intrinsic.minIntrinsicHeight(children, Constraints.Infinity))
            assertEquals(56, intrinsic.maxIntrinsicHeight(children, Constraints.Infinity))
            assertEquals(152, intrinsic.minIntrinsicHeight(children, 140))
            assertEquals(152, intrinsic.maxIntrinsicHeight(children, 140))
        }
        assertEquals(0, measures)
    }

    @Test fun actualUnboundedMeasureResolvesNaturalWidthInsteadOfFixingInfinity() {
        with(policy()) {
            val result = measureScope.measure(fields(), Constraints())
            assertEquals(280, result.width)
            assertEquals(56, result.height)
        }
        assertEquals(4, measures)
    }

    @Test fun actualNarrowMeasureReservesBothIconsAndWrapsInput() {
        with(policy()) {
            val result = measureScope.measure(fields(), Constraints(maxWidth = 240))
            assertEquals(240, result.width)
            assertEquals(80, result.height)
        }
        assertEquals(4, measures)
    }

    @Test fun zeroWidthAndTallHintStillReportFiniteHeight() {
        val children = listOf(child("input", 180, 24, true), child("hint", 180, 48, true))
        with(policy(labelHeight = 0)) {
            val intrinsicHeight = intrinsic.maxIntrinsicHeight(children, 0)
            assertTrue(intrinsicHeight in 48 until Constraints.Infinity)
            val result = measureScope.measure(children, Constraints(maxWidth = 0))
            assertEquals(0, result.width)
            assertEquals(intrinsicHeight, result.height)
        }
    }

    @Test fun notificationBadgeIntrinsicQueriesUseAnchorOnlyWithoutMeasure() {
        val children = listOf(child("anchor", 52, 52), child("badge", 80, 20))
        with(NotificationBadgeMeasurePolicy) {
            assertEquals(52, intrinsic.minIntrinsicWidth(children, Constraints.Infinity))
            assertEquals(52, intrinsic.maxIntrinsicWidth(children, Constraints.Infinity))
            assertEquals(52, intrinsic.minIntrinsicHeight(children, Constraints.Infinity))
            assertEquals(52, intrinsic.maxIntrinsicHeight(children, Constraints.Infinity))
        }
        assertEquals(0, measures)
    }

    @Test fun notificationBadgeActualMeasureKeepsFiniteAnchorBounds() {
        with(NotificationBadgeMeasurePolicy) {
            val result = measureScope.measure(listOf(child("anchor", 52, 52), child("badge", 20, 16)), Constraints())
            assertEquals(52, result.width)
            assertEquals(52, result.height)
        }
        assertEquals(2, measures)
    }
}
