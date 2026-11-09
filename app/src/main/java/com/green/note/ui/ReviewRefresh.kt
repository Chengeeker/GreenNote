package com.green.note.ui

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.animation.*
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.LinearEasing
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.yield
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.*
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewRefreshBox(isRefreshing: Boolean, onRefresh: () -> Unit, modifier: Modifier = Modifier,
    failed: Boolean = false, showText:Boolean=true,textDimension:Dp?=null,content: @Composable BoxScope.() -> Unit,
) {
    val density = LocalDensity.current
    val distance = with(density) { 70.dp.toPx() }
    var lastUpdated by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var completed by remember { mutableStateOf(false) }
    var cycle by remember { mutableStateOf(ReviewRefreshCycle.Idle) }
    val ready by remember { derivedStateOf { cycle == ReviewRefreshCycle.Ready } }
    var offset by remember {mutableFloatStateOf(0f)}
    val visible by remember {derivedStateOf{offset>0f}}
    val armed by remember(distance) {derivedStateOf{offset>=distance}}
    var viewport by remember {mutableFloatStateOf(1f)}
    var rebound by remember {mutableStateOf<Job?>(null)}
    val scope=rememberCoroutineScope()
    val latestRefresh by rememberUpdatedState(onRefresh)
    val busy by rememberUpdatedState(isRefreshing)
    val active by rememberUpdatedState(isRefreshing || cycle != ReviewRefreshCycle.Idle)
    fun settle(target:Float,velocity:Float=0f,then:(()->Unit)?=null) {
        rebound?.cancel()
        rebound=scope.launch {
            val start=offset;val began=withFrameNanos{it}
            do {
                val sample=withFrameNanos{ReviewPullPhysics.sample(start,target,velocity,(it-began)/1e9)}
                offset=sample.position.coerceAtLeast(0f)
            }while(!sample.settled(target))
            offset=target;if(target==0f&&!active)completed=false;then?.invoke()
        }
    }
    fun startGestureRefresh() {
        cycle = cycle.start(busy)
        if (cycle != ReviewRefreshCycle.Running) {
            settle(0f)
            return
        }
        completed = false
        scope.launch {
            try {
                latestRefresh()
                // A callback may start loading in LaunchedEffect, or finish before a busy=true
                // composition is presented. Let that composition/effect commit before observing
                // completion; an immediate/no-op refresh must not leave the header pinned.
                withFrameNanos { }
                yield()
                withFrameNanos { }
                snapshotFlow { busy }.first { !it }
                cycle = cycle.complete()
                completed = true
                lastUpdated = System.currentTimeMillis()
                delay(1000)
            } finally {
                cycle = cycle.dismiss()
                settle(0f)
            }
        }
    }
    val connection=remember(distance) {object:NestedScrollConnection {
        private fun drag(delta:Float):Offset {
            rebound?.cancel();cycle = cycle.interruptReady()
            val change=ReviewPullPhysics.drag(offset,delta,viewport)
            offset=change.offset
            if(!cycle.holdsHeader)completed=false
            return Offset(0f,change.consumed)
        }
        override fun onPreScroll(available:Offset,source:NestedScrollSource):Offset =
            if(source==NestedScrollSource.UserInput&&offset>0&&available.y<0)drag(available.y)else Offset.Zero
        override fun onPostScroll(consumed:Offset,available:Offset,source:NestedScrollSource):Offset =
            if(available.y>0&&source==NestedScrollSource.UserInput)drag(available.y)else Offset.Zero
        override suspend fun onPreFling(available:Velocity):Velocity {
            if(offset<=0f)return Velocity.Zero
            if(cycle == ReviewRefreshCycle.Ready)return Velocity(0f,available.y)
            val released = cycle.release(offset >= distance, busy)
            if(released == ReviewRefreshCycle.Ready && cycle == ReviewRefreshCycle.Idle) {
                cycle = released
                // Original default waits for the ready rebound to reach its trigger before running the task.
                settle(distance,available.y){startGestureRefresh()}
            }else settle(if(cycle.holdsHeader)distance else 0f,available.y)
            return Velocity(0f,available.y)
        }
    }}
    val angle by animateFloatAsState(if(!completed&&!cycle.processing&&armed)-180f else 0f,tween(200,easing=LinearEasing),label="classic refresh arrow")
    val dark=MaterialTheme.colorScheme.surface.let{it.red+it.green+it.blue<1.5f}
    val iconColor=if(dark)Color.White else Color(0xDD000000)
    Box(modifier.clipToBounds().onSizeChanged{viewport=it.height.toFloat().coerceAtLeast(1f)}.nestedScroll(connection)
        .pointerInput(distance) {
            awaitEachGesture {
                awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                if (!active && !ready && offset > 0f && rebound?.isActive == true) {
                    rebound?.cancel()
                    rebound = null
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Final)
                    } while (event.changes.any { it.pressed })
                    if (rebound == null && !active && !ready && offset > 0f) settle(0f)
                }
            }
        }) {
        Box(Modifier.fillMaxSize().graphicsLayer { translationY = offset }, content = content)
        if (visible) Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().drawWithContent{clipRect(bottom=offset){this@drawWithContent.drawContent()}}) {
          Row(Modifier.align(Alignment.TopCenter).height(70.dp)
            .graphicsLayer { translationY = (offset-distance)/2 }, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                AnimatedContent(targetState=if(cycle.processing)"processing" else if(completed)if(failed)"failed"else"success"else"pull",
                    transitionSpec={(fadeIn(tween(300,easing=LinearEasing))+scaleIn(tween(300,easing=LinearEasing),initialScale=0f)) togetherWith (fadeOut(tween(200,easing=LinearEasing))+scaleOut(tween(200,easing=LinearEasing),targetScale=0f))},label="classic refresh status") { mode ->
                    if(mode=="processing")com.green.note.ui.ReviewCircularProgress(Modifier.size(20.dp),strokeWidth=2.dp,color=iconColor)
                    else MaterialGlyph(when(mode){"failed"->"error_outline";"success"->"done";else->"arrow_downward"},Modifier.graphicsLayer{rotationZ=if(mode=="pull")angle else 0f},color=iconColor)
                }
            }
            if(showText) {
            Spacer(Modifier.width(16.dp))
            Column(if(textDimension==null)Modifier else Modifier.width(textDimension),horizontalAlignment = Alignment.Start) {
                Text(when { cycle.processing -> "正在刷新..."; completed -> if (failed) "刷新失败" else "刷新成功"; armed -> "释放立即刷新"; else -> "下拉刷新" }, style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text("最后更新于 ${SimpleDateFormat("H:mm", Locale.getDefault()).format(Date(lastUpdated))}", style = MaterialTheme.typography.bodySmall)
            }
            }
          }
        }
    }
}
