package com.green.note.ui

import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.layout.*
import androidx.compose.ui.unit.*
import com.green.note.settings.WebDavFieldMeasurePolicy
import org.junit.Assert.*
import org.junit.Test

class SettingsIntrinsicMeasureTest {
    private val scope=object:MeasureScope {
        override val density=1f
        override val fontScale=1f
        override val layoutDirection=LayoutDirection.Ltr
    }
    private class Slot(val width:Int,val height:Int,val minWidth:Int=width,val minHeight:Int=height,val maxHeight:Int=height):Measurable {
        override val parentData:Any?=null
        var lastHeightQueryWidth:Int?=null
        var actualMeasures=0
        override fun minIntrinsicWidth(height:Int)=minWidth
        override fun maxIntrinsicWidth(height:Int)=width
        override fun minIntrinsicHeight(width:Int):Int {lastHeightQueryWidth=width;return minHeight}
        override fun maxIntrinsicHeight(width:Int):Int {lastHeightQueryWidth=width;return maxHeight}
        override fun measure(constraints:Constraints):Placeable {
            actualMeasures++
            return object:Placeable() {
                init { measuredSize=IntSize(constraints.constrainWidth(this@Slot.width),constraints.constrainHeight(this@Slot.height)) }
                override fun get(alignmentLine:AlignmentLine)=if(alignmentLine==FirstBaseline)(this@Slot.height*.75f).toInt()else AlignmentLine.Unspecified
                override fun placeAt(position:IntOffset,zIndex:Float,layerBlock:(GraphicsLayerScope.()->Unit)?)=Unit
            }
        }
    }

    @Test fun tileHasAllFourIntrinsicQueriesWithoutFakeActualMeasurement() {
        val slots=listOf(Slot(24,24),Slot(100,24,50),Slot(180,20,60),Slot(40,40))
        with(ReviewTileMeasurePolicy(true,true,true,4.dp,false)) {
            assertEquals(140,scope.minIntrinsicWidth(slots,Constraints.Infinity))
            assertEquals(260,scope.maxIntrinsicWidth(slots,Constraints.Infinity))
            assertEquals(64,scope.minIntrinsicHeight(slots,Constraints.Infinity))
            assertEquals(64,scope.maxIntrinsicHeight(slots,0))
        }
        assertTrue(slots.all{it.actualMeasures==0})
    }

    @Test fun tileActualInfiniteWidthUsesNaturalSlotsAndFiniteLayout() {
        val slots=listOf(Slot(24,24),Slot(100,24),Slot(180,20),Slot(40,40))
        with(ReviewTileMeasurePolicy(true,true,true,4.dp,false)) {
            val result=scope.measure(slots,Constraints())
            assertEquals(276,result.width)
            assertEquals(64,result.height)
            assertEquals(320,scope.measure(slots,Constraints(maxWidth=320)).width)
        }
    }

    @Test fun tileLargeTextAndThreeLineMinimumArePreserved() {
        val empty=Slot(0,0)
        with(ReviewTileMeasurePolicy(false,false,true,4.dp,true)) {
            assertEquals(160,scope.maxIntrinsicHeight(listOf(empty,Slot(100,72),Slot(100,80),empty),100))
            assertEquals(76,scope.minIntrinsicHeight(listOf(empty,Slot(100,20),Slot(100,20),empty),100))
        }
    }

    @Test fun outlinedFieldQueriesKeepInfinityAsAQueryAndNeverPackItAsFixedWidth() {
        val input=Slot(100,28,40,28,56)
        val slots=listOf(input,Slot(18,18))
        with(WebDavFieldMeasurePolicy) {
            assertEquals(108,scope.minIntrinsicWidth(slots,Constraints.Infinity))
            assertEquals(168,scope.maxIntrinsicWidth(slots,Constraints.Infinity))
            assertEquals(52,scope.minIntrinsicHeight(slots,Constraints.Infinity))
            assertEquals(Constraints.Infinity,input.lastHeightQueryWidth)
            assertEquals(80,scope.maxIntrinsicHeight(slots,100))
            assertEquals(32,input.lastHeightQueryWidth)
            scope.minIntrinsicHeight(slots,0)
            assertEquals(0,input.lastHeightQueryWidth)
        }
        assertTrue(slots.all{it.actualMeasures==0})
    }

    @Test fun outlinedFieldActualMeasureHandlesUnboundedNarrowAndParentMinimumSizes() {
        val slots=listOf(Slot(100,24),Slot(18,18))
        with(WebDavFieldMeasurePolicy) {
            assertEquals(168,scope.measure(slots,Constraints()).width)
            assertEquals(48,scope.measure(slots,Constraints()).height)
            assertEquals(0,scope.measure(slots,Constraints(maxWidth=0)).width)
            assertEquals(300,scope.measure(slots,Constraints(maxWidth=300)).width)
            assertEquals(80,scope.measure(slots,Constraints(minHeight=80,maxWidth=300)).height)
        }
    }
}
