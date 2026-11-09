package com.green.note.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.*
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner

/** Defaults from app_theme.dart; explicit Text styles inside caller slots retain precedence. */
@Composable
fun ReviewAlertDialog(onDismissRequest:()->Unit,confirmButton:@Composable ()->Unit,modifier:Modifier=Modifier,
    dismissButton:(@Composable ()->Unit)?=null,icon:(@Composable ()->Unit)?=null,title:(@Composable ()->Unit)?=null,text:(@Composable ()->Unit)?=null,
    shape:Shape=RoundedCornerShape(28.dp),containerColor:Color=MaterialTheme.colorScheme.surfaceContainerHigh,
    iconContentColor:Color=MaterialTheme.colorScheme.secondary,titleContentColor:Color=MaterialTheme.colorScheme.onSurface,
    textContentColor:Color=MaterialTheme.colorScheme.onSurfaceVariant,tonalElevation:Dp=0.dp,
    properties:DialogProperties=DialogProperties(usePlatformDefaultWidth=false),appDialog:Boolean=false) {
    if(!reviewWindowVisible())return
    // Flutter's dialog theme replaces DefaultTextStyle with a fresh TextStyle: no inherited height or font family.
    val titleStyle=TextStyle(localeList=ReviewTextLocales,fontSize=18.sp,fontWeight=adjustedWeight(700),platformStyle=PlatformTextStyle(includeFontPadding=false))
    val textStyle=TextStyle(localeList=ReviewTextLocales,fontSize=14.sp,fontWeight=adjustedWeight(400),platformStyle=PlatformTextStyle(includeFontPadding=false))
    val paddingScale=reviewDialogPaddingScale(with(LocalDensity.current){14.sp.toDp().value/14f})
    Dialog(onDismissRequest,properties=properties) {
        ReviewDialogWindow(appDialog)
        Surface(modifier.stopWindowScrollOnPress().padding(horizontal=40.dp,vertical=24.dp).widthIn(min=280.dp).width(IntrinsicSize.Max),
            shape=shape,color=containerColor,tonalElevation=tonalElevation) {
            Column {
                icon?.let {
                    Box(Modifier.fillMaxWidth().padding(start=(24*paddingScale).dp,end=(24*paddingScale).dp,top=(24*paddingScale).dp,
                        bottom=if(title!=null)16.dp else if(text!=null)0.dp else 24.dp),contentAlignment=Alignment.Center) {
                        CompositionLocalProvider(LocalMaterialGlyphColor provides iconContentColor,LocalContentColor provides iconContentColor){it()}
                    }
                }
                title?.let {
                    Box(Modifier.fillMaxWidth().padding(start=(24*paddingScale).dp,end=(24*paddingScale).dp,
                        top=if(icon==null)(24*paddingScale).dp else 0.dp,bottom=if(text==null)20.dp else 0.dp)) {
                        CompositionLocalProvider(LocalContentColor provides titleContentColor,
                            LocalTextStyle provides titleStyle.copy(textAlign=if(icon==null)TextAlign.Start else TextAlign.Center)){it()}
                    }
                }
                text?.let {
                    Box(Modifier.weight(1f,fill=false).fillMaxWidth().padding(start=(24*paddingScale).dp,end=(24*paddingScale).dp,
                        top=if(title==null&&icon==null)(16*paddingScale).dp else 16.dp,bottom=24.dp)) {
                        CompositionLocalProvider(LocalContentColor provides textContentColor,LocalTextStyle provides textStyle){it()}
                    }
                }
                ReviewDialogActions(Modifier.fillMaxWidth().padding(start=24.dp,end=24.dp,bottom=24.dp),dismissButton,confirmButton)
            }
        }
    }
}

internal fun reviewDialogPaddingScale(textScale:Float)=1f-(textScale.coerceIn(1f,2f)-1f)*2f/3f

// Compose's measured sizes are finite 24-bit dimensions; Infinity is a query/constraint sentinel.
private const val maxDialogActionDimension = 0x00ffffff
internal fun reviewDialogNaturalWidth(widths:List<Int>,gap:Int):Int =
    (widths.sumOf { it.toLong() } + gap.toLong() * (widths.size - 1).coerceAtLeast(0))
        .coerceIn(0,maxDialogActionDimension.toLong()).toInt()

internal fun reviewDialogActionWidth(sizes:List<IntSize>,constraints:Constraints,gap:Int):Int =
    if(constraints.hasBoundedWidth) constraints.maxWidth
    else constraints.constrainWidth(reviewDialogNaturalWidth(sizes.map { it.width },gap))

internal fun reviewDialogIntrinsicHeight(widths:List<Int>,heights:List<Int>,width:Int,gap:Int):Int {
    val rowWidth=widths.sumOf { it.toLong() } + gap.toLong() * (widths.size - 1).coerceAtLeast(0)
    return (if(rowWidth>width) heights.sumOf { it.toLong() } else (heights.maxOrNull()?:0).toLong())
        .coerceIn(0,maxDialogActionDimension.toLong()).toInt()
}

internal fun reviewDialogActionPositions(sizes:List<IntSize>,width:Int,gap:Int):List<IntOffset> {
    val rowWidth=sizes.sumOf{it.width.toLong()}+gap.toLong()*(sizes.size-1).coerceAtLeast(0)
    return if(rowWidth<=width) {
        var x=(width-rowWidth).toInt();val height=sizes.maxOfOrNull{it.height}?:0
        sizes.map{size->IntOffset(x,(height-size.height)/2).also{x+=size.width+gap}}
    } else {
        var y=0;sizes.map{size->IntOffset(width-size.width,y).also{y+=size.height}}
    }
}

