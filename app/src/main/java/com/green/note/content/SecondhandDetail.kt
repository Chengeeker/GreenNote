package com.green.note.content

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewText as Text
import com.green.note.network.await
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import java.net.URI
import java.util.concurrent.TimeUnit

internal data class XianyuDestination(val app: String?, val web: String?)

internal data class SecondhandInfo(
    val title: String,
    val price: String,
    val merchant: Boolean,
    val province: String,
    val city: String,
    val platform: String,
    val xianyu: Boolean,
    val destination: XianyuDestination?,
) {
    val location get() = listOf(province, city).filter(String::isNotEmpty).distinct().joinToString(" ")
}

internal fun secondhandInfo(row: JSONObject): SecondhandInfo? {
    val info = EntityDetails.objectValue(row.opt("ershou_info"))
    if (info.length() == 0) return null
    val platform = info.text("store_type_txt", "link_source")
    val namedXianyu = platform.contains("闲鱼") || info.text("link_source").contains("闲鱼")
    val urls = if (info.text("is_link") in setOf("0", "false")) emptyList() else
        listOf(info.text("link_app_url"), info.text("link_url")).filter(String::isNotEmpty).map(::unwrapShoppingLink)
    val app = urls.firstOrNull { raw ->
        parsedTradeUri(raw)?.let { it.scheme == "fleamarket" && !it.host.isNullOrEmpty() } == true
    }
    val web = urls.firstOrNull { raw ->
        parsedTradeUri(raw)?.let {
            val host = it.host.orEmpty().lowercase()
            it.scheme == "https" && (host == "goofish.com" || host.endsWith(".goofish.com") ||
                host == "2.taobao.com" || namedXianyu && (host == "m.tb.cn" || host == "tb.cn"))
        } == true
    }
    return SecondhandInfo(
        info.text("product_title").ifEmpty { row.text("message_title", "title", "extra_title") },
        info.text("product_price"),
        info.text("deal_type") == "1",
        info.text("province"),
        info.text("city"),
        platform,
        namedXianyu || app != null || web != null,
        if (app != null || web != null) XianyuDestination(app, web) else null,
    )
}

private fun parsedTradeUri(raw: String): URI? = runCatching { URI(raw) }.getOrNull()
    ?.takeIf { it.isAbsolute && it.rawUserInfo == null && it.port == -1 && !it.host.isNullOrEmpty() }

private fun URI.isXianyuShortLink(): Boolean = scheme == "https" && host.lowercase() in setOf("m.tb.cn", "tb.cn")

private val xianyuItemId = Regex("[1-9][0-9]{0,23}")

private fun xianyuItemLink(raw: String): String? {
    val uri = parsedTradeUri(raw) ?: return null
    val host = uri.host.lowercase()
    val itemPage = when (uri.scheme) {
        "https" -> when {
            host == "goofish.com" || host.endsWith(".goofish.com") -> uri.path.trimEnd('/') == "/item"
            host == "2.taobao.com" -> uri.path in setOf("/item", "/item.htm")
            else -> false
        }
        "fleamarket" -> host == "item"
        else -> false
    }
    if (!itemPage) return null
    val query = Uri.parse(raw)
    val ids = (query.getQueryParameters("itemId") + query.getQueryParameters("id")).distinct()
    val id = ids.singleOrNull()?.takeIf(xianyuItemId::matches) ?: return null
    return "fleamarket://item?id=$id"
}

private val xianyuShortLinkClient by lazy {
    OkHttpClient.Builder().followRedirects(false).callTimeout(4, TimeUnit.SECONDS).build()
}
// The short-link landing page exposes its destination as a literal without executing JavaScript.
private val xianyuShortLinkTarget = Regex("""\bvar\s+url\s*=\s*['"]([^'"\r\n]{1,2048})['"]""")

internal suspend fun resolveXianyuItem(destination: XianyuDestination, client: OkHttpClient = xianyuShortLinkClient): String? {
    destination.app?.let { app -> if (parsedTradeUri(app)?.scheme == "fleamarket") return app }
    val web = destination.web ?: return null
    xianyuItemLink(web)?.let { return it }
    return withContext(Dispatchers.IO) {
        withTimeoutOrNull(5_000) {
            var shortLink = web
            repeat(3) {
                val uri = parsedTradeUri(shortLink)?.takeIf { it.isXianyuShortLink() } ?: return@withTimeoutOrNull null
                val request = Request.Builder().url(shortLink)
                    .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36").build()
                val target = try {
                    client.newCall(request).await().use { response ->
                        when {
                            response.isRedirect -> response.header("Location")?.let { runCatching { uri.resolve(it).toString() }.getOrNull() }
                            response.isSuccessful -> xianyuShortLinkTarget.find(response.peekBody(64 * 1024L).string())
                                ?.groupValues?.get(1)?.replace("&amp;", "&")?.replace("\\u0026", "&")
                            else -> null
                        }
                    }
                } catch (_: IOException) {
                    null
                } ?: return@withTimeoutOrNull null
                xianyuItemLink(target)?.let { return@withTimeoutOrNull it }
                shortLink = target
            }
            null
        }
    }
}

