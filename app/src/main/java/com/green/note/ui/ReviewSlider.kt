package com.green.note.ui

import android.os.SystemClock
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.*

/** Geometry from Flutter's year2023 discrete Slider, not the later gapped handle slider. */
internal object ReviewSliderGeometry {
    fun discrete(value:Float,range:ClosedFloatingPointRange<Float>,divisions:Int):Float {
        val fraction=((value-range.start)/(range.endInclusive-range.start)).coerceIn(0f,1f)
        return range.start + (fraction*divisions).roundToInt().toFloat()/divisions*(range.endInclusive-range.start)
    }
    fun thumbX(width:Float,fraction:Float,overlayRadius:Float=24f,trackHeight:Float=4f,discrete:Boolean=true):Float {
        val padding=if(discrete)trackHeight else 0f
        return overlayRadius+padding/2+fraction.coerceIn(0f,1f)*(width-overlayRadius*2-padding).coerceAtLeast(0f)
    }
    fun fractionAt(width:Float,x:Float,overlayRadius:Float=24f):Float = ((x-overlayRadius)/(width-overlayRadius*2).coerceAtLeast(1f)).coerceIn(0f,1f)
    fun indicatorWidth(labelWidth:Float,scale:Float)= (max(20f,labelWidth)+8f)*scale
    fun labelShift(center:Float,windowWidth:Float,rectangleWidth:Float,textScale:Float):Float {
        val left=max(0f,rectangleWidth/2-center+8)
        val right=max(0f,rectangleWidth/2-(windowWidth-center-8))
        return if(rectangleWidth<windowWidth)left-right else if(left-right>0)left-8*textScale else -right+8*textScale
    }
}

