package com.green.note.ui

import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.graphics.GraphicsLayerScope
import org.junit.Assert.*
import org.junit.Test

class ReviewDialogGeometryTest {
    private val intrinsicScope=object:IntrinsicMeasureScope {
        override val density=1f
        override val fontScale=1f
        override val layoutDirection=LayoutDirection.Ltr
    }
    private fun action(minWidth:Int,maxWidth:Int,minHeight:Int,maxHeight:Int)=object:IntrinsicMeasurable {
        override val parentData:Any?=null
        override fun minIntrinsicWidth(height:Int):Int {assertEquals(Constraints.Infinity,height);return minWidth}
        override fun maxIntrinsicWidth(height:Int):Int {assertEquals(Constraints.Infinity,height);return maxWidth}
        override fun minIntrinsicHeight(width:Int)=minHeight
        override fun maxIntrinsicHeight(width:Int)=maxHeight
    }
    @Test fun flutterPaddingShrinksOnlyBetweenOneAndTwoTimesTextScale() {
        assertEquals(1f,reviewDialogPaddingScale(.8f),.00001f)
        assertEquals(1f,reviewDialogPaddingScale(1f),.00001f)
        assertEquals(20f,24*reviewDialogPaddingScale(1.25f),.00001f)
        assertEquals(8f,24*reviewDialogPaddingScale(2f),.00001f)
        assertEquals(8f,24*reviewDialogPaddingScale(3f),.00001f)
    }
    @Test fun overflowKeepsCancelBeforeConfirmWithNoVerticalGap() {
        val actions=listOf(IntSize(92,48),IntSize(124,56))
        assertEquals(listOf(IntOffset(36,4),IntOffset(136,0)),reviewDialogActionPositions(actions,260,8))
        assertEquals(listOf(IntOffset(108,0),IntOffset(76,48)),reviewDialogActionPositions(actions,200,8))
        assertEquals(listOf(IntOffset(0,4),IntOffset(100,0)),reviewDialogActionPositions(actions,224,8))
    }

    @Test fun allFourIntrinsicQueriesAreFiniteWithoutEnteringActualMeasure() {
        val children=listOf(action(64,92,48,60),action(80,124,56,72))
        with(ReviewDialogActionsMeasurePolicy(8)) {
            assertEquals(152,intrinsicScope.minIntrinsicWidth(children,Constraints.Infinity))
            assertEquals(224,intrinsicScope.maxIntrinsicWidth(children,Constraints.Infinity))
            assertEquals(56,intrinsicScope.minIntrinsicHeight(children,Constraints.Infinity))
            assertEquals(72,intrinsicScope.maxIntrinsicHeight(children,Constraints.Infinity))
            assertEquals(104,intrinsicScope.minIntrinsicHeight(children,150))
            assertEquals(132,intrinsicScope.maxIntrinsicHeight(children,150))
        }
    }

    @Test fun threeLargeFontActionsFitExactlyOrOverflowWithNoVerticalSpacing() {
        val children=listOf(action(120,180,72,96),action(140,200,80,112),action(160,240,88,128))
        with(ReviewDialogActionsMeasurePolicy(8)) {
            assertEquals(436,intrinsicScope.minIntrinsicWidth(children,1))
            assertEquals(636,intrinsicScope.maxIntrinsicWidth(children,1))
            assertEquals(88,intrinsicScope.minIntrinsicHeight(children,436))
            assertEquals(240,intrinsicScope.minIntrinsicHeight(children,435))
            assertEquals(336,intrinsicScope.maxIntrinsicHeight(children,435))
        }
        assertEquals(listOf(IntOffset(120,0),IntOffset(100,72),IntOffset(80,152)),
            reviewDialogActionPositions(listOf(IntSize(120,72),IntSize(140,80),IntSize(160,88)),240,8))
    }

    @Test fun actualUnboundedWidthUsesFiniteNaturalSizeAndHonorsMinimum() {
        val sizes=listOf(IntSize(92,48),IntSize(124,56),IntSize(64,48))
        assertEquals(296,reviewDialogActionWidth(sizes,Constraints(),8))
        assertEquals(340,reviewDialogActionWidth(sizes,Constraints(minWidth=340),8))
        assertEquals(200,reviewDialogActionWidth(sizes,Constraints(maxWidth=200),8))
        assertEquals(0,reviewDialogActionWidth(emptyList(),Constraints(),8))
        assertTrue(reviewDialogNaturalWidth(listOf(Int.MAX_VALUE,Int.MAX_VALUE),8)<Constraints.Infinity)
    }

    @Test fun actualMeasureWithInfiniteWidthNeverPassesInfinityToComposeLayout() {
        val scope=object:MeasureScope {
            override val density=1f
            override val fontScale=1f
            override val layoutDirection=LayoutDirection.Ltr
        }
        fun measurable(width:Int,height:Int)=object:Measurable {
            override val parentData:Any?=null
            override fun minIntrinsicWidth(height:Int)=width
            override fun maxIntrinsicWidth(height:Int)=width
            override fun minIntrinsicHeight(width:Int)=height
            override fun maxIntrinsicHeight(width:Int)=height
            override fun measure(constraints:Constraints)=object:Placeable() {
                init { measuredSize=IntSize(width,height) }
                override fun get(alignmentLine:AlignmentLine)=AlignmentLine.Unspecified
                override fun placeAt(position:IntOffset,zIndex:Float,layerBlock:(GraphicsLayerScope.()->Unit)?)=Unit
            }
        }
        with(ReviewDialogActionsMeasurePolicy(8)) {
            val result=scope.measure(listOf(measurable(92,48),measurable(124,144)),Constraints())
            assertEquals(224,result.width)
            assertEquals(144,result.height)
        }
    }

    @Test fun zeroChildrenAndZeroWidthHeightQueriesNeverProduceInfinity() {
        with(ReviewDialogActionsMeasurePolicy(8)) {
            assertEquals(0,intrinsicScope.minIntrinsicWidth(emptyList(),Constraints.Infinity))
            assertEquals(0,intrinsicScope.maxIntrinsicWidth(emptyList(),Constraints.Infinity))
            assertEquals(0,intrinsicScope.minIntrinsicHeight(emptyList(),0))
            assertEquals(0,intrinsicScope.maxIntrinsicHeight(emptyList(),Constraints.Infinity))
            assertEquals(144,intrinsicScope.maxIntrinsicHeight(listOf(action(64,92,48,72),action(64,92,48,72)),0))
        }
    }
}
