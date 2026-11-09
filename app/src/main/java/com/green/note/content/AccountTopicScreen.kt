package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import org.json.JSONObject

internal fun accountCount(row: JSONObject, vararg keys: String, compact: Boolean = true): String {
    val raw = row.text(*keys).replace(Regex("(条动态|讨论)$"), "").trim()
    val value = raw.toDoubleOrNull()
    return if (compact && value != null && value >= 10_000) String.format(java.util.Locale.US, "%.1f万", value / 10_000) else raw
}

@Composable
internal fun AccountTopicScreen(api: ContentApi, followed: Boolean, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit, onBack: () -> Unit) {
    val repo = remember(api) { ContentRepository(api) }
    val state = remember(api, followed) { ContentListState { page, first, last -> repo.page(contentRequest(if (followed) "/v6/topic/myFollowTopicList" else "/v6/user/recentHistoryList"), page, first, last).let { result -> result.copy(rows = result.rows.filter { it.text("title", "username", "userName", "name", "productName", "apkName", "tag", "tagName").isNotEmpty() }) } } }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val panel = if (dark) Color(0xFF1E1E1E) else MaterialTheme.colorScheme.surface
    Column(Modifier.fillMaxSize().background(if (dark) Color(0xFF101010) else MaterialTheme.colorScheme.surfaceContainerLow)) {
        ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).background(panel), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(16.dp)); Text(if (followed) "我关注的话题" else "我的常去", fontSize = 18.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
        }
        ContentList(api, state, onOpen, onUser, onLink, { _, _, _ -> }, {}, {},
            modifier = Modifier.padding(start = 8.dp, top = 8.dp, end = 8.dp).clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)).background(panel), contentPadding = PaddingValues(bottom = 24.dp),
            itemContent = { AccountTopicRow(api, it, followed, onOpen, onLink) })
    }
}

@Composable
private fun AccountTopicRow(api: ContentApi, row: JSONObject, followed: Boolean, onOpen: (JSONObject) -> Unit, onLink: (String) -> Unit) {
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val foreground = if (dark) Color(0xFFCCCCCC) else MaterialTheme.colorScheme.onSurface
    val secondary = if (dark) Color(0xFFB8B8B8) else MaterialTheme.colorScheme.onSurfaceVariant
    val title = row.text("title", "username", "userName", "name", "productName", "apkName", "tag", "tagName")
    val category = accountCategory(row)
    val logo = row.text("logo", "userAvatar", "avatar", "icon", "pic", "cover")
    var imageFailed by remember(logo) { mutableStateOf(false) }
    val size = if (followed) 56.dp else 48.dp; val radius = if (followed) 12.dp else 8.dp
    val count = accountCount(row, "commentnum_txt", "commentNumTxt", "commentnumTxt", "comment_num_txt", "feedNumTxt", "feed_num_txt", "feednum_txt", "commentnum", "comment_num", "feednum", "feed_num", "feedNum", "feeds", "feed")
    val heat = accountCount(row, "hot_num_txt", "hotNumTxt", "hot_num", "hotNum")
    val stats = if (followed) listOfNotNull(heat.takeIf(String::isNotEmpty)?.let { "${it}热度" }, count.takeIf(String::isNotEmpty)?.let { "${it}讨论" }).joinToString(" ") else {
        val follow = accountCount(row, "follownum", "follow_num", "followNum", "follow", "follownum_txt", "followNumTxt", compact = false)
        val visits = if (category == "用户") accountCount(row, "fans", "fansnum", "fans_num", "fansNum", "fansnum_txt", "fansNumTxt", compact = false)
            else accountCount(row, "commentnum", "comment_num", "feed_num", "feedNum", "commentnum_txt", "feedCommentNumTxt", compact = false)
        listOfNotNull(follow.takeIf(String::isNotEmpty)?.let { "${it}关注" }, visits.takeIf(String::isNotEmpty)?.let { "$it${if (category == "用户") "粉丝" else "讨论"}" }).joinToString(" ")
    }
    val score = ratingScore(row)
    Row(Modifier.fillMaxWidth().clickable {
        if (row.text("url").isNotEmpty()) onLink(row.text("url")) else {
            val type = if (followed) "topic" else when (category) { "话题" -> "topic"; "用户" -> "user"; "数码" -> "product"; "应用" -> "apk"; else -> row.text("entityType") }
            onOpen(JSONObject(row.toString()).put("entityType", type).put("title", title).apply { if (text("id").isEmpty()) put("id", text("uid", "entityId", "productId", "packageName")) })
        }
    }.padding(horizontal = 16.dp, vertical = if (followed) 8.dp else 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(size).clip(RoundedCornerShape(radius)), contentAlignment = Alignment.Center) {
            if (logo.isNotEmpty() && !imageFailed) ContentImage(api, logo, null, Modifier.fillMaxSize(), scale = if (category == "数码") ContentScale.Fit else ContentScale.Crop, heroCornerRadius = radius, onError = { imageFailed = true })
            else MaterialGlyph("image_outlined", color = secondary)
        }
        Spacer(Modifier.width(if (followed) 12.dp else 8.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!followed && category.isNotEmpty()) { Text(category, Modifier.border(.5.dp, Color(0xFF32988E), RoundedCornerShape(2.dp)).padding(horizontal = 3.dp, vertical = 1.dp), color = Color(0xFF32988E), fontSize = 10.sp, lineHeight = 12.sp); Spacer(Modifier.width(4.dp)) }
                Text(title, Modifier.weight(1f), fontSize = 16.sp, lineHeight = 20.8.sp, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (stats.isNotEmpty()) { Spacer(Modifier.height(5.dp)); Row(verticalAlignment = Alignment.CenterVertically) { if (followed && heat.isNotEmpty()) { MaterialGlyph("local_fire_department_outlined", size = 12.dp, color = Color(0xFFF44336)); Spacer(Modifier.width(2.dp)) }; Text(stats, Modifier.weight(1f), fontSize = if (followed) 12.sp else 14.sp, lineHeight = if (followed) 15.6.sp else 18.2.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = secondary) } }
        }
        Spacer(Modifier.width(6.dp))
        if (followed && score > 0 && score <= 10) Column(Modifier.width(76.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(String.format(java.util.Locale.US, "%.1f", score), fontSize = 23.sp, lineHeight = 25.3.sp, color = foreground); Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) { repeat(5) { star -> Box(Modifier.size(10.5.dp).clip(RoundedCornerShape(1.5.dp)).background(Color(0xFF777777)), contentAlignment = Alignment.Center) { Box(Modifier.fillMaxHeight().fillMaxWidth((score / 2 - star).toFloat().coerceIn(0f, 1f)).align(Alignment.CenterStart).background(Color(0xFFD99F18))); MaterialGlyph("star", size = 8.5.dp, color = Color.White) } } }
        } else MaterialGlyph("chevron_right_rounded", size = 24.dp, color = secondary)
    }
}
