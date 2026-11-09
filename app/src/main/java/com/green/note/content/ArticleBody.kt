package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.network.normalizeNetworkImageUrl
import org.json.JSONArray
import org.json.JSONObject

internal data class ArticlePart(val type: String, val text: String = "", val url: String = "", val caption: String = "")
internal fun articleParts(row: JSONObject): List<ArticlePart> {
    val parts = mutableListOf<ArticlePart>()
    fun appendText(value: String) { if (value.isNotBlank()) parts += ArticlePart("text", value.trim()) }
    fun rich(value: String) {
        if (!value.contains('<') && !value.contains('&')) { appendText(value); return }
        val pending = StringBuilder()
        fun flush() { appendText(pending.toString()); pending.clear() }
        fun visit(node: org.jsoup.nodes.Node) {
            when (node) {
                is org.jsoup.nodes.TextNode -> pending.append(node.wholeText)
                is org.jsoup.nodes.Element -> {
                    if (node.normalName() in setOf("script", "style")) return
                    if (node.normalName() == "img") {
                        val alt = node.attr("alt")
                        if (Regex("^\\[[^\\]]+\\]$").matches(alt)) { pending.append(alt); return }
                        val source = sequenceOf("data-original", "data-src", "src").map(node::attr).firstOrNull(String::isNotEmpty).orEmpty()
                        normalizeNetworkImageUrl(source).takeIf(String::isNotEmpty)?.let { flush(); parts += ArticlePart("image", url = it) }
                    } else if (node.selectFirst("img") == null) {
                        pending.append(node.outerHtml())
                        if (node.normalName() in setOf("p", "div", "figure", "section")) pending.append('\n')
                    } else {
                        node.childNodes().forEach(::visit)
                        if (node.normalName() in setOf("p", "div", "figure", "section")) pending.append('\n')
                    }
                }
            }
        }
        org.jsoup.Jsoup.parseBodyFragment(value).body().childNodes().forEach(::visit)
        flush()
    }
    val raw = row.opt("message_raw_output") ?: row.opt("messageRawOutput")
    val blocks = when (raw) { is JSONArray -> raw; is String -> runCatching { JSONArray(raw) }.getOrNull(); else -> null }
    blocks.objects().forEach { block -> when (block.text("type")) {
        "text" -> rich(block.text("message", "text"))
        "image" -> normalizeNetworkImageUrl(block.text("url")).takeIf(String::isNotEmpty)?.let { parts += ArticlePart("image", url = it, caption = block.text("description")) }
        "shareUrl" -> block.text("url").takeIf(::validWebUrl)?.let { parts += ArticlePart("link", block.text("title").ifEmpty { it }, it) }
    } }
    if (parts.isEmpty() && Regex("<img\\b", RegexOption.IGNORE_CASE).containsMatchIn(row.text("message"))) rich(row.text("message"))
    return parts
}

internal fun articleImageIndices(parts: List<ArticlePart>): List<Int> {
    var current = 0
    return parts.map { if (it.type == "image") current++ else -1 }
}

@Composable
internal fun ArticleBlock(api: ContentApi, row: JSONObject, part: ArticlePart, images: List<String>, imageIndex: Int, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(bottom = 12.dp)) {
        when (part.type) {
            "image" -> {
                var failed by remember(part.url) { mutableStateOf(false) }
                if (failed) Box(Modifier.fillMaxWidth().height(100.dp), contentAlignment = androidx.compose.ui.Alignment.Center) { Text("图片加载失败") }
                else ContentImage(api, part.url, "查看图文正文图片", Modifier.fillMaxWidth().clickable { onGallery(images, imageIndex, row) }, ContentScale.FillWidth, heroCornerRadius = 0.dp, onError = { failed = true })
                if (part.caption.isNotEmpty()) { Spacer(Modifier.height(6.dp)); ContentRichText(part.caption, secondary = true, onLink = onLink, fontSize = 12.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
            }
            "link" -> Surface(color = MaterialTheme.colorScheme.surfaceContainer, shape = RoundedCornerShape(8.dp), modifier = Modifier.clickable { onLink(part.url) }) {
                ContentListTile(headlineContent = { Text(part.text) }, leadingContent = { MaterialGlyph("link") }, horizontalPadding = 12.dp)
            }
            else -> ContentRichText(part.text, onLink = onLink, lineHeight = 26.4.sp, letterSpacing = .15.sp)
        }
    }
}

@Composable
internal fun ArticleBody(api: ContentApi, row: JSONObject, parts: List<ArticlePart>, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit) {
    val images = remember(parts) { parts.filter { it.type == "image" }.map { it.url } }
    val indices = remember(parts) { articleImageIndices(parts) }
    Column(Modifier.fillMaxWidth()) { parts.forEachIndexed { index, part -> ArticleBlock(api, row, part, images, indices[index], onLink, onGallery) } }
}
