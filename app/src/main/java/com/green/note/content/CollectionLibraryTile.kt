package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import org.json.JSONObject

@Composable
internal fun CollectionLibraryTile(row: JSONObject, first: Boolean, last: Boolean, onOpen: (JSONObject) -> Unit, grouped: Boolean = true) {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f
    val shape = RoundedCornerShape(topStart = if (first) 16.dp else 0.dp, topEnd = if (first) 16.dp else 0.dp,
        bottomStart = if (last) 16.dp else 0.dp, bottomEnd = if (last) 16.dp else 0.dp)
    val id = row.text("id", "collectionId", "collection_id")
    val privacy = if (row.text("is_open", "isOpen", "status") in setOf("0", "private")) "私密" else "公开"
    val follows = row.text("follow_num", "followNum", "follownum").ifEmpty { "1" }
    val count = row.text("content_num", "contentNum", "item_num", "itemNum", "feed_num", "feednum", "num", "count").ifEmpty { "0" }
    Column(Modifier.fillMaxWidth().then(if (grouped) Modifier.padding(start = 16.dp, end = 16.dp, top = if (first) 12.dp else 0.dp, bottom = if (last) 12.dp else 0.dp)
        .clip(shape).background(if (dark) Color(0xFF1E1E22) else scheme.surfaceContainer) else Modifier)) {
        if (grouped && !first) HorizontalDivider(Modifier.padding(start = 114.dp), thickness = 1.dp, color = if (dark) Color.White.copy(alpha = .06f) else scheme.outlineVariant.copy(alpha = .25f))
        Row(Modifier.fillMaxWidth().clickable(enabled = id.isNotEmpty()) { onOpen(JSONObject(row.toString()).put("entityType", "collection").put("id", id)) }
            .padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(84.dp, 64.dp).dropShadow(RoundedCornerShape(14.dp), Shadow(radius = 8.dp, color = Color(0xFF20D4A0).copy(alpha = .25f), offset = DpOffset(0.dp, 3.dp)))
                .background(Brush.verticalGradient(listOf(Color(0xFF1FD5D2), Color(0xFF20D4A0))), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                MaterialGlyph("folder_outlined", size = 36.dp, color = Color.White)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(row.text("title", "name").ifEmpty { "收藏单" }, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    fontSize = 16.sp, fontWeight = FontWeight.Bold, color = if (dark) Color.White else Color.Black.copy(alpha = .87f))
                Spacer(Modifier.height(5.dp))
                Text("$privacy  ${follows}人关注  ${count}个内容", maxLines = 1, overflow = TextOverflow.Ellipsis,
                    fontSize = 13.sp, color = if (dark) Color.White.copy(alpha = .54f) else Color.Black.copy(alpha = .54f))
            }
            Spacer(Modifier.width(8.dp))
            MaterialGlyph("chevron_right_rounded", size = 22.dp, color = if (dark) Color.White.copy(alpha = .38f) else Color.Black.copy(alpha = .38f))
        }
    }
}
