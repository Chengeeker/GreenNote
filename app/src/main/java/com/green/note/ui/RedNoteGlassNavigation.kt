@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)

package com.green.note.ui

import com.green.note.ui.ReviewText as Text

import android.graphics.Bitmap
import android.graphics.Path as AndroidPath
import android.view.MotionEvent
import android.view.HapticFeedbackConstants
import android.view.VelocityTracker
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.layout.*
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlin.math.*
import kotlinx.coroutines.*

@Composable
private fun navigationGlassMotion(
    selected: Int,
    touching: Boolean,
    dragging: Boolean,
    target: Float,
    longPressed: Boolean,
): Pair<Float, Float> {
    val held = touching && dragging
    val water = navigationWaterHeld(touching, longPressed)
    val lens by
        animateFloatAsState(
            if (held) target else selected.toFloat(),
            glassSpring(if (held) 150 else 350, if (held) .14f else .15f),
            label = "glass-position",
        )
    val press by
        animateFloatAsState(
            if (water) 1f else 0f,
            navigationWaterSpec(water),
            label = "glass-thickness",
        )
    return lens to press.coerceIn(0f, 1f)
}

@Composable
internal fun RedNoteGlassNavigation(selected: Int, choose: (Int) -> Unit, hasBottomInset: Boolean) {
    val backdrop = LocalGlassBackdrop.current ?: return
    val context = LocalContext.current
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val owner = LocalLifecycleOwner.current
    val labelsLayer = rememberGraphicsLayer()
    val selectedLayer = rememberGraphicsLayer()
    val sceneColor = LocalScaffoldColor.current
    val selectedColor = MaterialTheme.colorScheme.primary
    val unselectedColor =
        if (sceneColor.luminance() < .5f) Color.White
        else MaterialTheme.colorScheme.onSurfaceVariant
    val appFontScale = LocalAppPreferences.current.fontScale
    val scope = rememberCoroutineScope()
    var position by remember { mutableStateOf(Offset.Zero) }
    var dimensions by remember { mutableStateOf(IntSize.Zero) }
    var touching by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }
    var longPressed by remember { mutableStateOf(false) }
    var target by remember { mutableFloatStateOf(selected.toFloat()) }
    val (lens, press) = navigationGlassMotion(selected, touching, dragging, target, longPressed)
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val rootView = LocalView.current
    val onChoose by rememberUpdatedState(choose)
    val haptics by rememberUpdatedState(LocalAppPreferences.current.haptics)
    DisposableEffect(backdrop) {
        backdrop.gpuReader = true
        onDispose { backdrop.gpuReader = false }
    }

    var origin by remember { mutableStateOf(Offset.Zero) }
    var moved by remember { mutableStateOf(false) }
    var startSlot by remember { mutableIntStateOf(0) }
    var vertical by remember { mutableStateOf(false) }
    var velocity by remember { mutableStateOf<VelocityTracker?>(null) }
    var hold by remember { mutableStateOf<Job?>(null) }
    DisposableEffect(Unit) {
        onDispose {
            hold?.cancel()
            velocity?.recycle()
        }
    }
    val systemBottom = if (hasBottomInset) with(density) { WindowInsets.navigationBars.getBottom(density).toDp() } else 0.dp
    FloatingNavigationFrame(systemBottom) { barWidth ->
        val inset = with(density) { 4.dp.toPx() }
        val contentWidth = with(density) { (barWidth - 8.dp).toPx() }
        Box(Modifier.width(barWidth).height(floatingNavigationHeight)) {
            Box(
                Modifier.requiredSize(barWidth + 40.dp, 86.dp)
                    .align(Alignment.Center)
                    .onGloballyPositioned {
                        position = it.positionInRoot()
                        dimensions = it.size
                    }
            ) {
            GlassTabLabels(barWidth, unselectedColor, labelsLayer); GlassTabLabels(barWidth, selectedColor, selectedLayer)
            NavigationGlassMaterial(backdrop.layer, { backdrop.origin }, { backdrop.gpuRevision.toLong() },
                labelsLayer, selectedLayer, lens, press, dark, sceneColor,
                LocalAppPreferences.current.translucentNavigationGlass, navLabels.size, Modifier.fillMaxSize())
        }
            Row(
                Modifier.fillMaxSize().pointerInteropFilter { event ->
                    val x = event.x
                    val y = event.y
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            dragging = false
                            longPressed = false
                            hold?.cancel()
                            velocity?.recycle()
                            velocity = VelocityTracker.obtain().also { it.addMovement(event) }
                            origin = Offset(x, y)
                            moved = false
                            vertical = false
                            touching = true
                            startSlot = navigationSlot(x - inset, contentWidth)
                            target = navigationLensTarget(x - inset, contentWidth)
                            hold = if (startSlot == PublishNavigationSlot) null else scope.launch {
                                delay(220)
                                longPressed = true
                                dragging = true
                                if (haptics) rootView.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            }
                        }
                        MotionEvent.ACTION_MOVE -> {
                            velocity?.addMovement(event)
                            val dx = x - origin.x
                            val dy = y - origin.y
                            if (hypot(dx, dy) > 18 * density.density) {
                                moved = true
                                hold?.cancel()
                                if (abs(dx) > abs(dy)) dragging = true
                                else if (!dragging) vertical = true
                            }
                            if (!vertical) target = navigationLensTarget(x - inset, contentWidth)
                        }
                        MotionEvent.ACTION_UP,
                        MotionEvent.ACTION_CANCEL -> {
                            hold?.cancel()
                            val wasDragging = dragging
                            touching = false
                            velocity?.addMovement(event)
                            velocity?.computeCurrentVelocity(1000)
                            val speed = (velocity?.xVelocity ?: 0f) / density.density
                            if (event.actionMasked == MotionEvent.ACTION_UP && !vertical) {
                                val confirmedTap = !moved && !longPressed
                                val chosen = when {
                                    confirmedTap -> startSlot
                                    wasDragging -> navigationDragChoice(selected, navigationSlot(x - inset, contentWidth), speed)
                                    else -> null
                                }
                                if (chosen != null) {
                                    if (confirmedTap) AppHaptics.light(rootView, haptics)
                                    onChoose(chosen)
                                }
                            }
                            velocity?.recycle()
                            velocity = null
                            dragging = false
                            longPressed = false
                        }
                    }
                    true
                }.padding(horizontal = 4.dp)
            ) {
                navLabels.forEachIndexed { index, label ->
                    Box(
                        Modifier.weight(1f).fillMaxHeight().semantics {
                            contentDescription = label
                            role = if (index == PublishNavigationSlot) Role.Button else Role.Tab
                            if (index != PublishNavigationSlot) this.selected = selected == index
                            onClick {
                                AppHaptics.light(rootView, haptics)
                                onChoose(index)
                                true
                            }
                        },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (index == PublishNavigationSlot) Box(
                            Modifier.size(50.dp, 36.dp).background(
                                Brush.horizontalGradient(listOf(Color(0xFF65C4B9), Color(0xFF13A99F))),
                                RoundedCornerShape(20.dp),
                            ).clearAndSetSemantics {},
                            contentAlignment = Alignment.Center,
                        ) { MaterialGlyph("add_rounded", size = 28.dp, color = Color.White) }
                    }
                }
            }
        }
    }
}