internal fun openXianyu(context: Context, target: String): Boolean = try {
    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(target)).addCategory(Intent.CATEGORY_BROWSABLE).setPackage("com.taobao.idlefish"))
    true
} catch (_: ActivityNotFoundException) {
    false
} catch (_: SecurityException) {
    false
}

@Composable
internal fun XianyuMark(size: Dp = 16.dp) {
    Box(Modifier.size(size).background(Color(0xFFFFDA44), RoundedCornerShape(size / 6)),
        contentAlignment = Alignment.Center) {
        Text("闲鱼", color = Color(0xFF28271D), fontSize = (size.value * .38f).sp,
            lineHeight = (size.value * .5f).sp, fontWeight = FontWeight.Black, maxLines = 1)
    }
}

@Composable
internal fun SecondhandMerchantBadge() {
    Text("商家", Modifier.background(Color(0xFFA364F5), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 2.dp),
        color = Color.White, fontSize = 11.sp, lineHeight = 13.sp, maxLines = 1)
}

@Composable
internal fun SecondhandPrice(price: String, size: TextUnit, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.Bottom) {
        if (price.isNotEmpty()) {
            Text("¥", color = Color(0xFFF44336), fontSize = size * .62f, modifier = Modifier.alignByBaseline())
            Text(price, color = Color(0xFFF44336), fontSize = size, fontWeight = FontWeight.Bold,
                maxLines = 1, modifier = Modifier.alignByBaseline())
        }
    }
}

@Composable
internal fun SecondhandDetailBody(api: ContentApi, row: JSONObject, trade: SecondhandInfo, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit) {
    val images = remember(row) { feedImages(row).ifEmpty { listOf(row.text("message_cover", "extra_pic")).filter(String::isNotEmpty) } }
    val colors = MaterialTheme.colorScheme
    val muted = colors.onSurfaceVariant
    if (images.isNotEmpty()) {
        val pager = rememberPagerState { images.size }
        HorizontalPager(pager, Modifier.fillMaxWidth().aspectRatio(4f / 3f)) { index ->
            FeedImageTile(api, images[index], row, index, joined = true, overflow = 0, modifier = Modifier.fillMaxSize(), badgeOnTop = true) {
                onGallery(images, index, row)
            }
        }
        if (images.size > 1) Row(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 5.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally)) {
            repeat(images.size) { index ->
                Box(Modifier.size(6.dp).background(if (index == pager.currentPage) Color(0xFF009688) else muted.copy(alpha = .62f), CircleShape))
            }
        }
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 7.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (trade.merchant) SecondhandMerchantBadge()
            Text(trade.title, Modifier.weight(1f), color = colors.onSurface, fontSize = 19.sp, fontWeight = FontWeight.Medium)
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondhandPrice(trade.price, 28.sp, Modifier.weight(1f))
            if (trade.location.isNotEmpty()) Text(trade.location, color = muted, fontSize = 14.sp)
        }
        val description = row.text("message")
        if (description.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            ContentRichText(description, onLink = onLink, color = colors.onSurface, fontSize = 16.sp, lineHeight = 27.sp)
        }
        if (trade.city.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Row(Modifier.background(colors.onSurface.copy(alpha = .07f), RoundedCornerShape(4.dp)).padding(5.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(Modifier.size(18.dp).background(Color(0xFF58AB63), RoundedCornerShape(4.dp)), contentAlignment = Alignment.Center) {
                    MaterialGlyph("location_on_outlined", size = 16.dp, color = Color.White)
                }
                Text(trade.city, color = muted, fontSize = 12.sp)
            }
        }
        val location = row.text("location", "ip_location", "province").ifEmpty { trade.province }
        if (location.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Text(if (location.startsWith("发布于")) location else "发布于$location", color = muted.copy(alpha = .65f), fontSize = 12.sp)
        }
    }
}