@Composable
fun ReviewSlider(value:Float,onValueChange:(Float)->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,
    valueRange:ClosedFloatingPointRange<Float> = 0f..1f,divisions:Int=9,label:String?="${(value*100).roundToInt()}%",
    onValueChangeFinished:(()->Unit)?=null,thumbRadius:Dp=10.dp,overlayRadius:Dp=24.dp,trackHeight:Dp=4.dp,
    activeColor:Color?=null,inactiveColor:Color?=null,thumbColor:Color?=null,selectionHaptics:Boolean=true) {
    require(divisions>=0 && valueRange.endInclusive>valueRange.start)
    val density=LocalDensity.current
    val rtl=LocalLayoutDirection.current==LayoutDirection.Rtl
    val scheme=MaterialTheme.colorScheme
    val view=LocalView.current
    val haptics=LocalAppPreferences.current.haptics
    val scope=rememberCoroutineScope()
    val latestValue by rememberUpdatedState(value)
    val latestChange by rememberUpdatedState(onValueChange)
    val latestFinished by rememberUpdatedState(onValueChangeFinished)
    var held by remember{mutableStateOf(false)}
    var showUntil by remember{mutableLongStateOf(0)}
    var indicator by remember{mutableStateOf(false)}
    var width by remember{mutableFloatStateOf(0f)}
    var origin by remember{mutableStateOf(Offset.Zero)}
    val normalized=(((if(divisions>0)ReviewSliderGeometry.discrete(value,valueRange,divisions)else value.coerceIn(valueRange))-valueRange.start)/(valueRange.endInclusive-valueRange.start)).coerceIn(0f,1f)
    val position=remember{Animatable(normalized)}
    LaunchedEffect(normalized){position.animateTo(normalized,tween(75,easing=CubicBezierEasing(.42f,0f,.58f,1f)))}
    LaunchedEffect(held,showUntil){if(held){indicator=true}else{delay((showUntil-SystemClock.uptimeMillis()).coerceAtLeast(0));indicator=false}}
    val activation=remember{Animatable(0f)}
    LaunchedEffect(held){val target=if(held)1f else 0f;activation.animateTo(target,tween((100*abs(target-activation.value)).roundToInt(),easing=LinearEasing))}
    val activate=FastOutSlowInEasing.transform(activation.value)
    val enable by animateFloatAsState(if(enabled)1f else 0f,tween(75,easing=CubicBezierEasing(.42f,0f,.58f,1f)),label="slider enable")
    // Flutter runs the same curved controller backwards, including its interrupted fraction.
    val reveal=remember{Animatable(0f)}
    LaunchedEffect(indicator,enabled){reveal.animateTo(if(indicator&&enabled)1f else 0f,tween((100*abs((if(indicator&&enabled)1f else 0f)-reveal.value)).roundToInt(),easing=LinearEasing))}
    val indicatorScale=FastOutSlowInEasing.transform(reveal.value)
    fun fraction()=if(divisions>0)position.value else normalized
    fun thumbX(widthPx:Float,f:Float)=ReviewSliderGeometry.thumbX(widthPx/density.density,f,overlayRadius.value,trackHeight.value,divisions>0)*density.density
    fun change(candidate:Float,feedback:Boolean=true){val snapped=if(divisions>0)ReviewSliderGeometry.discrete(candidate,valueRange,divisions)else candidate.coerceIn(valueRange);if(if(divisions>0)abs(snapped-latestValue)>.00001f else snapped!=latestValue){if(feedback&&divisions>0&&selectionHaptics)AppHaptics.selection(view,haptics,tick=true);latestChange(snapped)}}
    fun begin(){held=true;showUntil=SystemClock.uptimeMillis()+500}
    val controlHeight=max(overlayRadius.value,thumbRadius.value)*2
    Box(modifier.height(controlHeight.dp).onGloballyPositioned{width=it.size.width.toFloat();origin=it.positionInWindow()}
        .semantics {
            if(label!=null)contentDescription=label
            progressBarRangeInfo=ProgressBarRangeInfo(value.coerceIn(valueRange),valueRange,(divisions-1).coerceAtLeast(0))
            if(!enabled)disabled() else setProgress {change(it);true}
        }.onKeyEvent{event->if(!enabled||event.type!=KeyEventType.KeyDown)false else {
            val delta=when(event.key){Key.DirectionRight->if(rtl)-1 else 1;Key.DirectionLeft->if(rtl)1 else -1;Key.DirectionUp->1;Key.DirectionDown->-1;else->0}
            if(delta==0)false else{change(latestValue+delta*(valueRange.endInclusive-valueRange.start)/(if(divisions>0)divisions else 10));true}
        }}.focusable(enabled)
        .pointerInput(enabled,rtl,valueRange,divisions,density.density,haptics,selectionHaptics){if(enabled)awaitEachGesture{
            val down=awaitFirstDown(requireUnconsumed=false)
            var dragging=false
            var cancelled=false
            var lastFeedbackStep=if(divisions>0)ReviewSliderGeometry.discrete(latestValue,valueRange,divisions)else latestValue
            fun changeAt(x:Float,feedback:Boolean=false){
                val f=ReviewSliderGeometry.fractionAt(size.width/density.density,x/density.density,overlayRadius.value)
                val candidate=valueRange.start+(if(rtl)1-f else f)*(valueRange.endInclusive-valueRange.start)
                if(feedback&&divisions>0){
                    val step=ReviewSliderGeometry.discrete(candidate,valueRange,divisions)
                    if(abs(step-lastFeedbackStep)>.00001f){if(selectionHaptics)AppHaptics.selection(view,haptics,tick=true);lastFeedbackStep=step}
                }
                change(candidate,feedback=false)
            }
            val timer=scope.launch{delay(100);begin();changeAt(down.position.x)}
            try {
                while(true){
                    val event=awaitPointerEvent()
                    val p=event.changes.firstOrNull{it.id==down.id}?:break
                    if(p.isConsumed){cancelled=true;break}
                    if(!p.pressed){if(!dragging){begin();changeAt(p.position.x);if(selectionHaptics)AppHaptics.selection(view,haptics)};p.consume();break}
                    val delta=p.position-down.position
                    if(!dragging&&abs(delta.y)>viewConfiguration.touchSlop&&abs(delta.y)>abs(delta.x)){cancelled=true;break}
                    if(!dragging&&abs(delta.x)>viewConfiguration.touchSlop){dragging=true;timer.cancel();begin()}
                    if(dragging){changeAt(p.position.x,feedback=true);p.consume()}
                }
            } finally {timer.cancel();if(held)latestFinished?.invoke();held=false;if(cancelled)showUntil=0}
        }}) {
        Canvas(Modifier.fillMaxSize()) {
            val f=if(rtl)1-fraction() else fraction()
            val x=thumbX(size.width,f)
            val y=size.height/2
            val left=overlayRadius.toPx();val right=size.width-left
            val active=lerp(scheme.onSurface.copy(alpha=.38f),activeColor?:scheme.primary,enable)
            val inactive=lerp(scheme.onSurface.copy(alpha=.12f),inactiveColor?:scheme.surfaceContainerHighest,enable)
            val half=trackHeight.toPx()/2;val activeHalf=half+1.dp.toPx()
            if(x<right-half)drawRoundRect(if(rtl)active else inactive,Offset(x-half,y-if(rtl)activeHalf else half),Size(right-x+half,2*(if(rtl)activeHalf else half)),CornerRadius(if(rtl)activeHalf else half))
            if(x>left+half)drawRoundRect(if(rtl)inactive else active,Offset(left,y-if(rtl)half else activeHalf),Size(x-left+half,2*(if(rtl)half else activeHalf)),CornerRadius(if(rtl)half else activeHalf))
            if(divisions>0&&right-left-trackHeight.toPx()>=divisions*trackHeight.toPx()*1.5f)for(i in 0..divisions){
                val tick=left+half+i.toFloat()/divisions*(right-left-trackHeight.toPx())
                val activeTick=if(rtl)tick>=x else tick<=x
                val color=lerp(scheme.onSurface.copy(alpha=.38f),if(activeTick)scheme.onPrimary.copy(alpha=.38f)else scheme.onSurfaceVariant.copy(alpha=.38f),enable)
                drawCircle(color,trackHeight.toPx()/4,Offset(tick,y))
            }
        }
        Box(Modifier.offset {val f=if(rtl)1-fraction() else fraction();IntOffset((thumbX(width,f)-thumbRadius.toPx()).roundToInt(),((controlHeight/2).dp-thumbRadius).roundToPx())}
            .size(thumbRadius*2).shadow((1+5*activate).dp,CircleShape,clip=false)
            .background(lerp(scheme.onSurface.copy(alpha=.38f).compositeOver(scheme.surface),thumbColor?:scheme.primary,enable),CircleShape))
    }
    if(label!=null&&indicatorScale>0&&reviewWindowVisible()){
        val f=if(rtl)1-fraction() else fraction()
        val center=origin+Offset(thumbX(width,f),with(density){(controlHeight/2).dp.toPx()})
        SliderValueIndicator(center,label,indicatorScale)
    }
}