@Composable
private fun GlassTabLabels(
    barWidth: Dp,
    color: Color,
    layer: GraphicsLayer,
) {
    Box(
        Modifier.fillMaxSize()
            .drawWithContent { layer.record { this@drawWithContent.drawContent() } }
            .clearAndSetSemantics {}
    ) {
        Row(Modifier.align(Alignment.Center).size(barWidth, floatingNavigationHeight).padding(horizontal = 4.dp)) {
            navLabels.forEachIndexed { index, name ->
                Column(
                    Modifier.weight(1f).fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    if (index == PublishNavigationSlot) return@Column
                    val icon = remember(index) { liquidIconPath(index) }
                    val paint = remember(color) { android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { this.color = color.toArgb() } }
                    Canvas(Modifier.size(24.dp)) {
                        drawIntoCanvas { canvas ->
                            val native = canvas.nativeCanvas
                            native.save()
                            native.scale(density, density)
                            native.drawPath(icon, paint)
                            native.restore()
                        }
                    }
                    Spacer(Modifier.height(2.dp))
                    Text(
                        name,
                        fontSize = 10.5.sp,
                        lineHeight = 11.55.sp,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
                        color = color,
                    )
                }
            }
        }
    }
}

internal suspend fun GraphicsLayer.readGlassBitmap(): Bitmap {
    val bitmap = toImageBitmap().asAndroidBitmap()
    if (bitmap.config == Bitmap.Config.ARGB_8888) return bitmap
    return try {
        withContext(Dispatchers.Default) {
            checkNotNull(bitmap.copy(Bitmap.Config.ARGB_8888, false))
        }
    } finally {
        bitmap.recycle()
    }
}

private fun liquidIconPath(index:Int)=AndroidPath().apply {
    fillType=AndroidPath.FillType.EVEN_ODD
    when(index) {
        0 -> {moveTo(11f,3.5f);quadTo(12f,2.9f,13f,3.5f);lineTo(20f,7.8f);quadTo(21f,8.4f,21f,9.5f);lineTo(21f,19f);quadTo(21f,21f,19f,21f);lineTo(5f,21f);quadTo(3f,21f,3f,19f);lineTo(3f,9.5f);quadTo(3f,8.4f,4f,7.8f);close();addRoundRect(11f,12f,13f,18f,1f,1f,AndroidPath.Direction.CW)}
        1 -> {addRoundRect(3.5f,3f,20.5f,21f,2f,2f,AndroidPath.Direction.CW);addRoundRect(9f,16f,15f,18f,1f,1f,AndroidPath.Direction.CW)}
        3 -> {addOval(2f,2f,22f,22f,AndroidPath.Direction.CW);moveTo(9f,9f);lineTo(17f,6f);lineTo(15f,15f);lineTo(6f,18f);close();addOval(10.8f,10.8f,13.2f,13.2f,AndroidPath.Direction.CW)}
        4 -> {addOval(7.5f,2f,16.5f,11f,AndroidPath.Direction.CW);moveTo(3f,21f);lineTo(3f,17f);quadTo(3f,13f,12f,13f);quadTo(21f,13f,21f,17f);lineTo(21f,21f);close()}
    }
}
