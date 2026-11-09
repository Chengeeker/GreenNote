package com.green.note.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import com.green.note.ui.ReviewText as Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import kotlinx.coroutines.delay

internal data class ToastMessage(val text: String, val id: Long = System.nanoTime())
class AppToastState {
    fun showSnackbar(message: String) { current = ToastMessage(message) }
    companion object { private var current by mutableStateOf<ToastMessage?>(null)
        internal val message get() = current
        internal fun dismiss(id: Long) { if (current?.id == id) current = null }
    }
}

@Composable
fun AppToastSink(@Suppress("UNUSED_PARAMETER") state: AppToastState, @Suppress("UNUSED_PARAMETER") modifier: Modifier = Modifier) = Unit

@Composable
fun AppToastHost() {
    val message = AppToastState.message ?: return
    val opacity = remember { Animatable(0f) }
    LaunchedEffect(message.id) {
        opacity.snapTo(0f)
        opacity.animateTo(1f, tween(100, easing = CubicBezierEasing(0f, 0f, .58f, 1f)))
        delay(2500)
        opacity.animateTo(0f, tween(100, easing = CubicBezierEasing(.42f, 0f, 1f, 1f)))
        AppToastState.dismiss(message.id)
    }
    val dark = MaterialTheme.colorScheme.background.let { it.red + it.green + it.blue < 1.5f }
    val density = LocalDensity.current
    val bottom = WindowInsets.navigationBars.union(WindowInsets.ime).getBottom(density) + with(density) { 84.dp.roundToPx() }
    Popup(alignment = Alignment.BottomCenter, offset = IntOffset(0, -bottom), properties = PopupProperties(focusable = false, dismissOnBackPress = false, dismissOnClickOutside = false, clippingEnabled = false)) {
        Box(Modifier.padding(horizontal = 24.dp)) {
        Box(Modifier.widthIn(max = 340.dp).alpha(opacity.value).dropShadow(RoundedCornerShape(24.dp),Shadow(radius=16.dp,color=Color.Black.copy(alpha=.3f),offset=DpOffset(0.dp,4.dp)))
            .background(if (dark) Color(0xff2c2d35).copy(alpha = .96f) else Color(0xff1e1e24).copy(alpha = .94f), RoundedCornerShape(24.dp))
            .padding(horizontal = 18.dp, vertical = 10.dp).semantics { liveRegion = LiveRegionMode.Polite }) {
            Text(message.text, color = Color.White, fontSize = 13.5.sp, lineHeight = 16.875.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center)
        }
        }
    }
}