@Composable
private fun ReviewDialogActions(modifier:Modifier,dismiss:(@Composable ()->Unit)?,confirm:@Composable ()->Unit) {
    val gap=with(LocalDensity.current){8.dp.roundToPx()}
    Layout(modifier=modifier,content={dismiss?.let{Box{it()}};Box{confirm()}},measurePolicy=remember(gap){ReviewDialogActionsMeasurePolicy(gap)})
}

/** Flutter OverflowBar's four intrinsic queries must not use Compose's fake measure fallback. */
internal class ReviewDialogActionsMeasurePolicy(private val gap:Int):MeasurePolicy {
        override fun MeasureScope.measure(measurables:List<Measurable>,constraints:Constraints):MeasureResult {
            val children=measurables.map{it.measure(constraints.copy(minWidth=0,minHeight=0))}
            val sizes=children.map{IntSize(it.width,it.height)}
            val width=reviewDialogActionWidth(sizes,constraints,gap)
            val points=reviewDialogActionPositions(sizes,width,gap)
            val height=constraints.constrainHeight(reviewDialogIntrinsicHeight(sizes.map { it.width },sizes.map { it.height },width,gap))
            return layout(width,height){children.forEachIndexed{i,child->child.placeRelative(points[i].x,points[i].y)}}
        }
        override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables:List<IntrinsicMeasurable>,height:Int)=
            reviewDialogNaturalWidth(measurables.map { it.minIntrinsicWidth(Constraints.Infinity) },gap)
        override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables:List<IntrinsicMeasurable>,height:Int)=
            reviewDialogNaturalWidth(measurables.map { it.maxIntrinsicWidth(Constraints.Infinity) },gap)
        override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables:List<IntrinsicMeasurable>,width:Int)=
            reviewDialogIntrinsicHeight(measurables.map { it.minIntrinsicWidth(Constraints.Infinity) },measurables.map { it.minIntrinsicHeight(width) },width,gap)
        override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables:List<IntrinsicMeasurable>,width:Int)=
            reviewDialogIntrinsicHeight(measurables.map { it.minIntrinsicWidth(Constraints.Infinity) },measurables.map { it.maxIntrinsicHeight(width) },width,gap)
}

@Composable
internal fun ReviewDialogWindow(appDialog:Boolean){val view=LocalView.current;SideEffect{(view.parent as? DialogWindowProvider)?.window?.let{window->window.setDimAmount(if(appDialog)128f/255 else .54f);window.setWindowAnimations(if(appDialog)com.green.note.R.style.ReviewAppDialogAnimation else com.green.note.R.style.ReviewStandardDialogAnimation)}}}

/** Covered routes stay composed, but their separate platform windows must not cover the foreground route. */
@Composable
internal fun reviewWindowVisible():Boolean {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    val state by lifecycle.currentStateFlow.collectAsState()
    return state.isAtLeast(Lifecycle.State.STARTED)
}

@Composable
fun reviewCardSurface():Color {
    val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    return if(dark)if(LocalAppPreferences.current.pureBlackDark)Color(0xFF121212)else Color(0xFF1B1C20)else scheme.surfaceContainerLowest
}
@Composable
fun reviewCardBorder():Color {
    val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    return if(dark&&LocalAppPreferences.current.pureBlackDark)Color.White.copy(alpha=.12f)else scheme.outlineVariant.copy(alpha=if(dark).2f else .25f)
}
@Composable
fun reviewSheetSurface():Color=if(LocalAppPreferences.current.pureBlackDark&&MaterialTheme.colorScheme.surface==Color.Black)Color(0xFF141414)else MaterialTheme.colorScheme.surfaceContainerLow

@Composable
fun ReviewSheetDragHandle(){Box(Modifier.size(48.dp),contentAlignment=Alignment.Center){Box(Modifier.size(38.dp,4.5.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha=.4f),RoundedCornerShape(2.25.dp)))}}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewModalBottomSheet(onDismissRequest:()->Unit,modifier:Modifier=Modifier,sheetState:SheetState=rememberModalBottomSheetState(),
    sheetMaxWidth:Dp=640.dp,shape:Shape=RoundedCornerShape(topStart=28.dp,topEnd=28.dp),containerColor:Color=reviewSheetSurface(),
    contentColor:Color=contentColorFor(containerColor),tonalElevation:Dp=0.dp,scrimColor:Color=Color.Black.copy(alpha=.54f),
    dragHandle:(@Composable ()->Unit)?={ReviewSheetDragHandle()},contentWindowInsets:@Composable ()->WindowInsets={BottomSheetDefaults.windowInsets},
    properties:ModalBottomSheetProperties=ModalBottomSheetProperties(),content:@Composable ColumnScope.()->Unit) {
    if(!reviewWindowVisible())return
    ModalBottomSheet(onDismissRequest,modifier.stopWindowScrollOnPress(),sheetState,sheetMaxWidth,shape=shape,containerColor=containerColor,contentColor=contentColor,tonalElevation=tonalElevation,scrimColor=scrimColor,dragHandle=dragHandle,contentWindowInsets=contentWindowInsets,properties=properties,content=content)
}

@Composable
internal fun Modifier.stopWindowScrollOnPress(): Modifier {
    val requests = LocalScrollRateController.current?.requests ?: return this
    val scope = rememberCoroutineScope()
    return pointerInput(requests, scope) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Final)
            requests.stopOnPress(scope)
        }
    }
}
