package com.green.note.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.progressSemantics
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.isActive
import kotlin.math.*

internal data class CircularProgressFrame(val startDegrees:Float,val sweepDegrees:Float)
internal data class LinearProgressFrame(val firstHead:Float,val firstTail:Float,val secondHead:Float,val secondTail:Float)
internal object ReviewProgressMotion {
    private fun cubic(t:Double,a:Double,b:Double,c:Double,d:Double):Double {
        if(t<=0)return 0.0;if(t>=1)return 1.0
        fun value(x:Double,y:Double,m:Double)=3*x*(1-m)*(1-m)*m+3*y*(1-m)*m*m+m*m*m
        var start=0.0;var end=1.0
        // Flutter Cubic uses this exact error threshold; retain its sampling instead of changing the curve solver.
        while(true){val mid=(start+end)/2;val estimate=value(a,c,mid);if(abs(t-estimate)<.001)return value(b,d,mid);if(estimate<t)start=mid else end=mid}
    }
    private fun interval(t:Double,start:Double,end:Double,a:Double,b:Double,c:Double,d:Double)=cubic(((t-start)/(end-start)).coerceIn(0.0,1.0),a,b,c,d)
    fun circular(milliseconds:Double,value:Float?=null):CircularProgressFrame {
        val radiansToDegrees=180/PI
        if(value!=null)return CircularProgressFrame(-90f,(value.coerceIn(0f,1f)*(2*PI-.001)*radiansToDegrees).toFloat())
        val path=((milliseconds%1333)/1333).coerceAtLeast(0.0)
        val rotation=((milliseconds%2222)/2222).coerceAtLeast(0.0)
        val head=interval(path,0.0,.5,.4,0.0,.2,1.0)
        val tail=interval(path,.5,1.0,.4,0.0,.2,1.0)
        return CircularProgressFrame((-90+tail*270+rotation*360+path*90).toFloat(),(max((head-tail)*1.5*PI,.001)*radiansToDegrees).toFloat())
    }
    fun linear(milliseconds:Double):LinearProgressFrame {
        val t=((milliseconds%1800)/1800).coerceAtLeast(0.0)
        return LinearProgressFrame(
            interval(t,0.0,750.0/1800,.2,0.0,.8,1.0).toFloat(),
            interval(t,333.0/1800,1083.0/1800,.4,0.0,1.0,1.0).toFloat(),
            interval(t,1000.0/1800,1567.0/1800,0.0,0.0,.65,1.0).toFloat(),
            interval(t,1267.0/1800,1.0,.10,0.0,.45,1.0).toFloat())
    }
}

/** A draw-only clock: no subtree recomposition per frame, and covered/background routes stop ticking. */
@Composable
private fun rememberProgressClock(running:Boolean):State<Long> {
    val elapsed=remember{mutableLongStateOf(0L)}
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(running,lifecycle){if(running)lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED){
        var previous=withFrameNanos{it}
        while(isActive){val now=withFrameNanos{it};elapsed.longValue+=(now-previous).coerceAtLeast(0);previous=now}
    }}
    return elapsed
}

/** Flutter year2023 defaults: 36dp layout, 4dp centre stroke, square indeterminate cap, no track. */
@Composable
fun ReviewCircularProgress(modifier:Modifier=Modifier,color:Color=MaterialTheme.colorScheme.primary,strokeWidth:Dp=4.dp,
    trackColor:Color=Color.Transparent,strokeCap:StrokeCap=StrokeCap.Square) =
    ReviewCircularBody(null,modifier,color,strokeWidth,trackColor,strokeCap)

@Composable
fun ReviewCircularProgress(progress:()->Float,modifier:Modifier=Modifier,color:Color=MaterialTheme.colorScheme.primary,strokeWidth:Dp=4.dp,
    trackColor:Color=Color.Transparent,strokeCap:StrokeCap=StrokeCap.Butt) =
    ReviewCircularBody(progress,modifier,color,strokeWidth,trackColor,strokeCap)

@Composable
private fun ReviewCircularBody(progress:(()->Float)?,modifier:Modifier,color:Color,strokeWidth:Dp,trackColor:Color,strokeCap:StrokeCap) {
    val time=rememberProgressClock(progress==null)
    val value=progress?.invoke()?.coerceIn(0f,1f)
    val semantics=if(value==null)Modifier.progressSemantics()else Modifier.progressSemantics(value)
    Canvas(modifier.then(semantics).defaultMinSize(minWidth=36.dp,minHeight=36.dp)) {
        if(trackColor.alpha>0)drawArc(trackColor,0f,((2*PI-.001)*180/PI).toFloat(),false,style=Stroke(strokeWidth.toPx(),cap=StrokeCap.Round))
        val frame=ReviewProgressMotion.circular(time.value/1e6,value)
        drawArc(color,frame.startDegrees,frame.sweepDegrees,false,style=Stroke(strokeWidth.toPx(),cap=strokeCap))
    }
}

/** Original linear painter has rectangular segments, no stop dot or gaps and secondaryContainer track. */
@Composable
fun ReviewLinearProgress(modifier:Modifier=Modifier,color:Color=MaterialTheme.colorScheme.primary,trackColor:Color=MaterialTheme.colorScheme.secondaryContainer) =
    ReviewLinearBody(null,modifier,color,trackColor)

@Composable
fun ReviewLinearProgress(progress:()->Float,modifier:Modifier=Modifier,color:Color=MaterialTheme.colorScheme.primary,trackColor:Color=MaterialTheme.colorScheme.secondaryContainer) =
    ReviewLinearBody(progress,modifier,color,trackColor)

@Composable
private fun ReviewLinearBody(progress:(()->Float)?,modifier:Modifier,color:Color,trackColor:Color) {
    val time=rememberProgressClock(progress==null)
    val value=progress?.invoke()?.coerceIn(0f,1f)
    val semantics=if(value==null)Modifier.progressSemantics()else Modifier.progressSemantics(value)
    Canvas(modifier.then(semantics).fillMaxWidth().defaultMinSize(minHeight=4.dp)) {
        fun segment(start:Float,end:Float,paint:Color) {
            if(end<=start)return
            val x=if(layoutDirection==LayoutDirection.Ltr)start else 1-end
            drawRect(paint,Offset(x*size.width,0f),Size((end-start)*size.width,size.height))
        }
        if(value!=null){segment(0f,1f,trackColor);if(value>0)segment(0f,value,color)}else {
            val frame=ReviewProgressMotion.linear(time.value/1e6)
            if(frame.firstHead<1)segment(frame.firstHead,1f,trackColor)
            segment(frame.firstTail,frame.firstHead,color)
            if(frame.firstTail>0)segment(frame.secondHead,frame.firstTail,trackColor)
            segment(frame.secondTail,frame.secondHead,color)
            if(frame.secondTail>0)segment(0f,frame.secondTail,trackColor)
        }
    }
}
