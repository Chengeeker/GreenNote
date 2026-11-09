package com.green.note.settings

import androidx.compose.ui.layout.*
import androidx.compose.ui.unit.*
import kotlin.math.max

/** Dense outlined field's existing geometry, with explicit intrinsic sizing for dialog parents. */
internal object WebDavFieldMeasurePolicy:MeasurePolicy {
    override fun MeasureScope.measure(measurables:List<Measurable>,constraints:Constraints):MeasureResult {
        val horizontal=68.dp.roundToPx()
        val input=measurables[0].measure(if(constraints.hasBoundedWidth)
            Constraints.fixedWidth((constraints.maxWidth-horizontal).coerceAtLeast(0)) else Constraints())
        val leading=measurables[1].measure(Constraints.fixed(18.dp.roundToPx(),18.dp.roundToPx()))
        val width=if(constraints.hasBoundedWidth)constraints.maxWidth else constraints.constrainWidth(input.width+horizontal)
        val height=constraints.constrainHeight(max(48.dp.roundToPx(),input.height+24.dp.roundToPx()))
        return layout(width,height){input.placeRelative(52.dp.roundToPx(),(height-input.height)/2);leading.placeRelative(15.dp.roundToPx(),(height-leading.height)/2)}
    }
    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables:List<IntrinsicMeasurable>,height:Int)=
        measurables[0].minIntrinsicWidth(height)+68.dp.roundToPx()
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables:List<IntrinsicMeasurable>,height:Int)=
        measurables[0].maxIntrinsicWidth(height)+68.dp.roundToPx()
    private fun IntrinsicMeasureScope.inputWidth(width:Int)=if(width==Constraints.Infinity)width else (width-68.dp.roundToPx()).coerceAtLeast(0)
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables:List<IntrinsicMeasurable>,width:Int)=
        max(48.dp.roundToPx(),measurables[0].minIntrinsicHeight(inputWidth(width))+24.dp.roundToPx())
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables:List<IntrinsicMeasurable>,width:Int)=
        max(48.dp.roundToPx(),measurables[0].maxIntrinsicHeight(inputWidth(width))+24.dp.roundToPx())
}
