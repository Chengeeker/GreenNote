package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
internal fun TopicTabs(titles: List<String>, selected: Int, activity: Boolean, rated: Boolean, onSelect: (Int) -> Unit) {
    val primary = if (activity) Color(0xFF009688) else if (rated) Color(0xFF00B075) else MaterialTheme.colorScheme.primary
    val textMeasurer = rememberTextMeasurer()
    val baseStyle = MaterialTheme.typography.titleSmall
    val labelWidth = if (rated) textMeasurer.measure(AnnotatedString(titles[selected]), baseStyle.copy(fontSize = 16.sp, fontWeight = FontWeight.Bold), softWrap = false).size.width.toFloat() else 0f
    // Flutter Tab is a 46dp centered label, with indicatorWeight reserved underneath.
    val indicatorSpace = if (rated) 3.dp else 2.dp
    val tabHeight = 46.dp + indicatorSpace
    TabRow(selected, Modifier.height(tabHeight), containerColor = Color.Transparent, divider = {}, indicator = { positions ->
        Canvas(Modifier.fillMaxSize()) {
            val tab = positions.getOrNull(selected) ?: return@Canvas
            val width = if (activity) 10.dp.toPx() else if (rated) labelWidth.coerceAtMost((tab.width - 24.dp).toPx().coerceAtLeast(0f)) else tab.width.toPx()
            val height = (if (activity || rated) 3.dp else 2.dp).toPx()
            val left = tab.left.toPx() + (tab.width.toPx() - width) / 2
            val top = size.height - height - if (activity || rated) 2.dp.toPx() else 0f
            if (activity) drawRoundRect(primary, Offset(left, top), Size(width, height), CornerRadius(2.dp.toPx()))
            else if (rated) drawPath(Path().apply { addRoundRect(RoundRect(left, top, left + width, top + height,
                topLeftCornerRadius = CornerRadius(height), topRightCornerRadius = CornerRadius(height))) }, primary)
            else drawRect(primary, Offset(left, top), Size(width, height))
        }
    }) {
        titles.forEachIndexed { index, title ->
            val active = selected == index
            Tab(active, com.green.note.ui.rememberHapticClick { onSelect(index) }, modifier = Modifier.height(tabHeight)) {
                Box(Modifier.fillMaxWidth().height(46.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                    TopicTabLabel(title, baseStyle.copy(
                        fontSize = if (activity && active) 18.sp else if (rated && active) 16.sp else 15.sp,
                        fontWeight = if (activity && active) FontWeight.Medium else if (rated && active) FontWeight.Bold else if (rated) FontWeight.Normal else if (active) com.green.note.ui.adjustedWeight(600) else com.green.note.ui.adjustedWeight(400),
                        color = if (active) primary else if (activity) Color(0xFFBBBBBB) else if (rated) Color.White.copy(alpha = .7f) else MaterialTheme.colorScheme.onSurfaceVariant))
                }
                Spacer(Modifier.height(indicatorSpace))
            }
        }
    }
}

/** Flutter Tab's softWrap:false/overflow:fade; long labels must never become extra rows. */
@Composable
private fun TopicTabLabel(title: String, style: TextStyle) {
    var overflowWidth by remember(title, style) { mutableStateOf(false) }
    var overflowHeight by remember(title, style) { mutableStateOf(false) }
    val measurer = rememberTextMeasurer()
    val fade = measurer.measure("\u2026", style).size
    Text(title, style = style, softWrap = false, maxLines = 1, overflow = TextOverflow.Clip,
        onTextLayout = { overflowWidth = it.didOverflowWidth; overflowHeight = it.didOverflowHeight },
        modifier = Modifier.graphicsLayer { compositingStrategy = if (overflowWidth || overflowHeight) CompositingStrategy.Offscreen else CompositingStrategy.Auto }
            .drawWithContent {
                drawContent()
                if (overflowWidth) drawRect(Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), size.width - fade.width, size.width), blendMode = BlendMode.DstIn)
                else if (overflowHeight) drawRect(Brush.verticalGradient(listOf(Color.Black, Color.Transparent), size.height - fade.height / 2f, size.height), blendMode = BlendMode.DstIn)
            })
}
