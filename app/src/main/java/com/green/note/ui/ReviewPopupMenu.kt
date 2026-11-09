package com.green.note.ui

import com.green.note.ui.ReviewText as Text

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.*
import kotlin.math.*

internal fun popupRouteProgress(raw:Float,opening:Boolean)=if(opening)raw else(raw/(2f/3f)).coerceIn(0f,1f)
internal fun popupInterval(progress:Float,start:Float,end:Float)=((progress-start)/(end-start)).coerceIn(0f,1f)
internal fun popupSteppedWidth(natural:Int,unit:Float,maximum:Int):Int = (ceil(natural/(56*unit))*56*unit).roundToInt().coerceIn(min((112*unit).roundToInt(),maximum),min((280*unit).roundToInt(),maximum))
private class PopupFrame {
    val items=mutableStateListOf<Any>()
    var progress:()->Float={0f}
    var enabled=true
}
private val LocalPopupFrame=staticCompositionLocalOf<PopupFrame?>{null}

/** Flutter PopupMenu defaults and route animation; distinct from DropdownButton's selection popup. */
@Composable
fun ReviewPopupMenu(expanded:Boolean,onDismissRequest:()->Unit,modifier:Modifier=Modifier,
    offset:DpOffset=DpOffset.Zero,shape:Shape=RoundedCornerShape(4.dp),containerColor:Color=MaterialTheme.colorScheme.surfaceContainer,
    tonalElevation:Dp=0.dp,shadowElevation:Dp=3.dp,properties:PopupProperties=PopupProperties(focusable=true),content:@Composable ColumnScope.()->Unit) {
    val transition=remember{Animatable(0f)}
    LaunchedEffect(expanded){
        val target=if(expanded)1f else 0f
        // A 0 -> 0 tween still becomes running, which would mount an invisible focusable window.
        if(transition.value!=target)transition.animateTo(target,tween(300,easing=LinearEasing))
    }
    if(!reviewWindowVisible()||(!expanded&&!transition.isRunning&&transition.value==0f))return
    val frame=remember{PopupFrame()}
    frame.progress={popupRouteProgress(transition.value,expanded)};frame.enabled=expanded
    val density=LocalDensity.current
    val left=WindowInsets.safeDrawing.getLeft(density,androidx.compose.ui.platform.LocalLayoutDirection.current)
    val right=WindowInsets.safeDrawing.getRight(density,androidx.compose.ui.platform.LocalLayoutDirection.current)
    val top=WindowInsets.safeDrawing.getTop(density);val bottom=WindowInsets.safeDrawing.getBottom(density)
    val edge=with(density){8.dp.roundToPx()};val dx=with(density){offset.x.roundToPx()};val dy=with(density){offset.y.roundToPx()}
    val position=remember(left,right,top,bottom,edge,dx,dy){object:PopupPositionProvider {
        override fun calculatePosition(anchorBounds:IntRect,windowSize:IntSize,layoutDirection:LayoutDirection,popupContentSize:IntSize):IntOffset {
            val endSpace=windowSize.width-anchorBounds.right
            val growLeft=anchorBounds.left>endSpace||(anchorBounds.left==endSpace&&layoutDirection==LayoutDirection.Rtl)
            val x=(if(growLeft)anchorBounds.right-popupContentSize.width else anchorBounds.left)+dx
            val minX=left+edge;val maxX=max(minX,windowSize.width-right-edge-popupContentSize.width)
            val minY=top+edge;val maxY=max(minY,windowSize.height-bottom-edge-popupContentSize.height)
            return IntOffset(x.coerceIn(minX,maxX),(anchorBounds.top+dy).coerceIn(minY,maxY))
        }
    }}
    Popup(position,onDismissRequest=onDismissRequest,properties=properties) {
        CompositionLocalProvider(LocalPopupFrame provides frame) {
            Surface(modifier.stopWindowScrollOnPress().graphicsLayer{alpha=popupInterval(frame.progress(),0f,1f/3f)},shape=shape,color=containerColor,
                tonalElevation=tonalElevation,shadowElevation=shadowElevation) {
                Layout(content={Column(Modifier.verticalScroll(rememberReviewScrollState()).padding(vertical=8.dp),content=content)}) { measurables,constraints ->
                    val child=measurables.single()
                    val maxWidth=min((280*this.density).roundToInt(),constraints.maxWidth).coerceAtLeast(0)
                    val natural=child.maxIntrinsicWidth(constraints.maxHeight).coerceAtMost(maxWidth)
                    val width=popupSteppedWidth(natural,this.density,maxWidth)
                    val maximumHeight=(constraints.maxHeight-top-bottom-edge*2).coerceAtLeast(0)
                    val placeable=child.measure(constraints.copy(minWidth=width,maxWidth=width,minHeight=0,maxHeight=maximumHeight))
                    val count=frame.items.size.coerceAtLeast(1);val unit=1f/(count+1.5f);val progress=frame.progress()
                    val visibleWidth=(width*popupInterval(progress,0f,unit)).roundToInt().coerceAtLeast(1)
                    val visibleHeight=(placeable.height*popupInterval(progress,0f,unit*count)).roundToInt().coerceAtLeast(1)
                    layout(visibleWidth,visibleHeight){placeable.placeRelative(visibleWidth-width,0)}
                }
            }
        }
    }
}

@Composable
fun ReviewPopupMenuItem(text:@Composable ()->Unit,onClick:()->Unit,modifier:Modifier=Modifier,
    leadingIcon:(@Composable ()->Unit)?=null,trailingIcon:(@Composable ()->Unit)?=null,enabled:Boolean=true,
    contentPadding:PaddingValues=PaddingValues(horizontal=12.dp),height:Dp=48.dp,iconSpacing:Dp=8.dp) {
    val frame=LocalPopupFrame.current;val token=remember{Any()}
    DisposableEffect(frame,token){frame?.items?.add(token);onDispose{frame?.items?.remove(token)}}
    val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.let{it.red+it.green+it.blue<1.5f}
    val color=if(enabled)scheme.onSurface else scheme.onSurface.copy(alpha=.38f)
    val iconColor=LocalMaterialGlyphColor.current.let{if(enabled)it else it.copy(alpha=it.alpha*if(dark).5f else .38f)}
    Row(modifier.fillMaxWidth().graphicsLayer {
        if(frame!=null){val count=frame.items.size.coerceAtLeast(1);val index=frame.items.indexOf(token).coerceAtLeast(0);val unit=1f/(count+1.5f)
            alpha=popupInterval(frame.progress(),(index+1)*unit,min(1f,(index+2.5f)*unit))}
    }.clickable(enabled=enabled&&(frame?.enabled!=false),interactionSource=remember{MutableInteractionSource()},indication=null,role=Role.Button,onClick={if(frame?.enabled!=false)onClick()})
        .heightIn(min=height).padding(contentPadding),verticalAlignment=Alignment.CenterVertically) {
        if(leadingIcon!=null){CompositionLocalProvider(LocalContentColor provides iconColor,LocalMaterialGlyphColor provides iconColor,LocalIconButtonColor provides iconColor){leadingIcon()};Spacer(Modifier.width(iconSpacing))}
        Box(Modifier.weight(1f)){CompositionLocalProvider(LocalContentColor provides color,LocalTextStyle provides MaterialTheme.typography.labelLarge.copy(color=Color.Unspecified)){text()}}
        if(trailingIcon!=null){Spacer(Modifier.width(iconSpacing));CompositionLocalProvider(LocalContentColor provides iconColor,LocalMaterialGlyphColor provides iconColor,LocalIconButtonColor provides iconColor){trailingIcon()}}
    }
}
