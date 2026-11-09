package com.green.note.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.*
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.*
import kotlin.math.*

@Composable
fun ReviewRadioButton(selected:Boolean,onClick:(()->Unit)?,modifier:Modifier=Modifier,enabled:Boolean=true,shrinkWrap:Boolean=false) {
    val scheme=MaterialTheme.colorScheme
    val source=remember{MutableInteractionSource()}
    val pressed by source.collectIsPressedAsState();val focused by source.collectIsFocusedAsState();val hovered by source.collectIsHoveredAsState()
    val position=remember{Animatable(if(selected)1f else 0f)}
    LaunchedEffect(selected){val target=if(selected)1f else 0f;position.animateTo(target,tween((200*abs(target-position.value)).roundToInt(),easing=LinearEasing))}
    val click=rememberHapticClick{onClick?.invoke()}
    val input=if(onClick==null)Modifier else Modifier.selectable(selected=selected,enabled=enabled,role=Role.RadioButton,interactionSource=source,indication=null,onClick=click)
    Canvas(modifier.then(input).size(if(shrinkWrap)40.dp else 48.dp)){
        val t=(if(selected)CubicBezierEasing(.42f,0f,1f,1f)else CubicBezierEasing(0f,0f,.58f,1f)).transform(position.value)
        val inactive=if(!enabled)scheme.onSurface.copy(alpha=.38f)else if(pressed||focused||hovered)scheme.onSurface else scheme.onSurfaceVariant
        val active=if(enabled)scheme.primary else scheme.onSurface.copy(alpha=.38f)
        val color=lerp(inactive,active,t)
        drawCircle(color,7.dp.toPx(),style=Stroke(2.dp.toPx()))
        if(t>0)drawCircle(color,4.5.dp.toPx()*t)
    }
}

internal object ReviewSwitchMotion {
    private val back=CubicBezierEasing(.175f,.885f,.32f,1.275f)
    private val first=CubicBezierEasing(.31f,0f,.56f,1f)
    private val second=CubicBezierEasing(.20f,0f,0f,1f)
    fun position(t:Float,forward:Boolean)=if(forward)back.transform(t)else 1-back.transform(1-t)
    fun color(t:Float,forward:Boolean)=(if(forward)CubicBezierEasing(0f,0f,.58f,1f)else CubicBezierEasing(.42f,0f,1f,1f)).transform(t)
    fun thumb(t:Float,forward:Boolean,inactive:Float=16f,active:Float=24f):Size {
        fun mix(a:Size,b:Size,f:Float)=Size(a.width+(b.width-a.width)*f,a.height+(b.height-a.height)*f)
        val small=Size(inactive,inactive);val large=Size(active,active);val middle=Size(34f,22f)
        return if(forward)when{t<.11f->mix(small,middle,first.transform(t/.11f));t<.83f->mix(middle,large,second.transform((t-.11f)/.72f));else->large}
        else when{t<.17f->small;t<.89f->mix(small,middle,1-second.transform(1-(t-.17f)/.72f));else->mix(middle,large,1-first.transform(1-(t-.89f)/.11f))}
    }
}

