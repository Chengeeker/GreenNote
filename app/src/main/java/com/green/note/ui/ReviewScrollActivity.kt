package com.green.note.ui

import android.os.Build
import android.view.Window
import android.view.WindowManager
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.foundation.gestures.stopScroll
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

internal class ScrollRequests(private val changed: (Boolean) -> Unit) {
    private val active = mutableSetOf<Any>()
    private val scrolls = mutableMapOf<Any, ScrollableState>()

    fun track(owner: Any, state: ScrollableState) { scrolls[owner] = state }
    fun untrack(owner: Any) {
        scrolls.remove(owner)
        update(owner, false)
    }

    fun stopOnPress(scope: CoroutineScope) {
        scrolls.values.filter { it.isScrollInProgress }.distinct().forEach { state ->
            // Default-priority cancellation leaves a new UserInput drag in control.
            scope.launch(start = CoroutineStart.UNDISPATCHED) { state.stopScroll() }
        }
    }

    fun update(owner: Any, scrolling: Boolean) {
        val previous = active.isNotEmpty()
        if (scrolling) active.add(owner) else active.remove(owner)
        if (previous != active.isNotEmpty()) changed(active.isNotEmpty())
    }
    fun clear() { scrolls.clear(); if (active.isNotEmpty()) { active.clear(); changed(false) } }
}

class ScrollRateController(private val window: Window) {
    private var idleRate: Float? = null
    internal val requests = ScrollRequests(::setRate)
    fun release() { requests.clear(); setRate(false) }
    private fun setRate(active: Boolean) {
        if (Build.VERSION.SDK_INT < 30) return
        try {
            val attributes = WindowManager.LayoutParams().apply { copyFrom(window.attributes) }
            val requested = if (active) {
                val display = window.decorView.display ?: return
                val mode = display.mode
                val rate = display.supportedModes.filter { it.physicalWidth == mode.physicalWidth && it.physicalHeight == mode.physicalHeight }
                    .maxOfOrNull { it.refreshRate } ?: mode.refreshRate
                if (idleRate == null) idleRate = attributes.preferredRefreshRate
                rate
            } else idleRate ?: return
            if (attributes.preferredRefreshRate != requested) { attributes.preferredRefreshRate = requested; window.attributes = attributes }
            if (!active) idleRate = null
        } catch (_: RuntimeException) { /* A display rejecting the hint must not interrupt scrolling. */ }
    }
}

val LocalScrollRateController = staticCompositionLocalOf<ScrollRateController?> { null }

@Composable
fun ReviewScrollActivity(state: ScrollableState) {
    val requests = LocalScrollRateController.current?.requests ?: return
    val owner = remember { Any() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(requests, lifecycle, state) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            requests.track(owner, state)
            try {
                snapshotFlow { state.isScrollInProgress }.collect { requests.update(owner, it) }
            } finally {
                requests.untrack(owner)
            }
        }
    }
}

@Composable
internal fun rememberReviewScrollState() = rememberScrollState().also { ReviewScrollActivity(it) }

@Composable
internal fun rememberReviewLazyListState() = rememberLazyListState().also { ReviewScrollActivity(it) }
