package com.green.note.content

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import com.green.note.ui.ReviewText as Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import org.json.JSONObject

internal val LocalContentVideo = staticCompositionLocalOf<(JSONObject) -> Unit> { {} }

/** Keeps the provider request intact for the player's resolver. */
internal fun feedVideo(row: JSONObject): JSONObject? {
    fun json(value: Any?): JSONObject? = when (value) {
        is JSONObject -> value
        is String -> runCatching { JSONObject(value) }.getOrNull()
        else -> null
    }
    val media = json(row.opt("media_info") ?: row.opt("mediaInfo"))
    var url = row.text("media_url", "video_url")
    var cover = row.text("video_pic", "pic", "cover")
    val rawParams = media?.opt("requestParams") ?: media?.opt("request_params")
    val paramsObject = json(rawParams)
    val provider = if (paramsObject != null && paramsObject.length() > 0) {
        if (paramsObject.has("fromType") || paramsObject.has("0")) paramsObject
        else paramsObject.opt(paramsObject.keys().asSequence().last())
    } else rawParams
    var params = if (provider == null || provider == JSONObject.NULL) "" else provider.toString().trim()
    val parsed = json(params)
    if (parsed?.text("fromType") == "localVideo") { url = parsed.text("0"); params = "" }
    if (url.isEmpty()) url = media?.text("url", "media_url", "stream_url").orEmpty()
    if (cover.isEmpty()) cover = media?.text("cover", "pic", "cover_url").orEmpty()
    if (url.isEmpty()) {
        val extra = row.text("extra_url", "url", "shareUrl")
        if (listOf("video", ".mp4", "weibo.com", "t.cn", "bilibili.com", "b23.tv").any(extra::contains)) url = extra
    }
    if (url.isEmpty()) {
        val expressions = listOf(
            "https?://(?:video\\.weibo\\.com|h5\\.video\\.weibo\\.com|weibo\\.com/\\d+/[A-Za-z0-9]+|weibo\\.com/tv/show/\\d+:\\w+)[\\w\\-.,@?^=%&:/~+#]*",
            "https?://t\\.cn/[A-Za-z0-9]+",
            "https?://(?:(?:www\\.)?bilibili\\.com/video/[A-Za-z0-9]+|b23\\.tv/[A-Za-z0-9]+)[\\w\\-.,@?^=%&:/~+#]*")
        url = expressions.firstNotNullOfOrNull { Regex(it).find(row.text("message"))?.value }.orEmpty()
    }
    if (url.isEmpty() && params.isEmpty()) return null
    if (cover.isEmpty()) cover = feedImages(row).firstOrNull().orEmpty()
    val duration = media?.text("duration", "duration_ms", "video_duration")?.toLongOrNull() ?: 0
    val seconds = if (duration > 1000) duration / 1000 else duration
    val durationText = if (seconds > 0) "%02d:%02d".format(seconds / 60, seconds % 60) else media?.text("duration_string").orEmpty()
    return JSONObject().put("url", url).put("requestParams", params).put("coverUrl", cover)
        .put("title", row.text("message", "title").ifEmpty { "视频播放" }).put("author", row.text("username"))
        .put("feedId", row.text("id")).put("durationText", durationText)
}

@Composable
internal fun FeedVideoPreview(api: ContentApi, video: JSONObject) {
    val open = LocalContentVideo.current
    Box(Modifier.padding(vertical = 8.dp).fillMaxWidth().aspectRatio(16f / 9).clip(RoundedCornerShape(14.dp))
        .background(Color(0xff263238)).clickable { open(video) }, contentAlignment = Alignment.Center) {
        if (video.text("coverUrl").isNotEmpty()) ContentImage(api, video.text("coverUrl"), "视频封面", Modifier.fillMaxSize())
        else MaterialGlyph("videocam_rounded", size = 48.dp, color = Color.White.copy(alpha = .54f))
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .25f)))
        Box(Modifier.size(52.dp).clip(CircleShape).background(Color.Black.copy(alpha = .55f)).border(1.5.dp, Color.White.copy(alpha = .6f), CircleShape), contentAlignment = Alignment.Center) {
            MaterialGlyph("play_arrow_rounded", size = 36.dp, color = Color.White)
        }
        if (video.text("durationText").isNotEmpty()) Text(video.text("durationText"), Modifier.align(Alignment.BottomEnd).padding(10.dp)
            .clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = .72f)).padding(horizontal = 7.dp, vertical = 3.dp),
            color = Color.White, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold)
    }
}
