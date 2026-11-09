package com.green.note.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.*
import kotlin.math.*

internal object ReviewChipGeometry {
    fun availableWidth(maxWidth: Int, reserved: Int): Int =
        if (maxWidth == Constraints.Infinity) maxWidth else (maxWidth - reserved).coerceAtLeast(0)
    fun labelPadding(fontScale:Float)=8f-4f*(fontScale-1).coerceIn(0f,1f)
    fun contentHeight(labelHeight:Float,verticalPadding:Float,labelVerticalPadding:Float)=max(32f-verticalPadding+labelVerticalPadding,labelHeight+labelVerticalPadding)
    fun interval(value:Float,start:Float)=FastOutSlowInEasing.transform(((value-start)/(1-start)).coerceIn(0f,1f))
    fun checkProgress(parent:Float,reversing:Boolean)=interval(parent,1f-(if(reversing)50f else 150f)/195f)
    fun avatarProgress(parent:Float,reversing:Boolean)=if(reversing)interval(parent,1-100f/195f)else FastOutSlowInEasing.transform(parent)
}

// Flutter RawChip paints through Ink(ShapeDecoration), whose shape dimensions also inset the child.
// A transparent selected border still occupies 1dp; explicit null represents BorderSide.none.
internal fun Modifier.reviewChipBorderInset(side: BorderStroke?): Modifier = padding(side?.width ?: 0.dp)

