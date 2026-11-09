package com.green.note.account

import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.layout.*
import androidx.compose.ui.unit.*
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.ceil

class AccountFieldMeasurePolicyTest {
    private fun scope(scale: Float = 1f, pixels: Float = 1f) = object : MeasureScope {
        override val density = pixels
        override val fontScale = scale
        override val layoutDirection = LayoutDirection.Ltr
    }
    private class Child(val naturalWidth: Int, val lineHeight: Int, val lines: Int = 1, val wrap: Boolean = false) : Measurable {
        override val parentData: Any? = null
        var measured: Constraints? = null
        var heightWidth: Int? = null
        var widthHeight: Int? = null
        override fun minIntrinsicWidth(height: Int): Int { widthHeight = height; return if (wrap) 20 else naturalWidth }
        override fun maxIntrinsicWidth(height: Int): Int { widthHeight = height; return naturalWidth }
        private fun height(width: Int): Int = lineHeight * maxOf(lines,
            if (!wrap || width == Constraints.Infinity) 1 else ceil(naturalWidth.toDouble() / width.coerceAtLeast(1)).toInt())
        override fun minIntrinsicHeight(width: Int): Int { heightWidth = width; return height(width) }
        override fun maxIntrinsicHeight(width: Int): Int { heightWidth = width; return height(width) }
        override fun measure(constraints: Constraints): Placeable {
            check(measured == null) { "A field slot must only be measured once" }
            measured = constraints
            val width = constraints.constrainWidth(naturalWidth)
            return object : Placeable() {
                init { measuredSize = IntSize(width, constraints.constrainHeight(height(width))) }
                override fun get(alignmentLine: AlignmentLine) = AlignmentLine.Unspecified
                override fun placeAt(position: IntOffset, zIndex: Float, layerBlock: (GraphicsLayerScope.() -> Unit)?) = Unit
            }
        }
    }
    private fun children(input: Child) = listOf(input, Child(24, 24), Child(24, 24))

    @Test fun dialogUsesAllFourRealIntrinsicMethodsWithoutCallingMeasure() {
        val input = Child(140, 24, wrap = true)
        val children = children(input)
        with(AccountFieldMeasurePolicy(true, true, true, 100, 16f)) {
            assertEquals(204, scope().minIntrinsicWidth(children, Constraints.Infinity))
            assertEquals(244, scope().maxIntrinsicWidth(children, Constraints.Infinity))
            assertEquals(Constraints.Infinity, input.widthHeight)
            assertEquals(56, scope().minIntrinsicHeight(children, Constraints.Infinity))
            assertEquals(56, scope().maxIntrinsicHeight(children, Constraints.Infinity))
            assertEquals(Constraints.Infinity, input.heightWidth)
            assertEquals(104, scope().maxIntrinsicHeight(children, 154))
            assertEquals(50, input.heightWidth)
        }
        assertTrue(children.all { it.measured == null })
    }

    @Test fun actualUnboundedWidthUsesInputAndLabelNaturalSizesAndParentMinimum() {
        with(AccountFieldMeasurePolicy(false, false, true, 160, 16f)) {
            val first = children(Child(80, 24))
            val measured = scope().measure(first, Constraints())
            assertEquals(192, measured.width)
            assertEquals(56, measured.height)
            assertEquals(Constraints.Infinity, first[0].measured!!.maxWidth)
            val withMinimum = scope().measure(children(Child(80, 24)), Constraints(minWidth = 250))
            assertEquals(250, withMinimum.width)
        }
        with(AccountFieldMeasurePolicy(true, true, true, 80, 16f)) {
            assertEquals(404, scope().measure(children(Child(300, 24)), Constraints()).width)
        }
    }

    @Test fun boundedMultilineInputRetainsFieldPaddingAndBothIconSlots() {
        val children = children(Child(140, 24, 3))
        with(AccountFieldMeasurePolicy(true, true, true, 60, 16f)) {
            val result = scope().measure(children, Constraints.fixedWidth(280))
            assertEquals(280, result.width)
            assertEquals(104, result.height)
            assertEquals(Constraints.fixedWidth(176), children[0].measured)
            assertEquals(Constraints.fixed(48, 48), children[1].measured)
            assertEquals(Constraints.fixed(48, 48), children[2].measured)
        }
    }

    @Test fun underlineFiveLinesAndLargeFontsUseScaledTextButUnscaledPadding() {
        with(AccountFieldMeasurePolicy(false, false, false, 120, 32f)) {
            val result = scope(2f).measure(children(Child(120, 48, 5)), Constraints.fixedWidth(280))
            assertEquals(288, result.height)
            assertEquals(288, scope(2f).maxIntrinsicHeight(children(Child(120, 48, 5)), 280))
        }
        with(AccountFieldMeasurePolicy(true, true, true, 360, 32f)) {
            val result = scope(2f, 3f).measure(children(Child(360, 144, 3)), Constraints.fixedWidth(840))
            assertEquals(528, result.height)
            assertEquals(672, scope(2f, 3f).maxIntrinsicWidth(children(Child(360, 144)), Constraints.Infinity))
        }
    }

    @Test fun zeroAndTightConstraintsNeverCreateNegativeOrInfiniteFixedSizes() {
        for (width in listOf(0, 1, 20, 80)) for (height in listOf(0, 1, 20, 80)) {
            with(AccountFieldMeasurePolicy(true, true, true, 120, 16f)) {
                val children = children(Child(200, 24, 3))
                val result = scope().measure(children, Constraints.fixed(width, height))
                assertEquals(width, result.width)
                assertEquals(height, result.height)
                assertTrue(children.all { it.measured!!.minWidth >= 0 && it.measured!!.maxWidth < Constraints.Infinity })
            }
        }
    }

    @Test fun finiteIntrinsicHeightConstraintSubtractsPaddingAndPreservesEmptyLabel() {
        val children = children(Child(50, 24))
        with(AccountFieldMeasurePolicy(false, false, true, 0, 16f)) {
            assertEquals(82, scope().maxIntrinsicWidth(children, 40))
            assertEquals(8, children[0].widthHeight)
            assertEquals(56, scope().minIntrinsicHeight(children, 0))
            assertEquals(0, children[0].heightWidth)
        }
    }
}
