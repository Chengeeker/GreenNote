package com.green.note.ui

import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.invisibleToUser
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private class RouteEntry(val path: List<String>, initial: Float) {
    val route get() = path.last()
    val progress = Animatable(initial)
}

/** Retain covered pages and their drafts, but stop lifecycle-bound work until revealed. */
@Composable
fun ActivePage(active: Boolean, content: @Composable () -> Unit) {
    val parent = LocalLifecycleOwner.current
    val owner = remember(parent) { object : LifecycleOwner {
        val registry = LifecycleRegistry(this)
        override val lifecycle: Lifecycle = registry
    } }
    DisposableEffect(parent, active) {
        fun update() {
            val state = parent.lifecycle.currentState
            owner.registry.currentState = if (active || state < Lifecycle.State.STARTED) state else Lifecycle.State.CREATED
        }
        val observer = LifecycleEventObserver { _, _ -> update() }
        parent.lifecycle.addObserver(observer); update()
        onDispose { parent.lifecycle.removeObserver(observer) }
    }
    DisposableEffect(owner) { onDispose { owner.registry.currentState = Lifecycle.State.DESTROYED } }
    CompositionLocalProvider(LocalLifecycleOwner provides owner, content = content)
}

@Composable
fun StackedRoutes(routes: List<String>, onBack: () -> Unit, modifier: Modifier = Modifier,
    active: Boolean = true,
    content: @Composable (String) -> Unit,
) {
    val entries = remember { mutableStateListOf<RouteEntry>().apply { routes.indices.forEach { add(RouteEntry(routes.take(it + 1), 1f)) } } }
    val scope = rememberCoroutineScope()
    val direction = if (LocalLayoutDirection.current == LayoutDirection.Ltr) 1f else -1f
    val forward = CubicBezierEasing(.215f, .61f, .355f, 1f)
    val reverse = routeExitEasing
    LaunchedEffect(routes.toList()) {
        routes.indices.forEach { index -> val path = routes.take(index + 1)
            if (entries.none { it.path == path }) entries.add(RouteEntry(path, 0f))
        }
    }
    PredictiveBackHandler(active && routes.isNotEmpty()) { events ->
        val top = entries.lastOrNull { it.path == routes }
        try {
            events.collect { event -> top?.progress?.snapTo(1f - event.progress) }
            onBack()
        } catch (_: CancellationException) {
            scope.launch { top?.progress?.animateTo(1f, tween(240, easing = forward)) }
        }
    }
    Box(modifier.fillMaxSize()) {
        entries.forEachIndexed { position, entry -> key(entry) {
            val retained = retainsRoute(entry.path, routes)
            val foreground = active && entry.path == routes
            LaunchedEffect(retained) {
                entry.progress.animateTo(if (retained) 1f else 0f, tween(if (retained) 240 else 190, easing = if (retained) forward else reverse))
                if (!retained) entries.remove(entry)
            }
            val visible = position == entries.lastIndex || position == entries.lastIndex - 1 && entries.last().progress.value < 1f
            ActivePage(foreground) {
                Surface(Modifier.fillMaxSize()
                    .layout { measurable, constraints -> val measured = measurable.measure(constraints)
                        layout(measured.width, measured.height) { if (visible) measured.place(0, 0) } }
                    .graphicsLayer { translationX = size.width * direction * (1f - entry.progress.value) }
                    .then(if (foreground) Modifier else Modifier.clearAndSetSemantics { invisibleToUser() })) {
                    content(entry.route)
                }
            }
        } }
    }
}

internal fun retainsRoute(path: List<String>, routes: List<String>) = path.isNotEmpty() && routes.take(path.size) == path

// Flutter applies reverseCurve to a controller moving from one to zero.
internal val routeExitEasing: Easing = CubicBezierEasing(.55f, .055f, .675f, .19f).let { curve ->
    Easing { elapsed -> 1f - curve.transform(1f - elapsed) }
}