/** M3 Flutter switch has 4dp horizontal padding and a 300ms overshooting thumb sequence. */
@Composable
fun ReviewSwitch(checked:Boolean,onCheckedChange:((Boolean)->Unit)?,modifier:Modifier=Modifier,enabled:Boolean=true,shrinkWrap:Boolean=false) {
    val scheme=MaterialTheme.colorScheme;val density=LocalDensity.current;val rtl=LocalLayoutDirection.current==LayoutDirection.Rtl
    val source=remember{MutableInteractionSource()}
    val pressed by source.collectIsPressedAsState();val focused by source.collectIsFocusedAsState();val hovered by source.collectIsHoveredAsState()
    var dragging by remember{mutableStateOf(false)};var dragValue by remember{mutableFloatStateOf(if(checked)1f else 0f)}
    val position=remember{Animatable(if(checked)1f else 0f)}
    LaunchedEffect(checked,dragging){if(!dragging){val target=if(checked)1f else 0f;position.animateTo(target,tween((300*abs(target-position.value)).roundToInt(),easing=LinearEasing))}}
    val reaction by animateFloatAsState(if(pressed||dragging)1f else 0f,tween(100,easing=FastOutSlowInEasing),label="switch press")
    val view=LocalView.current;val haptics=LocalAppPreferences.current.haptics
    val callback by rememberUpdatedState(onCheckedChange)
    val latestChecked by rememberUpdatedState(checked)
    var dragStartChecked by remember { mutableStateOf(checked) }
    val latestHaptics by rememberUpdatedState(haptics)
    LaunchedEffect(source) {
        source.interactions.collect { interaction ->
            // Draggable also calls onDragStopped on cancellation; only Stop confirms a release.
            if (interaction is DragInteraction.Stop && (dragValue >= .5f) != dragStartChecked)
                AppHaptics.light(view, latestHaptics)
        }
    }
    val input=if(onCheckedChange==null)Modifier else Modifier.toggleable(value=checked,enabled=enabled,role=Role.Switch,interactionSource=source,indication=null,onValueChange={AppHaptics.light(view,haptics);callback?.invoke(it)})
        .draggable(rememberDraggableState{delta->dragValue=(dragValue+delta/(20*density.density)*(if(rtl)-1 else 1)).coerceIn(0f,1f)},Orientation.Horizontal,enabled=enabled,interactionSource=source,
            onDragStarted={dragStartChecked=latestChecked;dragValue=position.value;dragging=true},onDragStopped={
                position.snapTo(dragValue);dragging=false
                if((dragValue>=.5f)!=latestChecked)callback?.invoke(dragValue>=.5f)
            })
    Canvas(modifier.then(input).size(60.dp,if(shrinkWrap)40.dp else 48.dp)) {
        val raw=if(dragging)dragValue else position.value
        val p=if(dragging)raw else ReviewSwitchMotion.position(raw,checked)
        val color=ReviewSwitchMotion.color(raw,checked)
        val activeThumb=if(!enabled)scheme.surface else if(pressed||dragging||hovered||focused)scheme.primaryContainer else scheme.onPrimary
        val inactiveThumb=if(!enabled)scheme.onSurface.copy(alpha=.38f)else if(pressed||dragging||hovered||focused)scheme.onSurfaceVariant else scheme.outline
        val activeTrack=if(enabled)scheme.primary else scheme.onSurface.copy(alpha=.12f)
        val inactiveTrack=if(enabled)scheme.surfaceContainerHighest else scheme.surfaceContainerHighest.copy(alpha=.12f)
        val trackColor=lerp(inactiveTrack,activeTrack,color)
        val borderColor=(if(enabled)scheme.outline else scheme.onSurface.copy(alpha=.12f)).let{it.copy(alpha=it.alpha*(1-color))}
        val inactiveSize=16f+(if(!checked)12f*reaction else 0f)
        val activeSize=24f+(if(checked)4f*reaction else 0f)
        val thumb=if(reaction>=1f)Size(28f,28f)else ReviewSwitchMotion.thumb(raw,checked,inactiveSize,activeSize)
        val left=(size.width-52.dp.toPx())/2;val top=(size.height-32.dp.toPx())/2
        drawRoundRect(trackColor,Offset(left,top),Size(52.dp.toPx(),32.dp.toPx()),CornerRadius(16.dp.toPx()))
        drawRoundRect(borderColor,Offset(left+1.dp.toPx(),top+1.dp.toPx()),Size(50.dp.toPx(),30.dp.toPx()),CornerRadius(15.dp.toPx()),style=Stroke(2.dp.toPx()))
        val cx=left+16.dp.toPx()+(if(rtl)1-p else p)*20.dp.toPx()
        val pressedInactive=if(enabled)scheme.onSurfaceVariant else scheme.onSurface.copy(alpha=.38f)
        val pressedActive=if(enabled)scheme.primaryContainer else scheme.surface
        val thumbColor=(when {
            reaction>0f ->lerp(pressedInactive,pressedActive,color)
            position.isRunning&&checked ->lerp(pressedInactive,activeThumb,color)
            position.isRunning&&!checked ->lerp(inactiveThumb,pressedActive,color)
            else ->lerp(inactiveThumb,activeThumb,color)
        }).compositeOver(scheme.surface)
        drawRoundRect(thumbColor,Offset(cx-thumb.width.dp.toPx()/2,size.height/2-thumb.height.dp.toPx()/2),Size(thumb.width.dp.toPx(),thumb.height.dp.toPx()),CornerRadius(thumb.height.dp.toPx()/2))
    }
}
