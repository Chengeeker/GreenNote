package com.green.note.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.interaction.*
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.roundToInt

internal object ReviewCheckboxGeometry {
    fun inset(t:Float)=1f-abs(t-.5f)*2
    fun edge(t:Float)=18f-inset(t)*2
    fun check(t:Float)=((t-.5f)*2).coerceIn(0f,1f)
}

/** Original M3 Checkbox: 18dp box, 2dp radius/stroke; no ordinary touch overlay. */
@Composable
fun ReviewCheckbox(checked:Boolean,onCheckedChange:((Boolean)->Unit)?,modifier:Modifier=Modifier,enabled:Boolean=true,
    shrinkWrap:Boolean=false,isError:Boolean=false) {
    val scheme=MaterialTheme.colorScheme
    val source=remember{MutableInteractionSource()}
    val pressed by source.collectIsPressedAsState()
    val focused by source.collectIsFocusedAsState()
    val hovered by source.collectIsHoveredAsState()
    val position=remember{Animatable(if(checked)1f else 0f)}
    LaunchedEffect(checked){val target=if(checked)1f else 0f;position.animateTo(target,tween((200*abs(target-position.value)).roundToInt(),easing=LinearEasing))}
    val view=LocalView.current
    val haptics=LocalAppPreferences.current.haptics
    val input=if(onCheckedChange==null)Modifier else Modifier.toggleable(checked,enabled=enabled,role=Role.Checkbox,
        interactionSource=source,indication=null,onValueChange={AppHaptics.light(view,haptics);onCheckedChange(it)})
    Canvas(modifier.then(input).size(if(shrinkWrap)40.dp else 48.dp)) {
        val t=if(checked)CubicBezierEasing(.42f,0f,1f,1f).transform(position.value)
            else CubicBezierEasing(0f,0f,.58f,1f).transform(position.value)
        val edge=ReviewCheckboxGeometry.edge(t).dp.toPx()
        val origin=Offset(size.width/2-9.dp.toPx(),size.height/2-9.dp.toPx())
        val inset=ReviewCheckboxGeometry.inset(t).dp.toPx()
        val outer=origin+Offset(inset,inset)
        val active=if(!enabled)scheme.onSurface.copy(alpha=.38f)else if(isError)scheme.error else scheme.primary
        val inactiveSide=if(!enabled)scheme.onSurface.copy(alpha=.38f)else if(isError)scheme.error else if(pressed||focused||hovered)scheme.onSurface else scheme.onSurfaceVariant
        val fill=active.copy(alpha=active.alpha*(t*4).coerceAtMost(1f))
        drawRoundRect(fill,outer,Size(edge,edge),CornerRadius(2.dp.toPx()))
        if(t<=.5f){
            val strokeWidth=(if(enabled)2*(1-t)else 2f).dp.toPx()
            val border=inactiveSide.copy(alpha=inactiveSide.alpha*(1-t))
            drawRoundRect(border,outer+Offset(strokeWidth/2,strokeWidth/2),Size(edge-strokeWidth,edge-strokeWidth),CornerRadius((2.dp.toPx()-strokeWidth/2).coerceAtLeast(0f)),style=Stroke(strokeWidth))
        }
        val fraction=ReviewCheckboxGeometry.check(t)
        if(fraction>0){
            val start=origin+Offset(18.dp.toPx()*.15f,18.dp.toPx()*.45f)
            val mid=origin+Offset(18.dp.toPx()*.4f,18.dp.toPx()*.7f)
            val end=origin+Offset(18.dp.toPx()*.85f,18.dp.toPx()*.25f)
            val path=Path().apply{moveTo(start.x,start.y);if(fraction<.5f){val p=lerp(start,mid,fraction*2);lineTo(p.x,p.y)}else{lineTo(mid.x,mid.y);val p=lerp(mid,end,(fraction-.5f)*2);lineTo(p.x,p.y)}}
            drawPath(path,if(!enabled)scheme.surface else if(isError)scheme.onError else scheme.onPrimary,style=Stroke(2.dp.toPx()))
        }
    }
}
