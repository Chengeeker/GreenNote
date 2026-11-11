package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import org.json.JSONObject

internal fun topicCount(raw: String): String = raw.toLongOrNull()?.takeIf { it > 10_000 }?.let { String.format(java.util.Locale.US, "%.1f万", it / 10_000.0) } ?: raw

internal fun topicStats(row: JSONObject): String = listOf(
    row.text("follow_num", "followNum", "follownum").takeIf(String::isNotEmpty)?.let { "${topicCount(it)} 关注" },
    row.text("comment_num", "feed_num", "feedNum", "total_num").takeIf(String::isNotEmpty)?.let { "${topicCount(it)} 讨论" },
).filterNotNull().joinToString(" · ")

internal fun topicCreator(row: JSONObject): Pair<String, String> {
    if (row.text("hidden_creator") in setOf("1", "true")) return "" to ""
    fun JSONObject?.firstString(vararg keys: String): String = keys.firstNotNullOfOrNull { key ->
        (this?.opt(key) as? String)?.trim()?.takeIf(String::isNotEmpty)
    }.orEmpty()

    val creator = row.optJSONObject("creator")
    val userInfo = creator?.optJSONObject("userInfo")
    val name = creator.firstString("displayUsername", "username")
        .ifEmpty { userInfo.firstString("displayUsername", "username") }
        .ifEmpty { row.firstString("creator", "creator_name", "username", "author", "nickName", "nickname") }
    val avatar = creator.firstString("userAvatar", "avatar")
        .ifEmpty { userInfo.firstString("userAvatar", "avatar") }
        .ifEmpty { row.firstString("creator_avatar", "userAvatar", "avatar", "author_avatar") }
    return name to avatar
}

@Composable
internal fun TopicAtmosphere(api: ContentApi, cover: String, background: Color, accent: Color) {
    Box(Modifier.fillMaxSize().background(background)) {
        if (cover.isNotEmpty()) ContentImage(api, cover, null, Modifier.fillMaxWidth().height(240.dp), showDefaultError = false)
        else Canvas(Modifier.fillMaxWidth().height(260.dp).offset(y = (-60).dp)) {
            val overscan = 40.dp.toPx()
            val center = Offset(size.width / 2, size.height * .2f)
            drawRect(Brush.radialGradient(listOf(accent.copy(alpha = .35f), accent.copy(alpha = .12f), Color.Transparent), center, minOf(size.width + overscan * 2, size.height) * .9f), topLeft = Offset(-overscan, 0f), size = androidx.compose.ui.geometry.Size(size.width + overscan * 2, size.height))
        }
        Box(Modifier.fillMaxWidth().height(250.dp).background(Brush.verticalGradient(0f to background.copy(alpha = .3f), .5f to background.copy(alpha = .7f), 1f to background)))
    }
}

@Composable
internal fun TopicLogo(api: ContentApi, logo: String, initialImage: String, title: String, accent: Color, onOpen: (String) -> Unit) {
    var failed by remember(logo, initialImage) { mutableIntStateOf(0) }
    val fallback = initialImage.takeIf { it.isNotEmpty() && it != logo }.orEmpty()
    val url = if (failed == 0) logo else if (failed == 1) fallback else ""
    Box(Modifier.size(62.dp).clip(RoundedCornerShape(16.dp)).clickable(enabled = logo.isNotEmpty()) { onOpen(logo) }, contentAlignment = Alignment.Center) {
        if (url.isNotEmpty()) ContentImage(api, url, null, Modifier.fillMaxSize(), heroCornerRadius = 16.dp, onError = { failed++ })
        else Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(accent, accent.copy(alpha = .7f)))), contentAlignment = Alignment.Center) {
            Text(communityTextLimit(title.ifEmpty { "#" }, 1).text, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
    }
}

@Composable
private fun TopicMiniAvatar(api: ContentApi, color: Color, letter: String, url: String, background: Color, modifier: Modifier = Modifier) {
    var failed by remember(url) { mutableStateOf(false) }
    Box(modifier.size(18.dp).clip(CircleShape).background(color).border(1.5.dp, background, CircleShape).padding(1.5.dp), contentAlignment = Alignment.Center) {
        if (url.isNotEmpty() && !failed) ContentImage(api, url, null, Modifier.fillMaxSize(), heroCornerRadius = 9.dp, onError = { failed = true })
        else Text(letter, fontSize = 8.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}

@Composable
internal fun TopicCreatorRow(api: ContentApi, row: JSONObject, background: Color) {
    val (name, avatar) = remember(row) { topicCreator(row) }
    val followers = topicCount(row.text("follow_num", "followNum", "follownum", "follownum_txt")).ifEmpty { "—" }
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (name.isNotEmpty()) TopicMiniAvatar(api, Color(0xFF00B075), communityTextLimit(name, 1).text, avatar, background)
        else Box(Modifier.width(44.dp).height(18.dp)) { listOf(Color(0xFFFF5722) to "C", Color(0xFF00B075) to "K", Color(0xFF2196F3) to "A").forEachIndexed { index, item -> TopicMiniAvatar(api, item.first, item.second, "", background, Modifier.offset(x = (12 * index).dp)) } }
        Spacer(Modifier.width(6.dp))
        Text(if (name.isNotEmpty()) "$name 创建 | ${followers}关注" else "${followers}关注", fontSize = 12.sp, color = Color.White.copy(alpha = .7f))
        MaterialGlyph("chevron_right_rounded", size = 14.dp, color = Color.White.copy(alpha = .55f))
    }
}

@Composable
internal fun TopicScoreBar(fraction: Float, modifier: Modifier = Modifier) {
    Box(modifier.height(4.dp).clip(RoundedCornerShape(2.dp)).background(Color.White.copy(alpha = .12f))) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).fillMaxHeight().background(Color(0xFFFFB300)))
    }
}

@Composable
internal fun TopicFollowButton(following: Boolean, busy: Boolean, rated: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(15.dp)
    val foreground = Color.White.copy(alpha = .7f)
    Box(Modifier.height(30.dp).then(if (!following) Modifier.dropShadow(shape, Shadow(6.dp, Color(0xFF00B075).copy(alpha = .35f), offset = DpOffset(0.dp, 2.dp))) else Modifier)
        .clip(shape).background(if (following) Color.White.copy(alpha = .12f) else Color(0xFF00B075))
        .clickable(enabled = !busy, onClick = onClick).padding(horizontal = if (following) 12.dp else 16.dp), contentAlignment = Alignment.Center) {
        if (following) Row(verticalAlignment = Alignment.CenterVertically) { MaterialGlyph("check_rounded", size = 14.dp, color = foreground); Spacer(Modifier.width(4.dp)); Text("已关注", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = foreground) }
        else Text("关注", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}
