package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.green.note.ui.MaterialGlyph
import org.json.JSONObject

internal fun contentEntityType(row: JSONObject) = row.text("entityType", "entity_type").lowercase()
internal fun contentEntityIsFeed(row: JSONObject): Boolean {
    val type = contentEntityType(row)
    val articleTypes = setOf("article", "feedarticle", "feed_article", "dyharticle")
    return (type.contains("feed") && !type.contains("reply")) || type.contains("article") ||
        row.text("entityTemplate", "entity_template").lowercase() in articleTypes ||
        row.text("feedType", "feed_type").lowercase() in articleTypes || type.isEmpty() && row.has("message")
}

internal fun contentEntityId(row: JSONObject): String {
    val type = contentEntityType(row)
    return when {
        type.contains("topic") || type.contains("tag") -> carouselTopicTag(row)
        type.contains("apk") || type.contains("app") || type == "game" -> row.text("packageName", "package_name", "apkname", "apk_name", "id")
        type.contains("collection") -> row.text("id", "collectionId", "collection_id")
        type.contains("user") -> row.text("uid", "id", "entityId")
        // A content object's author uid must not replace its own detail identity.
        type.contains("reply") || type.contains("event") || type.contains("dyh") -> row.text("id", "entityId")
        type.contains("product") || type.contains("rating") -> row.text("id", "productId", "entityId")
        else -> row.text("uid", "id", "packageName", "package_name", "tag", "tagName", "productId", "entityId")
    }
}

internal data class EntityDestination(val type: String, val id: String)

/** Mirrors ApiEntityCard._open after community/headline special cases. */
internal fun contentEntityDestination(row: JSONObject): EntityDestination? {
    val type = contentEntityType(row)
    val id = contentEntityId(row)
    if (contentEntityIsFeed(row) && row.text("id", "feedId", "feed_id").isNotEmpty())
        return EntityDestination("feed", row.text("id", "feedId", "feed_id"))
    if (id.isEmpty()) return null
    return when {
        type.contains("dyh") -> EntityDestination("dyh", id)
        type.contains("event") -> EntityDestination("event", id)
        type.contains("reply") -> EntityDestination("reply_thread", id)
        type.contains("category") -> EntityDestination("raw", id)
        type.contains("user") -> EntityDestination("user", id)
        type.contains("product") || type.contains("rating") -> EntityDestination("product", id)
        type.contains("apk") || type.contains("app") || type == "game" -> EntityDestination("apk", id)
        type.contains("topic") || type.contains("tag") -> EntityDestination("topic", id)
        type.contains("collection") -> EntityDestination("collection", id)
        else -> null
    }
}

internal fun contentGoodsTarget(row: JSONObject) = row.text("goods_url", "goods_buy_url", "url")
internal fun contentTemplateListRoute(row: JSONObject): String {
    if (!row.optBoolean("_composeApiTemplateItem")) return ""
    val type = contentEntityType(row)
    val url = row.text("url")
    if (type.contains("topic") || type.contains("tag") || url.contains("/t/")) return ""
    return url.takeIf { row.text("uid", "id", "productId", "tag").isEmpty() }.orEmpty()
}
internal fun contentEntitySummary(row: JSONObject): String {
    fun stat(label: String, vararg keys: String) = row.text(*keys).takeIf(String::isNotEmpty)?.let { "$it$label" }
    return when (contentEntityType(row)) {
        "user", "contacts" -> listOfNotNull(stat("关注", "follow", "followNum"), stat("粉丝", "fans", "fansNum"))
        "product" -> listOfNotNull(stat("热度", "hotNumTxt", "hot_num_txt", "hot_num"), stat("讨论", "feedCommentNumTxt", "commentnum"))
        "apk" -> listOfNotNull(stat("讨论", "commentnum", "commentNum"), stat("下载", "downCount", "apkDownCount"))
        "topic", "tag" -> listOfNotNull(stat("热度", "hotNumTxt", "hot_num_txt"), stat("讨论", "commentnumTxt", "commentnum"))
        else -> emptyList()
    }.joinToString(" · ")
}

@Composable
private fun EntityPlaceholder(type: String) {
    val icon = when {
        type.contains("user") -> "person_outline_rounded"
        type.contains("apk") || type.contains("app") -> "apps_rounded"
        type.contains("topic") || type.contains("tag") -> "tag_rounded"
        type.contains("product") || type.contains("rating") -> "devices_rounded"
        else -> "article_outlined"
    }
    Box(Modifier.size(54.dp).background(MaterialTheme.colorScheme.secondaryContainer, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) { MaterialGlyph(icon) }
}

@Composable
internal fun ContentEntityRow(api: ContentApi, row: JSONObject, onOpen: (JSONObject) -> Unit) {
    val type = contentEntityType(row)
    val title = row.text("goods_title", "title", "username", "userName", "apkName", "apk_name", "productName", "tag")
    val subtitle = row.text("description", "message", "subTitle", "apkVersion", "brief").ifEmpty { contentEntitySummary(row) }
    val plain = remember(subtitle) { org.jsoup.Jsoup.parseBodyFragment(subtitle).text() }
    val image = row.text("goods_pic", "userAvatar", "avatar", "logo", "icon", "pic", "cover", "tagLogo", "tag_logo", "img").ifEmpty { systemPresetLogo(title).orEmpty() }
    Row(Modifier.fillMaxWidth().clickable(enabled = contentEntityId(row).isNotEmpty() || contentGoodsTarget(row).isNotEmpty()) { onOpen(row) }.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.Top) {
        if (image.isNotEmpty()) CardImage(api, image, Modifier.size(50.dp), radius = 12.dp) { EntityPlaceholder(type) }
        else EntityPlaceholder(type)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(title.ifEmpty { "酷安内容" }, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle.isNotEmpty()) { Spacer(Modifier.height(4.dp)); Text(plain, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis) }
        }
        MaterialGlyph("chevron_right_rounded")
    }
}
