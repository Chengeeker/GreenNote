package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import coil.compose.AsyncImage
import com.green.note.ui.MaterialGlyph

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ComposerMedia(type: String, pictures: List<String>, maximum: Int, enabled: Boolean, onAdd: () -> Unit, onRemove: (String) -> Unit, onReorder: (List<String>) -> Unit) {
    if (type == "article" && pictures.isEmpty()) return
    val feed = type == "feed"; val side = if (feed) 104.dp else if (type == "picture") 96.dp else 106.dp
    val radius = if (feed) 12.dp else 9.dp; val scheme = MaterialTheme.colorScheme
    val dark = scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f
    val bounds = remember { mutableMapOf<String, Rect>() }; var dragged by remember { mutableStateOf<String?>(null) }; var delta by remember { mutableStateOf(Offset.Zero) }; var pointer by remember { mutableStateOf(Offset.Zero) }
    val current by rememberUpdatedState(pictures); val reorder by rememberUpdatedState(onReorder)
    @Composable fun Add() { Box(Modifier.size(side).clip(RoundedCornerShape(radius)).background(if (feed) if (dark) Color(0xFF262629) else Color(0xFFF2F2F4) else if (dark) Color(0xFF2B2B2D) else Color(0xFFF0F0F0)).clickable(enabled = enabled, onClick = onAdd), contentAlignment = Alignment.Center) { MaterialGlyph(if (feed) "add_rounded" else "add", size = if (feed) 38.dp else 46.dp, color = if (feed) if (dark) Color(0xFF6E6E73) else Color(0xFFAAAAAA) else Color(0xFF808080)) } }
    if (pictures.isEmpty()) Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Add(); Spacer(Modifier.width(16.dp)); Text(if (type == "ershou") "添加真实详细的商品照片\n首图会作为动态封面" else "长按图片可拖动排序\n发无关图、色情图将会被禁言", Modifier.weight(1f), fontSize = 13.sp, lineHeight = if (feed) 19.5.sp else 20.8.sp, textAlign = if (feed) TextAlign.Start else TextAlign.Center, color = if (feed) if (dark) Color(0xFF8E8E93) else Color(0xFF666666) else scheme.onSurface)
    } else FlowRow(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(if (feed) 10.dp else 8.dp), verticalArrangement = Arrangement.spacedBy(if (feed) 10.dp else 8.dp)) {
        pictures.forEach { path -> key(path) { Box(Modifier.size(side).onGloballyPositioned { bounds[path] = it.boundsInRoot() }.zIndex(if (dragged == path) 1f else 0f).graphicsLayer { if (dragged == path) { translationX = delta.x; translationY = delta.y } }.then(if (!feed && enabled) Modifier.pointerInput(path) {
            detectDragGesturesAfterLongPress(onDragStart = { local -> dragged = path; delta = Offset.Zero; pointer = (bounds[path]?.topLeft ?: Offset.Zero) + local }, onDragCancel = { dragged = null; delta = Offset.Zero }, onDragEnd = {
                val target = bounds.entries.firstOrNull { it.key != path && it.key in current && it.value.contains(pointer) }?.key
                if (target != null) { val next = current.toMutableList(); val index = next.indexOf(target); next.remove(path); next.add(index.coerceAtMost(next.size), path); reorder(next) }
                dragged = null; delta = Offset.Zero
            }, onDrag = { change, amount -> change.consume(); delta += amount; pointer += amount })
        } else Modifier)) {
            AsyncImage(path, "待发布图片", Modifier.fillMaxSize().clip(RoundedCornerShape(radius)), contentScale = ContentScale.Crop)
            if (dragged != path) Box(Modifier.align(Alignment.TopEnd).padding(if (feed) 4.dp else 0.dp).then(if (feed) Modifier.size(20.dp).clip(CircleShape).background(Color(0x99000000)) else Modifier.size(40.dp)).clickable(enabled = enabled) { onRemove(path) }, contentAlignment = Alignment.Center) { MaterialGlyph(if (feed) "close_rounded" else "cancel", size = if (feed) 14.dp else 24.dp, color = Color.White) }
        } } }
        if (pictures.size < maximum) Add()
    }
}
