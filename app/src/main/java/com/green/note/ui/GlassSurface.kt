package com.green.note.ui

import android.graphics.RectF
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import kotlin.math.*

/** The gallery's original glass material. Place it in GlassBackdropHost.overlay. */
enum class GlassMaterial { GALLERY, NAVIGATION }
@Composable
fun GlassSurface(modifier:Modifier=Modifier,cornerRadius:Dp=24.dp,opacity:Float=1f,liquid:Boolean?=null,
    interactive:Boolean=true,material:GlassMaterial=GlassMaterial.GALLERY,tintColor:Color?=null,themeAdaptive:Boolean=true,content:@Composable BoxScope.()->Unit) {
    val useLiquid=liquid ?: LocalAppPreferences.current.liquidGlassNavBar
    val density=LocalDensity.current
    val scheme=androidx.compose.material3.MaterialTheme.colorScheme
    val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    val (host,region)=rememberBackdropRegion()
    var presentationReady by remember { mutableStateOf(false) }
    var logicalSize by remember { mutableStateOf(IntSize.Zero) }
    var viewportSize by remember { mutableStateOf(IntSize.Zero) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var pressed by remember { mutableStateOf(false) }
    var touchPoint by remember {mutableStateOf(Offset.Zero)}
    val touchIntensity by animateFloatAsState(if(pressed)1f else 0f,spring(if(pressed).86f else 1f,(2*PI/if(pressed).15 else .5).pow(2).toFloat()),label="glass button light")
    val touchRadius by animateFloatAsState(if(pressed)1f else 1.2f,spring(if(pressed).86f else 1f,(2*PI/if(pressed).15 else .5).pow(2).toFloat()),label="glass button halo")
    var drag by remember { mutableStateOf(Offset.Zero) }
    val grow by animateFloatAsState(if(pressed)1f else 0f,
        spring(if(pressed).75f else .55f,(2*PI/if(pressed).25 else .28).pow(2).toFloat()),label="glass press")
    val damped=drag/(1+drag.getDistance()*.01f)*.8f
    val movement by animateOffsetAsState(if(pressed)damped else Offset.Zero,
        spring(if(pressed).8f else .5f,(2*PI/if(pressed).15 else .5).pow(2).toFloat()),label="glass stretch")
    val w=with(density){logicalSize.width.toDp().value}.coerceAtLeast(1f)
    val h=with(density){logicalSize.height.toDp().value}.coerceAtLeast(1f)
    val transform=GalleryStretch.calculate(w,h,movement.x,movement.y,grow)
    Box(modifier.onGloballyPositioned { logicalSize=it.size }.pointerInput(useLiquid,interactive) {
        if(useLiquid && interactive)awaitEachGesture {
            val down=awaitFirstDown(requireUnconsumed=false,pass=PointerEventPass.Initial)
            pressed=true;drag=Offset.Zero;touchPoint=down.position
            try { do { val event=awaitPointerEvent(PointerEventPass.Initial);val change=event.changes.firstOrNull {it.id==down.id} ?: break
                drag=(change.position-down.position)/density.density
                val point=Offset(change.position.x.coerceIn(0f,logicalSize.width.toFloat()),change.position.y.coerceIn(0f,logicalSize.height.toFloat()))
                if((point-touchPoint).getDistanceSquared()>=9*density.density*density.density)touchPoint=point
                if(!change.pressed)break
            }while(true) } finally { pressed=false;drag=Offset.Zero }
        }
    },contentAlignment=Alignment.Center) {
        val pad=24.dp;val padding=with(density){pad.toPx()}
        AndroidView(factory={GlassTextureView(it).apply {
            onCaptureTarget={target->region.target=target;host?.request()}
            onPresentationReady={presentationReady=it}
        }},
            modifier=Modifier.requiredSize(with(density){logicalSize.width.toDp()}+pad*2,with(density){logicalSize.height.toDp()}+pad*2)
                .onGloballyPositioned { origin=it.positionInRoot();viewportSize=it.size
                    val bounds=Rect(origin,androidx.compose.ui.geometry.Size(it.size.width.toFloat(),it.size.height.toFloat()))
                    if(region.bounds!=bounds){region.bounds=bounds;host?.request()} },
            update={control->if(viewportSize.width>0 && logicalSize.width>0) {
                val inset=if(useLiquid)0f else 2*density.density
                val body=RectF(padding+inset,padding+inset,viewportSize.width-padding-inset,viewportSize.height-padding-inset)
                if(useLiquid) {
                    val cx=body.centerX()+transform.translationX*density.density;val cy=body.centerY()+transform.translationY*density.density
                    val bw=body.width()*transform.scaleX;val bh=body.height()*transform.scaleY
                    body.set(cx-bw/2,cy-bh/2,cx+bw/2,cy+bh/2)
                }
                val style=if(material==GlassMaterial.NAVIGATION)GlassSurfaceStyle(if(dark||!themeAdaptive)0x66000000 else 0xF0FFFFFF.toInt(),visibility=opacity,rimLight=if(dark||!themeAdaptive)0f else 1f)
                else GlassSurfaceStyle(0x66000000,32f,1.24f,.025f,if(useLiquid)2f else 2.5f*opacity,.25f,1.5f,
                    visibility=opacity,legacyGallery=!useLiquid,oval=useLiquid && logicalSize.width==logicalSize.height)
                control.submit(GlassDrawRequest(origin,viewportSize.width,viewportSize.height,density.density,body,with(density){cornerRadius.toPx()},if(tintColor==null)style else style.copy(color=tintColor.toArgb()),touch=if(useLiquid&&interactive)GlassTouchFrame(touchPoint+Offset(padding,padding),touchIntensity,touchRadius) else null,sourceSize=host?.size,shapeScale=if(useLiquid)transform.scaleX to transform.scaleY else 1f to 1f))
            }})
        // The GPU's first pipeline creation can outlast the opening animation. Keep
        // the existing material identifiable until TextureView presents a real frame.
        // Legacy gallery already supplies its own static treatment below.
        if(useLiquid&&!presentationReady) {
            val base=tintColor?:if(material==GlassMaterial.NAVIGATION&&!dark&&themeAdaptive)Color(0xF0FFFFFF)else Color(0x66000000)
            Box(Modifier.fillMaxSize().background(base.copy(alpha=base.alpha*opacity),RoundedCornerShape(cornerRadius))
                .border(1.dp,Color.White.copy(alpha=.34f*opacity),RoundedCornerShape(cornerRadius)))
        }
        if(!useLiquid)Box(Modifier.fillMaxSize().padding(2.dp).background(Brush.linearGradient(listOf(Color(0xFFE0E0E0).copy(alpha=.30f*opacity),Color(0xFF9E9E9E).copy(alpha=.20f*opacity),Color(0xFF424242).copy(alpha=.36f*opacity))),RoundedCornerShape(cornerRadius))
            .border(1.dp,Color.White.copy(alpha=.34f*opacity),RoundedCornerShape(cornerRadius)))
        Box(Modifier.fillMaxSize().graphicsLayer {
            if(useLiquid){scaleX=transform.scaleX;scaleY=transform.scaleY;translationX=transform.translationX*density.density;translationY=transform.translationY*density.density}
        },contentAlignment=Alignment.Center,content=content)
    }
}

internal data class GalleryStretch(val scaleX:Float,val scaleY:Float,val translationX:Float,val translationY:Float) {
    companion object {
        fun calculate(width:Float,height:Float,dx:Float,dy:Float,press:Float):GalleryStretch {
            val longest=max(width,height).coerceAtLeast(1f);val xDamping=min(1f,height/width);val yDamping=min(1f,width/height)
            val relativeX=abs(dx)/longest;val relativeY=abs(dy)/longest
            val sx=(1+(relativeX*.8f*xDamping).coerceAtMost(.3f))*(1-(relativeY*.3f*xDamping).coerceAtMost(.15f))
            val sy=(1+(relativeY*.8f*yDamping).coerceAtMost(.3f))*(1-(relativeX*.3f*yDamping).coerceAtMost(.15f))
            fun smooth(value:Float):Float { val t=(abs(value)/20).coerceIn(0f,1f);return sign(value)*t*t*(3-2*t) }
            val tx=width*.5f*smooth(dx)*(sx-1)+dx*.15f*xDamping*sx
            val ty=height*.5f*smooth(dy)*(sy-1)+dy*.15f*yDamping*sy
            val inflation=1+17*press/longest
            return GalleryStretch(sx*inflation,sy*inflation,tx,ty)
        }
    }
}
