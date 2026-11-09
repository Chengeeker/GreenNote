package com.green.note.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.*
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import androidx.compose.ui.unit.Constraints
import kotlin.math.max
import kotlin.math.roundToInt

internal data class ReviewTileGeometry(val height:Float,val titleY:Float,val subtitleY:Float)

/** Flutter's dense ListTile baseline and multi-line compatibility layout. */
internal fun reviewTileGeometry(titleHeight:Float,titleBaseline:Float,subtitleHeight:Float?,subtitleBaseline:Float,
    minimumPadding:Float,unit:Float=1f,isThreeLine:Boolean=false):ReviewTileGeometry {
    if(subtitleHeight==null){val height=max(48*unit,titleHeight+2*minimumPadding);return ReviewTileGeometry(height,(height-titleHeight)/2,0f)}
    val target=(if(isThreeLine)76 else 64)*unit
    val title=(if(isThreeLine)22 else 28)*unit-titleBaseline;val subtitle=(if(isThreeLine)42 else 48)*unit-subtitleBaseline
    val overlap=max(title+titleHeight-subtitle,0f)/2
    val titleY=title-overlap;val subtitleY=subtitle+overlap
    return if(titleY<minimumPadding||subtitleY+subtitleHeight+minimumPadding>target)
        ReviewTileGeometry(2*minimumPadding+titleHeight+subtitleHeight,minimumPadding,minimumPadding+titleHeight)
    else ReviewTileGeometry(target,titleY,subtitleY)
}

@Composable
internal fun ReviewTileLayout(modifier:Modifier=Modifier,horizontalPadding:Dp=16.dp,verticalPadding:Dp=0.dp,minVerticalPadding:Dp=4.dp,isThreeLine:Boolean=false,
    leading:(@Composable ()->Unit)?=null,trailing:(@Composable ()->Unit)?=null,subtitle:(@Composable ()->Unit)?=null,title:@Composable ()->Unit) {
    Layout(content={Box{leading?.invoke()};Box{title()};Box{subtitle?.invoke()};Box{trailing?.invoke()}},
        modifier=modifier.fillMaxWidth().padding(horizontal=horizontalPadding,vertical=verticalPadding),
        measurePolicy=remember(leading!=null,trailing!=null,subtitle!=null,minVerticalPadding,isThreeLine) {
            ReviewTileMeasurePolicy(leading!=null,trailing!=null,subtitle!=null,minVerticalPadding,isThreeLine)
        })
}

internal class ReviewTileMeasurePolicy(private val hasLeading:Boolean,private val hasTrailing:Boolean,
    private val hasSubtitle:Boolean,private val minVerticalPadding:Dp,private val isThreeLine:Boolean):MeasurePolicy {
    override fun MeasureScope.measure(items:List<Measurable>,constraints:Constraints):MeasureResult {
        val loose=constraints.copy(minWidth=0,minHeight=0)
        val icon=items[0].measure(loose);val end=items[3].measure(loose)
        val titleStart=if(!hasLeading)0 else max(24.dp.roundToPx(),icon.width)+16.dp.roundToPx()
        val titleEnd=if(!hasTrailing)0 else max(end.width+16.dp.roundToPx(),32.dp.roundToPx())
        val textConstraints=if(constraints.hasBoundedWidth) {
            val textWidth=(constraints.maxWidth-titleStart-titleEnd).coerceAtLeast(0)
            loose.copy(minWidth=textWidth,maxWidth=textWidth)
        } else loose
        val heading=items[1].measure(textConstraints);val detail=items[2].measure(textConstraints)
        val width=if(constraints.hasBoundedWidth)constraints.maxWidth else constraints.constrainWidth(titleStart+max(heading.width,detail.width)+titleEnd)
        val geometry=reviewTileGeometry(heading.height.toFloat(),heading[FirstBaseline].takeIf{it!=androidx.compose.ui.layout.AlignmentLine.Unspecified}?.toFloat()?:heading.height.toFloat(),
            if(!hasSubtitle)null else detail.height.toFloat(),detail[FirstBaseline].takeIf{it!=androidx.compose.ui.layout.AlignmentLine.Unspecified}?.toFloat()?:detail.height.toFloat(),minVerticalPadding.toPx(),density,isThreeLine)
        val height=constraints.constrainHeight(geometry.height.roundToInt())
        return layout(width,height){
            if(hasLeading)icon.placeRelative(0,if(isThreeLine)minVerticalPadding.roundToPx() else (height-icon.height)/2)
            heading.placeRelative(titleStart,geometry.titleY.roundToInt())
            if(hasSubtitle)detail.placeRelative(titleStart,geometry.subtitleY.roundToInt())
            if(hasTrailing)end.placeRelative(width-end.width,if(isThreeLine)minVerticalPadding.roundToPx() else (height-end.height)/2)
        }
    }

    // Flutter _RenderListTile intrinsic sizing; queries must never call actual measure with Infinity.
    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables:List<IntrinsicMeasurable>,height:Int):Int {
        val start=if(hasLeading)max(24.dp.roundToPx(),measurables[0].minIntrinsicWidth(height))+16.dp.roundToPx() else 0
        return start+max(measurables[1].minIntrinsicWidth(height),if(hasSubtitle)measurables[2].minIntrinsicWidth(height)else 0)+
            if(hasTrailing)measurables[3].maxIntrinsicWidth(height)else 0
    }
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables:List<IntrinsicMeasurable>,height:Int):Int {
        val start=if(hasLeading)max(24.dp.roundToPx(),measurables[0].maxIntrinsicWidth(height))+16.dp.roundToPx() else 0
        return start+max(measurables[1].maxIntrinsicWidth(height),if(hasSubtitle)measurables[2].maxIntrinsicWidth(height)else 0)+
            if(hasTrailing)measurables[3].maxIntrinsicWidth(height)else 0
    }
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables:List<IntrinsicMeasurable>,width:Int):Int =
        max((if(isThreeLine)76.dp else if(hasSubtitle)64.dp else 48.dp).roundToPx(),
            measurables[1].minIntrinsicHeight(width)+(if(hasSubtitle)measurables[2].minIntrinsicHeight(width)else 0)+2*minVerticalPadding.roundToPx())
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables:List<IntrinsicMeasurable>,width:Int)=minIntrinsicHeight(measurables,width)
}
