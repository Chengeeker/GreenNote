package com.green.note.content

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp

/** Keep the original editor viewport fixed while reserving the keyboard's scroll space. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun Modifier.composerKeyboardReveal(): Modifier {
    val requester = remember { BringIntoViewRequester() }
    var focused by remember { mutableStateOf(false) }
    var size by remember { mutableStateOf(IntSize.Zero) }
    val keyboard = WindowInsets.ime.getBottom(LocalDensity.current)
    val padding = with(LocalDensity.current) { 20.dp.toPx() }
    LaunchedEffect(focused, keyboard, size) {
        if (focused && keyboard > 0 && size.height > 0) {
            requester.bringIntoView(Rect(-padding, -padding, size.width + padding, size.height + keyboard + padding))
        }
    }
    return this.bringIntoViewRequester(requester).onFocusChanged { focused = it.isFocused }.onSizeChanged { size = it }
}
