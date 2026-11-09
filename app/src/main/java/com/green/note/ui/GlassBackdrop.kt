package com.green.note.ui

import android.graphics.SurfaceTexture
import android.view.Surface
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.IntSize
import kotlinx.coroutines.channels.Channel
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.ceil
import kotlin.math.floor

internal data class BackdropFrame(val width: Int, val height: Int, val origin: Offset)
internal class GlassCaptureGate {
    // Idle, queued, or queued with a newer scene waiting.
    private val state = AtomicInteger(0)

    fun begin(): Boolean = state.getAndUpdate { if (it == 0) 1 else 2 } == 0
    fun finish(): Boolean = state.getAndSet(0) == 2
}

internal class GlassCaptureTarget(val texture: SurfaceTexture, val surface: Surface) {
    @Volatile var frame: BackdropFrame? = null
    @Volatile var closed = false
    val gate = GlassCaptureGate()
    @Volatile var retryCapture: (() -> Unit)? = null

    fun captureFinished() {
        if (gate.finish() && !closed) retryCapture?.invoke()
    }
}
internal class BackdropRegion {
    var bounds = Rect.Zero
    var target: GlassCaptureTarget? = null
}
internal class GlassBackdropState(val layer: GraphicsLayer) {
    val changed = Channel<Unit>(Channel.CONFLATED)
    val regions = mutableStateListOf<BackdropRegion>()
    var origin = Offset.Zero
    var size = IntSize.Zero
    var contentRevision by mutableIntStateOf(0)
        private set
    var gpuReader by mutableStateOf(false)
    var gpuRevision by mutableIntStateOf(0)
        private set
    fun request() {
        if (gpuReader || regions.isNotEmpty()) changed.trySend(Unit)
    }
    fun updateGpu() { if (gpuReader) gpuRevision++ }
    fun invalidateContent() { contentRevision++ }
}
internal val LocalGlassBackdrop = staticCompositionLocalOf<GlassBackdropState?> { null }

/** Records the body only. Overlay invalidation never schedules another body capture. */
@Composable
fun GlassBackdropHost(modifier: Modifier = Modifier, sourceKey: Any? = null, content: @Composable () -> Unit, overlay: @Composable () -> Unit) {
    val body = rememberGraphicsLayer()
    val state = remember(body) { GlassBackdropState(body) }
    val visibleSource = rememberUpdatedState(sourceKey)
    val density = androidx.compose.ui.platform.LocalDensity.current
    val direction = androidx.compose.ui.platform.LocalLayoutDirection.current
    val scrollObserver=remember { object:NestedScrollConnection {
        override fun onPostScroll(consumed:Offset,available:Offset,source:NestedScrollSource):Offset { state.request();return Offset.Zero }
    } }
    LaunchedEffect(state, body) {
        for (ignored in state.changed) {
            withFrameNanos { }
            state.updateGpu()
            val available = Rect(Offset.Zero, androidx.compose.ui.geometry.Size(state.size.width.toFloat(), state.size.height.toFloat()))
            if (available.isEmpty) continue
            for (region in state.regions.toList()) {
                val target = region.target ?: continue
                if (target.closed || !target.surface.isValid) continue
                val local = region.bounds.translate(-state.origin).inflate(32 * density.density).intersect(available)
                if (local.isEmpty) continue
                val left = floor(local.left); val top = floor(local.top)
                val size = IntSize(ceil(local.right - left).toInt(), ceil(local.bottom - top).toInt())
                if (!target.gate.begin()) continue
                target.retryCapture = { state.changed.trySend(Unit) }
                try {
                    if (target.frame?.width != size.width || target.frame?.height != size.height)
                        target.texture.setDefaultBufferSize(size.width, size.height)
                    val nativeCanvas = target.surface.lockHardwareCanvas()
                    try {
                        nativeCanvas.drawColor(android.graphics.Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR)
                        CanvasDrawScope().draw(density, direction, Canvas(nativeCanvas), androidx.compose.ui.geometry.Size(size.width.toFloat(), size.height.toFloat())) {
                            translate(-left, -top) { drawLayer(body) }
                        }
                        target.frame = BackdropFrame(size.width, size.height, Offset(left, top) + state.origin)
                    } finally {
                        target.surface.unlockCanvasAndPost(nativeCanvas)
                    }
                } catch (failure: RuntimeException) {
                    target.captureFinished()
                    android.util.Log.w("ComposeGlass", "Backdrop capture failed", failure)
                }
            }
        }
    }
    CompositionLocalProvider(LocalGlassBackdrop provides state) {
        Box(modifier) {
            val recording = state.gpuReader || state.regions.isNotEmpty()
            Box(Modifier.then(if (recording) Modifier.graphicsLayer().nestedScroll(scrollObserver) else Modifier)
                .onGloballyPositioned { if(state.origin!=it.positionInRoot() || state.size!=it.size) { state.origin = it.positionInRoot(); state.size = it.size; state.request() } }
                .drawWithCache {
                    // A new tab or a child image may update its own RenderNode without repainting this host.
                    visibleSource.value
                    state.contentRevision
                    onDrawWithContent {
                        if (recording) {
                            body.record { this@onDrawWithContent.drawContent() }
                            drawLayer(body)
                            state.request()
                        } else drawContent()
                    }
                }) { content() }
            overlay()
        }
    }
}

@Composable
internal fun rememberGlassContentInvalidator(): () -> Unit {
    val state = LocalGlassBackdrop.current
    return remember(state) { { state?.invalidateContent(); Unit } }
}

/** For transforms updated on a child RenderNode without a parent draw, e.g. gallery zoom springs. */
@Composable
fun rememberGlassBackdropInvalidator():()->Unit {
    val state=LocalGlassBackdrop.current
    return remember(state) { {state?.request();Unit} }
}

@Composable
internal fun rememberBackdropRegion(): Pair<GlassBackdropState?, BackdropRegion> {
    val state = LocalGlassBackdrop.current
    val region = remember { BackdropRegion() }
    DisposableEffect(state, region) {
        state?.regions?.add(region)
        state?.request()
        onDispose { state?.regions?.remove(region) }
    }
    return state to region
}
