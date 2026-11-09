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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.*
import kotlin.math.*

internal data class DropdownPlacement(val top:Float,val height:Float,val scroll:Float)
/** Flutter _DropdownRoute.getMenuLimits, using its fixed 48dp items and 8dp list padding. */
internal fun reviewDropdownPlacement(top:Float,bottom:Float,windowHeight:Float,count:Int,selected:Int,unit:Float=1f):DropdownPlacement {
    val item=48*unit;val selectedOffset=8*unit+item*selected
    val preferred=16*unit+count*item
    val height=min(preferred,(windowHeight-2*item).coerceAtLeast(item))
    val topLimit=min(item,top);val bottomLimit=max(windowHeight-item,bottom)
    var menuTop=top-selectedOffset-(item-(bottom-top))/2
    var menuBottom=menuTop+height
    if(menuTop<topLimit){menuTop=min(top,topLimit);menuBottom=menuTop+height}
    if(menuBottom>bottomLimit){menuBottom=max(bottom,bottomLimit);menuTop=menuBottom-height}
    if(menuBottom-item/2<bottom-(bottom-top)/2){menuBottom=bottom-(bottom-top)/2+item/2;menuTop=menuBottom-height}
    val scroll=if(preferred>height)(selectedOffset-(top-menuTop)).coerceIn(0f,preferred-height)else 0f
    return DropdownPlacement(menuTop,height,scroll)
}

/** Original DropdownButton popup: selected row alignment, 2dp shape and three-stage 300ms reveal. */
@Composable
fun ReviewDropdownMenu(expanded:Boolean,onDismiss:()->Unit,items:List<String>,selectedIndex:Int,anchor:IntRect,onSelect:(Int)->Unit) {
    val progress=remember{Animatable(0f)}
    var selectedAtOpen by remember{mutableIntStateOf(selectedIndex.coerceIn(0,items.lastIndex))}
    LaunchedEffect(expanded){
        if(expanded)selectedAtOpen=selectedIndex.coerceIn(0,items.lastIndex)
        val target=if(expanded)1f else 0f
        if(progress.value!=target)progress.animateTo(target,tween(300,easing=LinearEasing))
    }
    if(!reviewWindowVisible()||(!expanded&&!progress.isRunning&&progress.value==0f))return
    val density=LocalDensity.current;val unit=density.density
    val window=LocalWindowInfo.current.containerSize
    val placement=reviewDropdownPlacement(anchor.top.toFloat(),anchor.bottom.toFloat(),window.height.toFloat(),items.size,selectedAtOpen,unit)
    val width=with(density){(anchor.width+40*unit).coerceAtMost(window.width.toFloat()).toDp()}
    val height=with(density){placement.height.toDp()}
    val scroll=rememberReviewScrollState()
    LaunchedEffect(expanded,selectedAtOpen){if(expanded)scroll.scrollTo(placement.scroll.roundToInt())}
    val position=remember(anchor,items.size,selectedAtOpen,unit){object:PopupPositionProvider {
        override fun calculatePosition(anchorBounds:IntRect,windowSize:IntSize,layoutDirection:LayoutDirection,popupContentSize:IntSize):IntOffset {
            val bounds=reviewDropdownPlacement(anchor.top.toFloat(),anchor.bottom.toFloat(),windowSize.height.toFloat(),items.size,selectedAtOpen,unit)
            val desired=if(layoutDirection==LayoutDirection.Ltr)anchor.left-16*unit else anchor.right-popupContentSize.width+16*unit
            return IntOffset(desired.roundToInt().coerceIn(0,(windowSize.width-popupContentSize.width).coerceAtLeast(0)),bounds.top.roundToInt())
        }
    }}
    Popup(position,onDismissRequest=onDismiss,properties=PopupProperties(focusable=true)) {
        val fraction=progress.value
        val opacity=if(expanded)(fraction/.25f).coerceIn(0f,1f)else((fraction-.75f)/.25f).coerceIn(0f,1f)
        val resize=if(expanded)((fraction-.25f)/.25f).coerceIn(0f,1f)else if(fraction>0f)1f else 0f
        val startTop=(8*unit+48*unit*selectedAtOpen).coerceIn(0f,(placement.height-48*unit).coerceAtLeast(0f))
        val top=startTop*(1-resize)
        val bottom=(startTop+48*unit).coerceIn(min(48*unit,placement.height),placement.height)*(1-resize)+placement.height*resize
        Box(Modifier.stopWindowScrollOnPress().width(width).height(height).graphicsLayer{alpha=opacity}) {
            Surface(Modifier.fillMaxWidth().offset{IntOffset(0,top.roundToInt())}.height(with(density){(bottom-top).toDp()}),
                shape=RoundedCornerShape(2.dp),color=MaterialTheme.colorScheme.surface,shadowElevation=8.dp,tonalElevation=0.dp){}
            Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(vertical=8.dp)) {
                items.forEachIndexed { index,label ->
                    val timing=.5f/(items.size+1.5f);val begin=(.5f+(index+1)*timing).coerceIn(0f,1f);val end=(begin+1.5f*timing).coerceIn(0f,1f)
                    val itemOpacity=if(!expanded||index==selectedAtOpen)1f else((fraction-begin)/(end-begin)).coerceIn(0f,1f)
                    Box(Modifier.fillMaxWidth().height(48.dp).graphicsLayer{alpha=itemOpacity}
                        .semantics{selected=index==selectedAtOpen}.clickable(interactionSource=remember{MutableInteractionSource()},indication=null,role=Role.Button,onClick={onSelect(index)})
                        .padding(horizontal=16.dp),contentAlignment=Alignment.CenterStart) {Text(label,style=MaterialTheme.typography.titleMedium)}
                }
            }
        }
    }
}
