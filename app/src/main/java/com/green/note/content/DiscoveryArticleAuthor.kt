package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import com.green.note.ui.tapClickable as clickable
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import org.json.JSONObject

/** discovery_channel_page.dart:1147: articles identify their publisher, then their author. */
@Composable
internal fun DiscoveryArticleAuthor(api: ContentApi, row: JSONObject, source: JSONObject, onLink: (String) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(32.dp).clickable { onLink(source.text("url")) }) {
            DiscoveryImage(api, source.text("logo"), null, Modifier.fillMaxSize().clip(RoundedCornerShape(4.dp)))
        }
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(source.text("title"), Modifier.clickable { onLink(source.text("url")) }, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(2.dp))
            Text(buildAnnotatedString {
                withStyle(SpanStyle(color = MaterialTheme.colorScheme.onSurfaceVariant)) { append("来自 ") }
                withStyle(SpanStyle(color = Color(0xFF009688))) { append(row.text("username")) }
            }, Modifier.clickable { onLink("/u/${row.text("uid")}") }, fontSize = 11.sp)
        }
        Text(row.text("dateline_text"), fontSize = 10.sp, color = Color(0xFF9E9E9E))
        Spacer(Modifier.width(8.dp))
        MaterialGlyph("chevron_right", size = 22.dp)
    }
}