/** Flutter ChoiceChip/RawChip defaults; the 48dp hit target surrounds a label-sized painted chip. */
@Composable
fun ReviewChoiceChip(selected:Boolean,onClick:()->Unit,label:@Composable ()->Unit,modifier:Modifier=Modifier,
    enabled:Boolean=true,showCheckmark:Boolean=true,avatar:(@Composable ()->Unit)?=null,
    shape:Shape=RoundedCornerShape(8.dp),
    side:BorderStroke?=BorderStroke(1.dp,if(selected)Color.Transparent else if(enabled)MaterialTheme.colorScheme.outlineVariant else MaterialTheme.colorScheme.onSurface.copy(alpha=.12f)),
    padding:PaddingValues=PaddingValues(8.dp),labelPadding:PaddingValues?=null,labelStyle:TextStyle?=null,
    backgroundColor:Color=MaterialTheme.colorScheme.surface,selectedColor:Color=MaterialTheme.colorScheme.secondaryContainer,
    disabledColor:Color?=null,checkmarkColor:Color?=null,shrinkWrap:Boolean=false,compact:Boolean=false,selectionRole:Role=Role.RadioButton,
) {
    val scheme=MaterialTheme.colorScheme
    val density=LocalDensity.current
    val selection=remember{Animatable(if(selected)1f else 0f)}
    val drawer=remember{Animatable(if(avatar!=null||selected)1f else 0f)}
    val enable=remember{Animatable(if(enabled)1f else 0f)}
    LaunchedEffect(selected){selection.animateTo(if(selected)1f else 0f,tween((195*abs((if(selected)1f else 0f)-selection.value)).roundToInt(),easing=LinearEasing))}
    LaunchedEffect(selected,avatar!=null){val target=if(selected||avatar!=null)1f else 0f;drawer.animateTo(target,tween((150*abs(target-drawer.value)).roundToInt(),easing=LinearEasing))}
    LaunchedEffect(enabled){enable.animateTo(if(enabled)1f else 0f,tween((75*abs((if(enabled)1f else 0f)-enable.value)).roundToInt(),easing=LinearEasing))}
    val selectedBlend=FastOutSlowInEasing.transform(selection.value)
    val effectiveBackground=if(enabled)backgroundColor else disabledColor?:Color.Transparent
    val effectiveSelected=if(enabled)selectedColor else disabledColor?:scheme.onSurface.copy(alpha=.12f)
    val fill=lerp(effectiveBackground,effectiveSelected,selectedBlend).compositeOver(scheme.surface)
    val contentAlpha=97f/255+(1-97f/255)*FastOutSlowInEasing.transform(enable.value)
    val check=ReviewChipGeometry.checkProgress(selection.value,!selected)
    val open=if(!showCheckmark&&avatar==null)0f else ReviewChipGeometry.avatarProgress(drawer.value,avatar==null&&!selected)
    val defaultLabelColor=if(!enabled)scheme.onSurface else if(selected)scheme.onSecondaryContainer else scheme.onSurfaceVariant
    val style=MaterialTheme.typography.labelLarge.copy(color=defaultLabelColor).merge(labelStyle)
    val effectiveLabelScale=with(density){14.sp.toDp().value/14}
    val labelInset=labelPadding?:PaddingValues(horizontal=ReviewChipGeometry.labelPadding(effectiveLabelScale).dp)
    val checkColor=checkmarkColor?:if(!enabled)scheme.onSurface else if(selected)scheme.onSecondaryContainer else scheme.primary
    val click=rememberHapticClick(onClick)
    Box(modifier.defaultMinSize(minWidth=if(shrinkWrap)0.dp else if(compact)44.dp else 48.dp,minHeight=if(shrinkWrap)0.dp else if(compact)44.dp else 48.dp)
        .selectable(selected,enabled=enabled,role=selectionRole,interactionSource=remember{MutableInteractionSource()},indication=null,onClick=click),contentAlignment=Alignment.Center) {
        Layout(modifier=Modifier.background(fill,shape).then(if(side==null)Modifier else Modifier.border(side,shape)).reviewChipBorderInset(side),content={
            CompositionLocalProvider(LocalContentColor provides style.color,LocalTextStyle provides style){
                Box(Modifier.graphicsLayer{alpha=contentAlpha}){label()}
            }
            Box(Modifier.graphicsLayer{alpha=contentAlpha}.drawWithContent{
                drawContent()
                if(showCheckmark&&check>0f){
                    if(avatar!=null)drawCircle(Color(0x60191919).copy(alpha=(96f/255)*check))
                    val sideSize=size.height*.75f
                    val origin=Offset(size.height*.125f,size.height*.125f)
                    val start=Offset(sideSize*.15f,sideSize*.45f)+origin
                    val mid=Offset(sideSize*.4f,sideSize*.7f)+origin
                    val end=Offset(sideSize*.85f,sideSize*.25f)+origin
                    val t=if(selected)check else 1f
                    val path=Path().apply{moveTo(start.x,start.y);if(t<.5f){val next=lerp(start,mid,t*2);lineTo(next.x,next.y)}else{lineTo(mid.x,mid.y);val next=lerp(mid,end,(t-.5f)*2);lineTo(next.x,next.y)}}
                    drawPath(path,checkColor.copy(alpha=checkColor.alpha*(if(selected)1f else check)),style=Stroke(2.dp.toPx()*(size.height/24.dp.toPx())))
                }
            },contentAlignment=Alignment.Center){CompositionLocalProvider(LocalMaterialGlyphColor provides if(enabled)scheme.primary else scheme.onSurface,LocalMaterialGlyphSize provides 18.dp){avatar?.invoke()}}
        }) {measurables,constraints->
            val start=padding.calculateStartPadding(layoutDirection).roundToPx();val end=padding.calculateEndPadding(layoutDirection).roundToPx()
            val top=padding.calculateTopPadding().roundToPx();val bottom=padding.calculateBottomPadding().roundToPx()
            val ls=labelInset.calculateStartPadding(layoutDirection).roundToPx();val le=labelInset.calculateEndPadding(layoutDirection).roundToPx()
            val lt=labelInset.calculateTopPadding().roundToPx();val lb=labelInset.calculateBottomPadding().roundToPx()
            val labelSpace = start + end + ls + le
            val rawHeight=measurables[0].minIntrinsicHeight(ReviewChipGeometry.availableWidth(constraints.maxWidth, labelSpace))
            val content=max(32.dp.roundToPx()-top-bottom+lt+lb,rawHeight+lt+lb)
            val avatarWidth=(content*open).roundToInt()
            val text=measurables[0].measure(Constraints(maxWidth=ReviewChipGeometry.availableWidth(constraints.maxWidth, labelSpace + avatarWidth),maxHeight=content))
            val icon=measurables[1].measure(Constraints.fixed(content,content))
            val width=constraints.constrainWidth(start+avatarWidth+ls+text.width+le+end)
            val densityAdjustment=if(compact)(-2).dp.roundToPx() else 0
            val height=constraints.constrainHeight(top+content+bottom+densityAdjustment)
            layout(width,height){
                // The avatar drawer clips its growing width; final layout does not shrink the circle/check.
                if(open>0f)icon.placeRelativeWithLayer(start,top+densityAdjustment/2){clip=true;this.shape=object:Shape{override fun createOutline(size:androidx.compose.ui.geometry.Size,layoutDirection:LayoutDirection,density:Density)=Outline.Rectangle(androidx.compose.ui.geometry.Rect(0f,0f,avatarWidth.toFloat(),size.height))}}
                text.placeRelative(start+avatarWidth+ls,top+(content-text.height+densityAdjustment)/2)
            }
        }
    }
}

/** The original flat FilterChip uses the same RawChip geometry and M3 defaults, with independent selection. */
@Composable fun ReviewFilterChip(selected:Boolean,onClick:()->Unit,label:@Composable ()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true) {
    ReviewChoiceChip(selected,onClick,label,modifier,enabled,selectionRole=Role.Checkbox)
}
