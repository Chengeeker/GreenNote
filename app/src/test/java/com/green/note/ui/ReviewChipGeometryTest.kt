package com.green.note.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.layout.*
import androidx.compose.ui.node.LayoutModifierNode
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.unit.*
import org.junit.Assert.*
import org.junit.Test

class ReviewChipGeometryTest {
    @Test fun actualInkInsetMeasuresTransparentSelectedOutlinedAndExplicitNone() {
        val scope=object:MeasureScope {
            override val density=3f
            override val fontScale=1f
            override val layoutDirection=LayoutDirection.Ltr
        }
        for (side in listOf(BorderStroke(1.dp,Color.Gray),BorderStroke(1.dp,Color.Transparent),null)) {
            val inset=if(side==null)0 else 3
            var placed:IntOffset?=null
            val child=object:Measurable {
                override val parentData:Any?=null
                override fun minIntrinsicWidth(height:Int)=264
                override fun maxIntrinsicWidth(height:Int)=264
                override fun minIntrinsicHeight(width:Int)=108
                override fun maxIntrinsicHeight(width:Int)=108
                override fun measure(constraints:Constraints):Placeable=object:Placeable() {
                    init {measuredSize=IntSize(constraints.constrainWidth(264),constraints.constrainHeight(108))}
                    override fun get(alignmentLine:AlignmentLine)=AlignmentLine.Unspecified
                    override fun placeAt(position:IntOffset,zIndex:Float,layerBlock:(GraphicsLayerScope.()->Unit)?){placed=position}
                }
            }
            val node=Modifier.reviewChipBorderInset(side).foldIn<LayoutModifierNode?>(null){found,element->
                found?:((element as? ModifierNodeElement<*>)?.create() as? LayoutModifierNode)
            }!!
            with(node) {
                val result=scope.measure(child,Constraints())
                assertEquals(264+inset*2,result.width)
                assertEquals(108+inset*2,result.height)
                result.placeChildren()
                assertEquals(IntOffset(inset,inset),placed)
                assertEquals(result.width,scope.minIntrinsicWidth(child,Constraints.Infinity))
                assertEquals(result.width,scope.maxIntrinsicWidth(child,Constraints.Infinity))
                assertEquals(result.height,scope.minIntrinsicHeight(child,Constraints.Infinity))
                assertEquals(result.height,scope.maxIntrinsicHeight(child,Constraints.Infinity))
                val narrow=scope.measure(child,Constraints(maxWidth=4,maxHeight=4))
                assertEquals(4,narrow.width)
                assertEquals(4,narrow.height)
            }
        }
    }
    @Test fun horizontalScrollKeepsUnboundedLabelWidthRepresentable() {
        val infinity = androidx.compose.ui.unit.Constraints.Infinity
        val width = ReviewChipGeometry.availableWidth(infinity, 70)
        assertEquals(infinity, androidx.compose.ui.unit.Constraints(maxWidth = width, maxHeight = 48).maxWidth)
        assertEquals(50, ReviewChipGeometry.availableWidth(120, 70))
        assertEquals(0, ReviewChipGeometry.availableWidth(30, 70))
    }
    @Test fun originalPaintHeightIsContentDrivenAndHitTargetIsSeparate(){
        assertEquals(20f,ReviewChipGeometry.contentHeight(20f,16f,0f),0f)
        assertEquals(40f,ReviewChipGeometry.contentHeight(40f,16f,0f),0f)
        assertEquals(16f,ReviewChipGeometry.contentHeight(12f,16f,0f),0f)
        assertEquals(8f,ReviewChipGeometry.labelPadding(1f),0f)
        assertEquals(6f,ReviewChipGeometry.labelPadding(1.5f),0f)
        assertEquals(4f,ReviewChipGeometry.labelPadding(3f),0f)
    }
    @Test fun reverseCheckFadesBeforeDrawerFinishesClosing(){
        assertEquals(0f,ReviewChipGeometry.checkProgress(.7f,true),0f)
        assertTrue(ReviewChipGeometry.avatarProgress(.7f,true)>0)
        assertEquals(0f,ReviewChipGeometry.checkProgress(.2f,false),0f)
        assertEquals(1f,ReviewChipGeometry.checkProgress(1f,false),0f)
        assertEquals(1f,ReviewChipGeometry.avatarProgress(1f,false),0f)
    }
}