@Composable private fun SliderValueIndicator(center:Offset,label:String,scale:Float){
    val density=LocalDensity.current
    val scheme=MaterialTheme.colorScheme
    val measurer=rememberTextMeasurer()
    val text=measurer.measure(label,MaterialTheme.typography.labelMedium.copy(color=scheme.onPrimary))
    val rectangleWidth=ReviewSliderGeometry.indicatorWidth(text.size.width/density.density,scale)
    val boxWidth=max(80f,rectangleWidth+32)
    val provider=remember(center,boxWidth,density.density){object:PopupPositionProvider{
        override fun calculatePosition(anchorBounds:IntRect,windowSize:IntSize,layoutDirection:LayoutDirection,popupContentSize:IntSize)=
            IntOffset((center.x-popupContentSize.width/2).roundToInt(),(center.y-16*density.density-popupContentSize.height).roundToInt())
    }}
    val windowWidth=LocalWindowInfo.current.containerSize.width/density.density
    val shift=ReviewSliderGeometry.labelShift(center.x/density.density,windowWidth,rectangleWidth,density.fontScale)
    Popup(popupPositionProvider=provider,properties=PopupProperties(focusable=false,dismissOnClickOutside=false,dismissOnBackPress=false,clippingEnabled=false)){
        Canvas(Modifier.size(boxWidth.dp,64.dp)){
            translate(size.width/2,size.height){scale(scale,scale,Offset.Zero){
                val rect=Rect((-rectangleWidth/2+shift).dp.toPx(),(-34).dp.toPx(),(rectangleWidth/2+shift).dp.toPx(),(-6).dp.toPx())
                val radius=min(rect.width,rect.height)/2
                val path=Path().apply{moveTo(0f,0f);lineTo((-10).dp.toPx(),(-10).dp.toPx());lineTo(10.dp.toPx(),(-10).dp.toPx());close();addRoundRect(RoundRect(rect,CornerRadius(radius)))}
                drawPath(path,scheme.primary)
                drawText(text,topLeft=Offset(shift.dp.toPx()-text.size.width/2,(-20).dp.toPx()-text.size.height/2))
            }}
        }
    }
}
