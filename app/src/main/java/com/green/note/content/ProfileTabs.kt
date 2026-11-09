package com.green.note.content

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import com.green.note.ui.ReviewText as Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
internal fun ProfileTabs(titles: List<String>, selected: Int, background: Color, dark: Boolean, modifier: Modifier = Modifier, onSelect: (Int) -> Unit) {
    val scroll = rememberScrollState()
    val bounds = remember { mutableMapOf<Int, androidx.compose.ui.geometry.Rect>() }
    var viewport by remember { mutableStateOf<androidx.compose.ui.geometry.Rect?>(null) }
    LaunchedEffect(selected, titles) {
        withFrameNanos { }
        val tab = bounds[selected]; val view = viewport
        if (tab != null && view != null) scroll.animateScrollTo((scroll.value + tab.center.x - view.center.x).toInt().coerceIn(0, scroll.maxValue), androidx.compose.animation.core.tween(300))
    }
    Box(modifier.fillMaxWidth().height(48.dp).background(background)) {
        Row(Modifier.fillMaxSize().onGloballyPositioned { viewport = it.boundsInRoot() }.horizontalScroll(scroll).padding(horizontal = 6.dp)) {
            titles.forEachIndexed { index, title ->
                val active = index == selected
                Box(Modifier.onGloballyPositioned { bounds[index] = it.boundsInRoot() }.fillMaxHeight()
                    .widthIn(min = 56.dp).semantics { this.selected = active }
                    .clickable(role = Role.Tab) { onSelect(index) }.padding(horizontal = 11.dp),
                    contentAlignment = Alignment.Center) {
                    val accent = if (dark) darkProfileAccent else Color(0xFF00796B)
                    Text(title, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (active) accent else if (dark) Color(0xFFBBBBBB) else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1, softWrap = false)
                    if (active) Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 5.dp)
                        .size(10.dp, 3.dp).background(accent, RoundedCornerShape(50)))
                }
            }
        }
        HorizontalDivider(Modifier.align(Alignment.BottomCenter), color = if (dark) Color(0xFF28282A) else MaterialTheme.colorScheme.outlineVariant.copy(alpha = .18f))
    }
}
