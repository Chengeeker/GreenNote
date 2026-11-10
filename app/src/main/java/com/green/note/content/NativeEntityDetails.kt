package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.Intent
import android.content.Context
import android.annotation.SuppressLint
import android.net.Uri
import android.text.Html
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.selection.selectableGroup
import com.green.note.ui.tapToggleable as toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import com.green.note.ui.ReviewRefreshBox
import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.fractionalVerticalPadding
import com.green.note.ui.GlassBackdropHost
import com.green.note.ui.GlassSurface
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.FormBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.TimeUnit
import org.jsoup.Jsoup
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import android.graphics.drawable.BitmapDrawable
import kotlin.math.roundToInt

@Composable
internal fun NativeEntityDetailScreen(api: ContentApi, type: String, id: String, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onBack: () -> Unit = {},
    onOpen: (JSONObject) -> Unit = {}, onLike: (JSONObject) -> Unit = {}, onMore: (JSONObject) -> Unit = {},
    preparedApp: PreparedAppDetail? = null, onCompose: () -> Unit = {}) {
    if (type == "product") NativeProductDetail(api, id, onLink, onGallery, onBack, onOpen, onLike, onMore, onCompose)
    else NativeAppDetail(api, id, onLink, onGallery, onBack, onOpen, onLike, onMore, preparedApp)
}

internal data class PreparedAppDetail(val data: JSONObject, val palette: Pair<Color, Color>? = null, val icon: ImageBitmap? = null)

private fun appDetailLogo(data: JSONObject) = data.text("apkRomIcon", "logo", "icon", "pic")

private suspend fun fetchAppDetail(api: ContentApi, id: String): JSONObject =
    EntityDetails.objectValue(api.request("/v6/apk/detail", query = mapOf("id" to id)).opt("data"))
        .also { check(it.length() > 0) { "应用详情数据为空" } }

internal suspend fun prepareAppDetail(context: Context, api: ContentApi, id: String): PreparedAppDetail {
    val owner = api.imageCacheScope()
    val data = fetchAppDetail(api, id)
    val url = com.green.note.network.normalizeNetworkImageUrl(appDetailLogo(data))
    val prepared = if (url.isEmpty()) null else withTimeoutOrNull(900) {
        try {
            val image = context.imageLoader.execute(ImageRequest.Builder(context).data(url).size(coil.size.Size.ORIGINAL)
                .allowHardware(false).memoryCacheKey("$owner|palette-original-format|$url")
                .diskCacheKey("$owner|palette-original-format|$url")
                .apply { api.imageHeaders(url).forEach { (key, value) -> addHeader(key, value) } }.build()) as? SuccessResult
            val bitmap = (image?.drawable as? BitmapDrawable)?.bitmap ?: return@withTimeoutOrNull null
            withContext(Dispatchers.Default) {
                val colors = appIconPalette(sampleAppIconPixels(bitmap))
                val scale = minOf(1.0, 256.0 / maxOf(bitmap.width, bitmap.height))
                val icon = android.graphics.Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).roundToInt().coerceAtLeast(1),
                    (bitmap.height * scale).roundToInt().coerceAtLeast(1), true)
                PreparedAppDetail(data, colors, icon.asImageBitmap())
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }
    check(owner == api.imageCacheScope()) { "账号已变更，请重新打开应用详情" }
    return prepared ?: PreparedAppDetail(data)
}

internal object EntityDetails {
    fun objectValue(value: Any?): JSONObject = when (value) {
        is JSONObject -> value
        is String -> runCatching { JSONObject(value) }.getOrDefault(JSONObject())
        is JSONArray -> value.optJSONObject(0) ?: JSONObject()
        else -> JSONObject()
    }
    fun values(data: JSONObject, vararg keys: String): List<String> {
        val raw = keys.firstNotNullOfOrNull { data.opt(it)?.takeIf { value -> value != JSONObject.NULL && value.toString().isNotBlank() } } ?: return emptyList()
        val list = if (raw is JSONArray) raw else runCatching { JSONArray(raw.toString()) }.getOrNull()
        return if (list != null) (0 until list.length()).mapNotNull { index -> when (val row = list.opt(index)) {
            is JSONObject -> row.text("title", "name", "tag", "url", "pic", "image").takeIf(String::isNotBlank)
            null, JSONObject.NULL -> null
            else -> row.toString().takeIf(String::isNotBlank)
        } } else raw.toString().split(Regex("[,，、;；|\\n]")).map(String::trim).filter(String::isNotBlank)
    }
    fun plain(data: JSONObject, vararg keys: String): String = Html.fromHtml(data.text(*keys).replace(Regex("<br\\s*/?>|</(p|div|li)>", RegexOption.IGNORE_CASE), "<br>"), Html.FROM_HTML_MODE_LEGACY).toString().trim()
    fun count(raw: String): String {
        val count = raw.replace(",", "").toDoubleOrNull() ?: return raw
        if (count < 10000) return raw
        return if (count >= 100000000 || (count / 10000).roundToInt() >= 10000) String.format(Locale.ROOT, "%.1f", count / 100000000).removeSuffix(".0") + "亿" else "${(count / 10000).roundToInt()}万"
    }
    fun update(raw: String, now: Long = System.currentTimeMillis()): String {
        val value = raw.toLongOrNull()?.takeIf { it > 0 } ?: return raw
        val days = (now - if (value > 100000000000) value else value * 1000) / 86400000
        return when { days <= 0 -> "今天"; days < 30 -> "${days}天前"; days < 365 -> "${days / 30}个月前"; else -> "${days / 365}年前" }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NativeAppDetail(api: ContentApi, id: String, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit,
    onBack: () -> Unit, onOpen: (JSONObject) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit,
    initial: PreparedAppDetail?) {
    var detail by remember(api, id) { mutableStateOf(initial) }
    val data = detail?.data
    val context = LocalContext.current
    val pageState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val photoStatusBars = LocalPhotoStatusBars.current
    val statusOwner = remember { Any() }
    val ownsStatusBars = detail?.palette != null && pageState.isAtLeast(Lifecycle.State.STARTED)
    DisposableEffect(photoStatusBars, statusOwner, ownsStatusBars) {
        if (ownsStatusBars) photoStatusBars?.put(statusOwner, Unit)
        onDispose { if (ownsStatusBars) photoStatusBars?.remove(statusOwner) }
    }
    var error by remember(id) { mutableStateOf<String?>(null) }
    var related by remember(id) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var relatedError by remember(id) { mutableStateOf<String?>(null) }
    var relatedLoading by remember(id) { mutableStateOf(false) }
    var loading by remember(id) { mutableStateOf(initial == null) }
    var tab by remember(id) { mutableStateOf("discussion") }
    var sort by remember(id) { mutableStateOf("lastupdate_desc") }
    var attempt by remember(id) { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val scroll = rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    val repo = remember(api) { ContentRepository(api) }
    val packageName = data?.text("apkname", "packageName", "package_name", "apk_name", "pn").orEmpty().ifEmpty { id }
    suspend fun loadRelated() {
        val packageName = detail?.data?.text("apkname", "packageName", "package_name", "apk_name", "pn").orEmpty().ifEmpty { id }
        relatedLoading = true
        try { related = repo.page(ContentRequest("/v6/apk/search", mapOf("q" to packageName, "apkType" to "0", "searchType" to "related")), 1).rows.take(8); relatedError = null }
        catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { relatedError = failure.message ?: "加载失败" }
        finally { relatedLoading = false }
    }
    LaunchedEffect(api, id, attempt) {
        loading = true; error = null
        try {
            val old = detail
            if (old == null) detail = prepareAppDetail(context, api, id)
            else if (attempt > 0) {
                val refreshed = fetchAppDetail(api, packageName)
                detail = old.copy(data = refreshed, icon = old.icon.takeIf { appDetailLogo(refreshed) == appDetailLogo(old.data) })
            }
            loadRelated()
        }
        catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message }
        finally { loading = false }
    }
    val list = remember(api, packageName, tab) { ContentListState() }
    val listRequest = ContentRequest(
        if (tab == "discussion") "/v6/page/dataList" else "/v6/apk/commentList",
        mapOf("id" to packageName, (if (tab == "discussion") "sort" else "listType") to sort) +
            if (tab == "discussion") mapOf("url" to "#/feed/apkCommentList") else emptyMap())
    LaunchedEffect(list, listRequest, data != null) {
        if (data != null && tab != "details") list.bind(listRequest) { page, first, last -> repo.page(listRequest, page, first, last) }
    }
    LaunchedEffect(list, scroll, tab) { snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect {
        if (tab != "details" && list.rows.isNotEmpty() && it >= list.rows.size - 1 && list.error == null) list.load()
    } }
    val discussionBackground = if (MaterialTheme.colorScheme.surface.luminance() < .5f) Color(0xff09090b) else MaterialTheme.colorScheme.surface
    val accent = detail?.palette?.first ?: discussionBackground
    val onAccent = detail?.palette?.second ?: MaterialTheme.colorScheme.onSurface
    val card = if (detail?.palette != null) lerp(accent, Color.Black, .16f) else MaterialTheme.colorScheme.surfaceContainerHigh
    Column(Modifier.fillMaxSize().background(discussionBackground)) {
        Row(Modifier.fillMaxWidth().background(accent).statusBarsPadding().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick = onBack, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back", color = onAccent) }; Spacer(Modifier.width(16.dp))
            Text(data?.text("title", "shorttitle", "name").orEmpty().ifEmpty { "应用详情" }, color = onAccent, fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        ReviewRefreshBox(isRefreshing = loading && attempt > 0 && data != null || list.refreshing, failed = error != null || list.error != null, onRefresh = { attempt++; scope.launch { if (tab != "details") list.load(true) } }, modifier = Modifier.weight(1f)) {
            LazyColumn(state = scroll, contentPadding = PaddingValues(bottom = 24.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()), modifier = Modifier.fillMaxSize()) {
                if (data == null) item { LoadingFailure(loading, error, modifier = Modifier.fillParentMaxHeight()) { attempt++ } }
                data?.let { value ->
                    item { AppDetailHeader(api, value, detail?.icon, related, relatedError, relatedLoading, accent, onAccent, card, onGallery, onOpen) { scope.launch { loadRelated() } } }
                    item {
                        Row(Modifier.fillMaxWidth()) { listOf("details" to "详情", "discussion" to "讨论", "reviews" to "点评").forEach { (key, title) ->
                            Column(Modifier.weight(1f).height(48.dp).clickable { tab = key; if (key == "details") scope.launch { scroll.animateScrollToItem(0) } }, horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { Text(title, color = if (key == tab) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = if (key == tab) FontWeight.SemiBold else FontWeight.Normal) }
                                Box(Modifier.width(24.dp).height(2.dp).background(if (key == tab) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(2.dp)))
                            }
                        } }
                    }
                    if (tab != "details") {
                        item { Row(Modifier.fillMaxWidth().padding(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("排序规则", Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                            listOf("lastupdate_desc" to "默认", "dateline_desc" to "最新", "popular" to "热度").forEach { (key, title) -> Spacer(Modifier.width(6.dp)); com.green.note.ui.ReviewChoiceChip(sort == key,showCheckmark=false,compact=true, onClick = { sort = key }, label = { Text(title) }, enabled = !list.busy) }
                        } }
                        items(list.rows, key = ::entityKey) { row -> EntityRow(api, row, onOpen, { onLink("/u/$it") }, onLink, onGallery, onLike, onMore) }
                        item(key = "app-discussion-status") {
                            if (list.rows.isEmpty()) {
                                val remaining = with(androidx.compose.ui.platform.LocalDensity.current) {
                                    val layout = scroll.layoutInfo
                                    (layout.viewportEndOffset - (layout.visibleItemsInfo.firstOrNull { it.key == "app-discussion-status" }?.offset ?: 0)).coerceAtLeast(0).toDp()
                                }
                                LoadingFailure(list.busy, list.error, modifier = Modifier.heightIn(min = remaining)) { scope.launch { list.load(true) } }
                            } else when {
                                list.busy -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
                                list.error != null -> com.green.note.ui.ReviewTextButton(onClick = { scope.launch { list.load() } }) { Text("加载失败，点击重试：${list.error}") }
                                !list.more -> Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { Text("已经到底了") }
                                else -> Spacer(Modifier.height(1.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingFailure(loading: Boolean, error: String?, empty: String = "暂无内容", modifier: Modifier = Modifier, retry: () -> Unit) {
    Column(modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        when { loading -> com.green.note.ui.ReviewCircularProgress(); error != null -> { Text(error); com.green.note.ui.ReviewTextButton(onClick = retry) { Text("重试") } }; empty.isNotEmpty() -> Text(empty) }
    }
}

@Composable
private fun AppDetailHeader(api: ContentApi, data: JSONObject, icon: ImageBitmap?, related: List<JSONObject>, relatedError: String?, relatedLoading: Boolean, accent: Color, foreground: Color, card: Color,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onOpen: (JSONObject) -> Unit, retryRelated: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(accent)) {
        Row(Modifier.padding(start = 16.dp, top = 18.dp, end = 16.dp, bottom = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            val iconModifier = Modifier.size(80.dp).clip(RoundedCornerShape(18.dp))
            if (icon != null) Image(icon, null, iconModifier, contentScale = ContentScale.Crop)
            else EntityImage(api, appDetailLogo(data), iconModifier, showLoading = false) {
                Box(Modifier.fillMaxSize().background(card), contentAlignment = Alignment.Center) { MaterialGlyph("apps_rounded", size = 42.dp, color = foreground) }
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(data.text("title", "shorttitle", "name"), color = foreground, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(7.dp))
                val version = data.text("apkversionname", "versionName", "version")
                val code = data.text("apkversioncode", "versionCode")
                val size = data.text("apksize", "apkSize", "size")
                Text(listOf(version, code.takeIf(String::isNotEmpty)?.let { "版本号 $it" }.orEmpty(), size).filter(String::isNotBlank).joinToString("  "), color = foreground.copy(alpha = .78f), style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                EntityDetails.update(data.text("lastupdate", "lastUpdate", "update_time")).takeIf(String::isNotEmpty)?.let { Spacer(Modifier.height(4.dp)); Text("更新于 $it", color = foreground.copy(alpha = .78f), style = MaterialTheme.typography.bodySmall) }
            }
        }
        NativeAppDownload(api, data, Modifier.fillMaxWidth().padding(horizontal = 16.dp))
        val metrics = listOf("下载" to EntityDetails.count(data.text("downnum", "downCount", "down_count")), "热度" to data.text("hot_num", "hotNum", "hot"), "评论" to data.text("commentnum", "commentCount", "comment_count"), "关注" to data.text("follow", "follownum", "follow_num")).filter { it.second.isNotEmpty() }
        if (metrics.isNotEmpty()) Row(Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp).fillMaxWidth().background(card, RoundedCornerShape(14.dp)).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            metrics.forEachIndexed { index, (name, value) ->
                if (index > 0) VerticalDivider(Modifier.height(34.dp), color = foreground.copy(alpha = .15f))
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { AppDetailStaticText(value, style = MaterialTheme.typography.titleMedium.copy(color = foreground, fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis); Spacer(Modifier.height(2.dp)); Text(name, color = foreground.copy(alpha = .72f), style = MaterialTheme.typography.labelSmall) }
            }
        }
        AppRating(data, foreground, card)
        EntityDetails.plain(data, "subtitle", "shorttitle", "brief", "summary").takeIf(String::isNotEmpty)?.let { summary ->
            Row(Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp).fillMaxWidth().background(card, RoundedCornerShape(14.dp)).padding(15.dp)) { AppDetailStaticText("“", style = LocalTextStyle.current.copy(color = foreground.copy(alpha = .55f), fontSize = 28.sp, lineHeight = .9.em)); Spacer(Modifier.width(8.dp)); Text(summary, Modifier.weight(1f), color = foreground.copy(alpha = .92f), textAlign = TextAlign.Center) }
        }
        val images = EntityDetails.values(data, "screenList", "screenshots", "screenArr", "screenshot", "picArr")
        if (images.isNotEmpty()) { Text("应用截图", Modifier.padding(start = 16.dp, top = 20.dp, bottom = 7.dp), color = foreground, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { images.forEachIndexed { index, url -> var failed by remember(url, api.imageCacheScope()) { mutableStateOf(false) }; Box(Modifier.size(112.dp, 192.dp).clip(RoundedCornerShape(10.dp)).clickable { onGallery(images, index, null) }, contentAlignment = Alignment.Center) { if (failed) Box(Modifier.fillMaxSize().background(card), contentAlignment = Alignment.Center) { MaterialGlyph("broken_image_outlined", color = foreground) }; ContentImage(api, url, "应用截图", Modifier.fillMaxSize(), heroCornerRadius = 10.dp, onError = { failed = true }, onDecoded = { _, _ -> failed = false }) } } }
        }
        val tags = EntityDetails.values(data, "tags", "tag", "category_title", "category")
        if (tags.isNotEmpty()) Row(Modifier.padding(top = 14.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { tags.forEach { Text(it, Modifier.background(card, RoundedCornerShape(20.dp)).padding(horizontal = 12.dp, vertical = 8.dp), color = foreground, style = MaterialTheme.typography.labelLarge) } }
        ExpandableAppText("新版特性", EntityDetails.plain(data, "changelog", "changeLog", "updateInfo"), foreground)
        ExpandableAppText("应用介绍", EntityDetails.plain(data, "description", "intro", "appDescription"), foreground)
        data.text("apkRecord", "apkrecord", "recordNumber", "icp", "beian").takeIf(String::isNotEmpty)?.let { Text("APP备案号：$it", Modifier.padding(start = 16.dp, top = 2.dp, end = 16.dp), color = foreground.copy(alpha = .64f), style = MaterialTheme.typography.bodySmall) }
        if (related.isNotEmpty() || relatedError != null || relatedLoading) Column(Modifier.padding(start = 16.dp, top = 18.dp, end = 16.dp)) {
            Text("相关应用", color = foreground, style = MaterialTheme.typography.titleMedium, fontWeight = com.green.note.ui.adjustedWeight(700))
            if (relatedLoading && related.isEmpty()) Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
            else if (relatedError != null && related.isEmpty()) com.green.note.ui.ReviewTextButton(onClick = retryRelated) { Text("加载失败，点击重试：$relatedError", color = foreground) }
            else Column(Modifier.padding(top = 8.dp)) { related.chunked(4).forEach { row -> Row(Modifier.fillMaxWidth()) {
                row.forEach { app ->
                    val target = app.text("packageName", "package_name", "apkname", "apk_name", "id")
                    Column(Modifier.weight(1f).aspectRatio(.68f).clip(RoundedCornerShape(12.dp)).clickable(enabled = target.isNotEmpty()) { onOpen(app) }.padding(horizontal = 3.dp, vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        EntityImage(api, app.text("logo", "apkRomIcon", "icon", "pic"), Modifier.size(52.dp).clip(RoundedCornerShape(14.dp))) {
                            Box(Modifier.fillMaxSize().background(card), contentAlignment = Alignment.Center) { MaterialGlyph("apps_rounded", color = foreground) }
                        }
                        Spacer(Modifier.height(5.dp))
                        Text(app.text("title", "appName", "shorttitle", "name").ifEmpty { "应用" }, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
                        app.text("score", "rating").takeIf(String::isNotEmpty)?.let { Text("$it ★", color = Color(0xffffd54f), style = MaterialTheme.typography.labelSmall) }
                    }
                }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            } } }
        }
        Spacer(Modifier.height(18.dp))
    }
}

@Composable
private fun ExpandableAppText(title: String, value: String, color: Color) {
    if (value.isEmpty()) return
    var expanded by remember(value) { mutableStateOf(false) }
    Column(Modifier.padding(start = 16.dp, top = 22.dp, end = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f), color = color, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = { expanded = !expanded }) { MaterialGlyph(if (expanded) "expand_less" else "expand_more", size = 18.dp, color = color.copy(alpha = .75f)); com.green.note.ui.ReviewButtonIconGap(); Text(if (expanded) "收起" else "展开", color = color.copy(alpha = .75f)) }
        }
        Spacer(Modifier.height(8.dp))
        Text(value, color = color.copy(alpha = .88f), maxLines = if (expanded) Int.MAX_VALUE else 4, overflow = TextOverflow.Ellipsis, lineHeight = 21.7.sp)
    }
}

@Composable
private fun AppDetailStaticText(value: String, style: TextStyle, maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip, modifier: Modifier = Modifier) {
    val metrics = com.green.note.ui.rememberFlutterArticleStyle(AnnotatedString(value), style, plainTitle = true)
    Text(value, modifier = modifier.then(metrics.modifier), style = metrics.style, onTextLayout = metrics.onTextLayout,
        maxLines = maxLines, overflow = overflow)
}

@Composable
private fun AppRating(data: JSONObject, foreground: Color, card: Color) {
    val raw = data.text("score", "rating", "apkScore")
    val score = raw.toDoubleOrNull()?.let { if (it > 5) it / 2 else it }
    val count = data.text("votenum", "voteNum", "score_count")
    if (raw.isEmpty() && count.isEmpty()) return
    val values = (5 downTo 1).map { data.text("votenum$it", "score$it", "score_$it", "star$it", "star_$it", "rating$it").toIntOrNull() ?: 0 }
    val total = values.sum()
    Column(Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp).fillMaxWidth().background(card, RoundedCornerShape(14.dp)).padding(14.dp)) {
        Text("酷安评分", color = foreground, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.width(120.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                AppDetailStaticText(score?.let { String.format(Locale.ROOT, "%.1f", it) } ?: raw.ifEmpty { "—" }, style = MaterialTheme.typography.headlineMedium.copy(color = foreground, fontSize = 38.sp, lineHeight = 1.05.em, fontWeight = FontWeight.Bold))
                Spacer(Modifier.height(5.dp))
                Row { repeat(5) { MaterialGlyph(if (it < (score?.roundToInt() ?: 0)) "star_rounded" else "star_outline_rounded", color = Color(0xffffca28), size = 18.dp) } }
                Spacer(Modifier.height(4.dp))
                if (count.isNotEmpty()) AppDetailStaticText("${count}人点评", style = MaterialTheme.typography.labelSmall.copy(color = foreground.copy(alpha = .72f)))
            }
            if (total > 0) Column(Modifier.weight(1f)) { values.forEachIndexed { index, value -> Row(Modifier.padding(vertical = 1.dp), verticalAlignment = Alignment.CenterVertically) {
                AppDetailStaticText("${5 - index}星", style = MaterialTheme.typography.labelSmall.copy(color = foreground.copy(alpha = .78f))); Spacer(Modifier.width(7.dp))
                com.green.note.ui.ReviewLinearProgress(progress = { value.toFloat() / total }, Modifier.weight(1f).height(9.dp).clip(RoundedCornerShape(8.dp)), color = Color(0xffffca28), trackColor = foreground.copy(alpha = .12f))
                Spacer(Modifier.width(7.dp))
                Text("$value", Modifier.width(38.dp), color = foreground.copy(alpha = .78f), style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.End)
            } } }
        }
        Spacer(Modifier.height(10.dp))
        Box(Modifier.fillMaxWidth().height(1.dp), contentAlignment = Alignment.Center) {
            HorizontalDivider(thickness = .6.dp, color = foreground.copy(alpha = .12f))
        }
    }
}

internal data class ProductDetailTab(val title: String, val type: String, val route: String = "", val subId: String = "")
private val productAccent = Color(0xff009688)
private val productWatchHeader = Color(0xff3f535a)
private val productTabletHeader = Color(0xff3c4e5c)
private val productPreviewHeader = Color(0xff39505f)

internal enum class ProductFooterAction(val label: String, val icon: String) {
    Compare("对比", ""), Follow("关注", "favorite_border_rounded"), Rate("打分", "star_border_rounded"),
    Unreleased("未发布", "star_border_rounded"), Buy("购买", "shopping_bag_outlined"),
}

internal fun productFooterActions(raw: JSONObject): List<ProductFooterAction> = buildList {
    val phone = raw.text("category_id") == "1000"
    val unreleased = raw.text("release_status") == "0"
    if (phone) add(ProductFooterAction.Compare)
    add(ProductFooterAction.Follow)
    add(if (unreleased) ProductFooterAction.Unreleased else ProductFooterAction.Rate)
    val canBuy = if (phone) raw.text("release_status") == "1" else productBuyUrl(raw).isNotEmpty()
    if (!unreleased && canBuy) {
        add(ProductFooterAction.Buy)
    }
}

internal fun productDetailTabs(raw: JSONArray?, id: String): List<ProductDetailTab> {
    val defaults = listOf("参数" to "main", "讨论" to "feed", "点评" to "rating", "图文" to "article", "问答" to "answer", "视频" to "video", "二手" to "trade").map { ProductDetailTab(it.first, it.second) }
    val parsed = raw.objects().mapNotNull { value ->
        val title = value.text("title"); val url = value.text("url")
        if (value.optString("is_open") == "0" || title.isEmpty() || url.isEmpty()) return@mapNotNull null
        val outer = Uri.parse(url.removePrefix("#"))
        if (!outer.isHierarchical) return@mapNotNull null
        val inner = Uri.parse(outer.getQueryParameter("url") ?: url.removePrefix("#"))
        if (!inner.isHierarchical) return@mapNotNull null
        val type = inner.getQueryParameter("type") ?: outer.getQueryParameter("type").orEmpty()
        val target = inner.getQueryParameter("id") ?: outer.getQueryParameter("id").orEmpty()
        when {
            inner.toString().contains("/product/feedList") && (target.isEmpty() || target == id) && type.isNotEmpty() -> ProductDetailTab(title, type, url, inner.getQueryParameter("subId") ?: outer.getQueryParameter("subId").orEmpty())
            !inner.toString().contains("/product/feedList") && (url.startsWith("/") || url.startsWith("#/")) -> ProductDetailTab(title, "external", url)
            else -> null
        }
    }.orEmpty().toMutableList()
    if (parsed.isEmpty()) return defaults
    if (parsed.none { it.type == "main" }) parsed.add(0, ProductDetailTab("参数", "main"))
    return parsed
}

internal fun productDetailRequest(tab: ProductDetailTab, id: String, sort: String): ContentRequest {
    if (tab.type == "external") return contentRequest(tab.route)
    val outer = Uri.parse(tab.route.removePrefix("#"))
    val inner = Uri.parse(outer.getQueryParameter("url") ?: tab.route.removePrefix("#"))
    val query = inner.queryParameterNames.associateWith { inner.getQueryParameter(it).orEmpty() }.toMutableMap()
    query.putAll(mapOf("url" to "/page?url=/product/feedList", "id" to id, "type" to tab.type, "withSortCard" to "0", "withSubTabFeedCard" to "0"))
    if (tab.subId.isNotEmpty()) query["subId"] = tab.subId
    when (tab.type) {
        "feed" -> query["listType"] = when (sort) { "latest" -> "dateline_desc"; "hot" -> "hot_desc"; else -> "lastupdate_desc" }
        "rating" -> {
            query["listType"] = if (sort == "latest") "dateline_desc" else "hot_desc"
            query["withRatingSortCard"] = "0"
        }
        "subTabFeed" -> if (sort != "default") query["listType"] = if (sort == "latest") "dateline_desc" else "rank_score"
        "trade" -> query["listType"] = "dateline_desc"
    }
    return ContentRequest("/v6/page/dataList", query)
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun NativeProductDetail(api: ContentApi, id: String, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit,
    onBack: () -> Unit, onOpen: (JSONObject) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit, onCompose: () -> Unit) {
    var detail by remember(id) { mutableStateOf<JSONObject?>(null) }
    var loading by remember(id) { mutableStateOf(true) }
    var error by remember(id) { mutableStateOf<String?>(null) }
    var reload by remember(id) { mutableIntStateOf(0) }
    var following by remember(id) { mutableStateOf(false) }
    var followBusy by remember(id) { mutableStateOf(false) }
    var comparison by remember { mutableStateOf(false) }
    var selector by remember { mutableStateOf(false) }
    var selected by remember(id) { mutableStateOf(ProductDetailTab("讨论", "feed")) }
    var sort by remember(id) { mutableStateOf("default") }
    var configId by remember(api, id) { mutableStateOf("") }
    val configCache = remember(api, id) { mutableStateMapOf<String, List<Pair<String, String?>>>() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val scroll = rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    val compact by remember { derivedStateOf { scroll.firstVisibleItemIndex > 0 } }
    val tabs = remember(detail) { productDetailTabs(detail?.optJSONArray("tabList"), id) }
    LaunchedEffect(api, id, reload) {
        loading = true; error = null
        try {
            val value = EntityDetails.objectValue(api.request("/v6/product/detail", query = mapOf("id" to id)).opt("data"))
            check(value.length() > 0) { "暂无产品资料" }; if (!value.has("id")) value.put("id", id)
            detail = value; following = api.isProductFollowed(value)
            val parsed = productDetailTabs(value.optJSONArray("tabList"), id)
            selected = parsed.firstOrNull { it.type == selected.type && it.subId == selected.subId } ?: parsed.firstOrNull { it.type == "feed" } ?: parsed.first()
        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message }
        finally { loading = false }
    }
    val list = remember(api, id, selected.type, selected.subId, selected.route) { ContentListState() }
    val listRequest = remember(selected, id, sort) { productDetailRequest(selected, id, sort) }
    LaunchedEffect(list, listRequest, detail != null) {
        if (detail != null && selected.type != "main") {
            list.bind(listRequest) { page, first, last ->
                val result = topicPage(api, listRequest, page, first, last)
                if (selected.type == "external") result
                else result.copy(rows = result.rows.filter { discoveryVisible(it) && it.text("entityTemplate") != "sortSelectCard" })
            }
        }
    }
    LaunchedEffect(list, scroll, selected) { snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect { last ->
        if (selected.type != "main" && list.rows.isNotEmpty() && last >= list.rows.size - 1 && list.error == null) list.load()
    } }
    fun follow() { if (!followBusy) detail?.let { value -> scope.launch {
        followBusy = true
        val previous = following
        following = !previous
        try { following = api.followProduct(value, previous) }
        catch (cancelled: CancellationException) { following = previous; throw cancelled } catch (failure: Exception) { following = previous; com.green.note.ui.AppToastState().showSnackbar(failure.message ?: "关注失败，请重试") }
        finally { followBusy = false }
    } } }
    fun toast(value: String) { com.green.note.ui.AppToastState().showSnackbar(value) }
    fun buy() {
        val value = detail ?: return
        val explicit = productBuyUrl(value)
        val title = value.text("title").ifEmpty { "手机" }
        val fallback = "https://so.m.jd.com/ware/search.action?keyword=${Uri.encode(title)}"
        val jd = "openapp.jdmobile://virtual?params=${Uri.encode(JSONObject().put("category", "jump").put("des", "search").put("keyWord", title).toString())}"
        fun open(url: String) = runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))); true }.getOrDefault(false)
        if (explicit.startsWith("https://") || explicit.startsWith("http://") || explicit.startsWith("openapp.jdmobile://")) if (open(explicit)) return
        if (!open(jd) && !open(fallback)) toast("无法打开购买链接")
    }
    if (comparison) { NativeProductComparison(api, detail ?: JSONObject().put("id", id), onBack = { comparison = false }); return }
    if (selector) { NativeProductSelector(api, onBack = { selector = false }, onSelected = { selector = false; onOpen(it.put("entityType", "product")) }); return }
    val raw = detail ?: JSONObject()
    val title = raw.text("title").ifEmpty { "数码产品" }
    val unreleased = raw.optString("release_status") == "0"
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < .5f
    val pureBlack = com.green.note.ui.LocalAppPreferences.current.pureBlackDark
    val pageColor = if (dark && !pureBlack) Color(0xff101010) else com.green.note.ui.LocalScaffoldColor.current
    val headerColor = if (!dark || pureBlack) com.green.note.ui.LocalScaffoldColor.current else when (raw.text("category_id")) {
        "1000" -> if (unreleased) productPreviewHeader else com.green.note.ui.LocalScaffoldColor.current
        "1001" -> productTabletHeader
        "1005" -> productWatchHeader
        else -> com.green.note.ui.LocalScaffoldColor.current
    }
    val tabColor = if (dark) Color(0xff1c1c1e) else scheme.surfaceContainerLowest
    val actions = remember(raw) { productFooterActions(raw) }
    val actionHeight = maxOf(46f, 28 + 13 * androidx.compose.ui.platform.LocalDensity.current.fontScale).dp
    Column(Modifier.fillMaxSize().background(pageColor)) {
        Row(Modifier.fillMaxWidth().background(if (compact) tabColor else headerColor).statusBarsPadding().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick = onBack, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back_rounded", contentDescription = "返回") }
            Spacer(Modifier.width(4.dp))
            if (compact) {
                if (raw.text("logo", "cover", "pic").isNotEmpty()) { ContentImage(api, raw.text("logo", "cover", "pic"), null, Modifier.size(28.dp, 34.dp), ContentScale.Fit); Spacer(Modifier.width(10.dp)) }
                Column(Modifier.weight(1f)) {
                    com.green.note.ui.ReviewBasicText(title, style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, localeList = com.green.note.ui.ReviewTextLocales, platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false)), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val score = ratingScore(raw)
                    if (!unreleased && score > 0) Row(verticalAlignment = Alignment.CenterVertically) {
                        repeat(5) { i -> MaterialGlyph(if (score / 2 >= i + 1) "star_rounded" else if (score / 2 > i) "star_half_rounded" else "star_outline_rounded", size = 12.dp, color = Color(0xffffa000)) }
                        Spacer(Modifier.width(4.dp)); com.green.note.ui.ReviewBasicText(String.format(Locale.ROOT, "%.1f", score), style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color(0xffffa000), platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false)))
                    }
                }
                com.green.note.ui.ReviewTextButton(onClick = ::follow, enabled = !followBusy, modifier = Modifier.widthIn(min = 64.dp).height(48.dp), contentPadding = PaddingValues(horizontal = 14.dp), colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface, containerColor = MaterialTheme.colorScheme.surfaceContainerHighest)) { Text(if (following) "已关注" else "关注") }
            }
            else Spacer(Modifier.weight(1f))
            com.green.note.ui.ReviewIconButton(onClick = { onLink("https://www.coolapk.com/search?q=${Uri.encode(title)}") }) { MaterialGlyph("search_rounded", contentDescription = "搜索机型") }
        }
        GlassBackdropHost(Modifier.weight(1f), content = {
            ReviewRefreshBox(isRefreshing = loading && detail != null || list.refreshing, failed = error != null || list.error != null, onRefresh = { reload++; scope.launch { if (selected.type != "main") list.load(true) } }, modifier = Modifier.fillMaxSize().background(pageColor)) {
                LazyColumn(Modifier.fillMaxSize().pointerInput(tabs, selected) {
                    var distance = 0f
                    detectHorizontalDragGestures(onDragStart = { distance = 0f }, onDragCancel = { distance = 0f }, onDragEnd = {
                        if (kotlin.math.abs(distance) >= 48.dp.toPx()) {
                            val next = tabs.indexOf(selected) + if (distance < 0) 1 else -1
                            tabs.getOrNull(next)?.let { selected = it }
                        }
                    }) { change, amount -> change.consume(); distance += amount }
                }, state = scroll, contentPadding = PaddingValues(bottom = 90.dp)) {
                    item {
                        if (detail == null) LoadingFailure(loading, error) { reload++ }
                        else ProductHeader(api, raw, headerColor, following, followBusy, ::follow, ::toast)
                    }
                    if (detail != null) {
                        stickyHeader {
                            BoxWithConstraints(Modifier.fillMaxWidth().background(headerColor)) {
                                val minTabWidth = ((maxWidth - 12.dp) / tabs.size).coerceAtLeast(56.dp)
                                val radius = if (compact) 0.dp else 12.dp
                                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = radius, topEnd = radius))
                                    .background(tabColor).horizontalScroll(rememberScrollState()).padding(horizontal = 6.dp).selectableGroup()) {
                                    tabs.forEach { tab ->
                                        val active = tab == selected
                                        Box(Modifier.widthIn(min = minTabWidth).heightIn(min = 49.dp)
                                            .semantics { this.selected = active }.clickable(role = Role.Tab) { selected = tab }
                                            .padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                                            Text(tab.title, Modifier.padding(vertical = 10.dp), fontSize = 16.sp, lineHeight = 20.sp, softWrap = false,
                                                color = if (active) productAccent else scheme.onSurfaceVariant, fontWeight = if (active) FontWeight.Medium else FontWeight.Normal)
                                            if (active) Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp)
                                                .size(10.dp, 3.dp).background(productAccent, CircleShape))
                                        }
                                    }
                                }
                            }
                        }
                        if (selected.type == "main") item {
                            NativeProductSpecs(api, raw, configId, { configId = it }, configCache)
                        }
                        else {
                            if (selected.type == "subTabFeed" && selected.subId == "6") item { ProductPriceSummary(raw) }
                            if (selected.type in listOf("feed", "rating") || selected.type == "subTabFeed" && selected.subId == "6") item(key = "product-sort") {
                                ProductSortRow(selected.type, sort) { sort = it }
                            }
                            items(list.rows, key = ::entityKey) { row ->
                                val card = remember(row, selected.type) {
                                    if (selected.type == "feed" && contentEntityIsFeed(row)) JSONObject(row.toString()).put("_composeProductDiscussion", true) else row
                                }
                                EntityRow(api, card, onOpen, { onLink("/u/$it") }, onLink, onGallery, onLike, onMore)
                            }
                            item(key = "product-list-status") { LoadingFailure(list.busy, list.error, if (list.rows.isEmpty()) "暂无内容" else if (!list.more) "已经到底了" else "") { scope.launch { list.load(list.rows.isEmpty()) } } }
                        }
                    }
                }
            }
        }, overlay = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding().coerceAtLeast(20.dp)
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = bottom), verticalAlignment = Alignment.CenterVertically) {
                if (detail != null) GlassSurface(Modifier.width((18 + actions.size * 40 + if (unreleased) 7 else 0).dp).height(actionHeight),
                    cornerRadius = 9999.dp, liquid = true, interactive = false, material = com.green.note.ui.GlassMaterial.NAVIGATION,
                    tintColor = if (dark) Color(0xf0000000) else null) {
                    Row(Modifier.fillMaxSize().padding(horizontal = 9.dp)) {
                        actions.forEach { action ->
                            val disabled = action == ProductFooterAction.Unreleased
                            val followed = action == ProductFooterAction.Follow && following
                            Column(Modifier.weight(if (disabled) 47f else 40f).fillMaxHeight().clickable(enabled = !disabled) {
                                when (action) {
                                    ProductFooterAction.Compare -> comparison = true
                                    ProductFooterAction.Follow -> follow()
                                    ProductFooterAction.Rate -> toast("评分功能需登录机主账号")
                                    ProductFooterAction.Buy -> buy()
                                    ProductFooterAction.Unreleased -> Unit
                                }
                            },
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                                val foreground = if (followed) productAccent else if (dark) Color(0xffd4d4d4) else scheme.onSurfaceVariant
                                val color = if (disabled) foreground.copy(alpha = .58f) else foreground
                                if (action == ProductFooterAction.Compare) {
                                    Box(Modifier.height(20.dp), contentAlignment = Alignment.Center) {
                                        Text("PK", fontSize = 18.sp, lineHeight = 20.sp, fontStyle = FontStyle.Italic, fontWeight = FontWeight.Black, color = color)
                                    }
                                } else MaterialGlyph(if (followed) "favorite_rounded" else action.icon, size = 20.dp, color = color)
                                Text(if (followed) "已关注" else action.label, fontSize = 10.sp, lineHeight = 13.sp, maxLines = 1, color = color)
                            }
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                com.green.note.ui.GreenComposeFab(onCompose, size = 46.dp, color = productAccent, iconColor = if (dark) Color(0xff072c28) else Color.White)
            }
        } })
    }
    LaunchedEffect(error, detail) { if (detail != null && error != null) { com.green.note.ui.AppToastState().showSnackbar(error.orEmpty()); error = null } }
}

@Composable
private fun ProductSortRow(type: String, sort: String, onSort: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < .5f
    Row(Modifier.fillMaxWidth().heightIn(min = 36.dp).padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(when (type) { "feed" -> "全部讨论"; "rating" -> "全部点评"; else -> "排序规则" }, Modifier.weight(1f), fontSize = 14.sp, lineHeight = 18.sp)
        Row(Modifier.background(if (dark) Color(0xff2c2c2e) else scheme.surfaceContainerHighest, CircleShape)
            .padding(1.dp).selectableGroup()) {
            listOf("default" to "默认", "latest" to "最新", "hot" to "热度").forEach { (key, label) ->
                val active = sort == key
                Box(Modifier.widthIn(min = 43.dp).heightIn(min = 25.dp).clip(CircleShape)
                    .background(if (active) { if (dark) Color(0xff1c1c1e) else scheme.surface } else Color.Transparent)
                    .semantics { selected = active }.clickable(role = Role.RadioButton) { onSort(key) }.padding(horizontal = 5.dp),
                    contentAlignment = Alignment.Center) {
                    Text(label, color = if (active) scheme.onSurface else scheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = 16.sp, softWrap = false)
                }
            }
        }
    }
}

private fun productBuyUrl(raw: JSONObject): String =
    raw.text("sell_url", "buy_url", "goods_buy_url", "jd_url", "mall_url", "shop_url")
        .takeIf { it.startsWith("https://") || it.startsWith("http://") || it.startsWith("openapp.jdmobile://") }.orEmpty()

private val productRatingFields = listOf(
    "续航" to "score_battery", "影像" to "score_camera", "性能" to "score_performance",
    "屏幕" to "score_screen", "外观质感" to "score_appearance", "性价比" to "score_cost",
)

internal fun productDimensionScores(raw: JSONObject): List<Pair<String, Float?>> {
    val dimensions = raw.optJSONArray("rating_item_info").objects()
    fun score(vararg values: String) = values.firstNotNullOfOrNull { it.toFloatOrNull()?.takeIf { value -> value > 0f && value <= 10f } }
    val named = dimensions.filter { it.text("name").isNotBlank() }
    if (raw.text("category_id") !in setOf("", "1000") && named.isNotEmpty()) {
        return named.map { it.text("name") to score(it.text("owner_average_score"), it.text("average_score")) }
    }
    return productRatingFields.mapIndexed { index, (label, legacyKey) ->
        val number = index + 1
        val dimension = named.firstOrNull { it.text("name") == label }
            ?: dimensions.firstOrNull { it.text("name").isEmpty() && it.text("id") == "v4_score_item_$number" }
        label to score(
            dimension?.text("owner_average_score").orEmpty(), dimension?.text("average_score").orEmpty(),
            raw.text(legacyKey), raw.text("score_$number"), raw.text("rating_average_score_$number"),
        )
    }
}

@Composable
private fun ProductPriceSummary(raw: JSONObject) {
    val statistics = EntityDetails.objectValue(raw.opt("subtab_statistics_item6"))
    val amount = statistics.text("final_price").toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 } ?: return
    val formatted = java.math.BigDecimal.valueOf(amount).setScale(2, java.math.RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.padding(start = 8.dp, top = 8.dp, end = 8.dp).fillMaxWidth().background(if (scheme.background.luminance() < .5f) Color(0xff1e1e1e) else scheme.surfaceContainer, RoundedCornerShape(8.dp)).padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            MaterialGlyph("currency_yen_rounded", size = 16.dp, color = Color(0xffff9800)); Spacer(Modifier.width(4.dp)); Text("到手价", fontSize = 13.sp); Spacer(Modifier.width(12.dp))
            Text(statistics.text("update_time").let { if (it.isEmpty()) "" else "发布时间：$it" }, Modifier.weight(1f), fontSize = 12.sp, color = scheme.onSurfaceVariant, textAlign = TextAlign.End)
        }
        Spacer(Modifier.height(14.dp))
        Text(buildAnnotatedString {
            withStyle(SpanStyle(fontSize = 13.sp, color = scheme.onSurfaceVariant)) { append("当前最低价 ") }
            withStyle(SpanStyle(fontSize = 20.sp)) { append("¥") }
            withStyle(SpanStyle(fontSize = 28.sp, fontWeight = FontWeight.SemiBold)) { append(formatted) }
        }, fontSize = 28.sp)
    }
}

@Composable
private fun ProductHeader(api: ContentApi, raw: JSONObject, headerColor: Color, following: Boolean, busy: Boolean,
    follow: () -> Unit, toast: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < .5f
    val foreground = if (dark) Color(0xffededed) else scheme.onSurface
    val cardColor = when {
        headerColor == productWatchHeader -> Color(0xff304346)
        headerColor == productTabletHeader -> Color(0xff303e49)
        headerColor == productPreviewHeader -> Color(0xff2e404c)
        dark -> Color(0xff222222)
        else -> scheme.surfaceContainerHighest.copy(alpha = .5f)
    }
    val unreleased = raw.text("release_status") == "0"
    val score = ratingScore(raw).takeIf { it > 0 && it <= 10 }
        ?: raw.text("score").toDoubleOrNull()?.takeIf { it > 0 && it <= 10 }
    val tablet = raw.text("category_id") == "1001"
    val dimensions = remember(raw) { productDimensionScores(raw) }
    val officialTags = remember(raw) { EntityDetails.values(raw, "product_specs", "productSpecs", "tagArr", "tag_arr", "specTags", "spec_tags", "specs_tags") }
    val release = raw.text("release_time_txt", "release_time")
        .takeIf { it.isNotBlank() && it != "0" && it != "-" }?.removeSuffix("上市")?.trimEnd()
    var headerConfig by remember(raw) { mutableStateOf(JSONObject()) }
    LaunchedEffect(api, raw) {
        if (officialTags.isEmpty()) {
            val configId = raw.optJSONArray("configRows").objects().firstOrNull()?.text("id").orEmpty()
            if (configId.isNotEmpty()) try {
                val config = EntityDetails.objectValue(api.request("/v6/product/config", query = mapOf("id" to configId)).opt("data"))
                headerConfig = EntityDetails.objectValue(config.opt("config_data"))
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* Optional metadata. */ }
        }
    }
    val tags = officialTags.ifEmpty {
        fun spec(vararg aliases: String) = productSpecValue(raw, aliases.toList()).ifEmpty { productSpecValue(headerConfig, aliases.toList()) }
        listOf(spec("chip", "soc", "processor", "CPU型号", "处理器", "芯片", "soc型号", "处理器型号"),
            spec("screen_size", "screen", "屏幕尺寸", "主屏尺寸"), raw.text("screen_type"), raw.text("battery"), raw.text("charging"))
            .filter { it.isNotEmpty() && it != "-" }
    }
    val specs = if (unreleased) tags else
        (listOfNotNull(release?.replace('年', '-')?.replace('月', '-')?.trimEnd('日', '-')?.let { "$it 上市" }) + tags).distinct()
    val followers = remember(raw) { raw.optJSONArray("recent_follow_list").objects().take(3) }
    val fontScale = androidx.compose.ui.platform.LocalDensity.current.fontScale
    Column(Modifier.fillMaxWidth().background(headerColor).padding(top = 12.dp, bottom = 12.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.Top) {
            EntityImage(api, raw.text("logo", "cover", "pic"), Modifier.size(80.dp).clip(RoundedCornerShape(8.dp))
                .background(if (unreleased || tablet) Color.Transparent else cardColor), ContentScale.Fit) {
                MaterialGlyph("devices_rounded", size = 32.dp, color = productAccent)
            }
            Spacer(Modifier.width(10.dp))
            Box(Modifier.weight(1f)) {
                Column(Modifier.fillMaxWidth().heightIn(min = 80.dp), verticalArrangement = Arrangement.SpaceBetween) {
                    Text(raw.text("title").ifEmpty { "数码产品" },
                        Modifier.padding(end = if (tablet || fontScale > 1.1f) 64.dp else 0.dp),
                        color = if (dark) Color.White else foreground, fontSize = 21.6.sp, lineHeight = 28.sp,
                        maxLines = if (tablet) 2 else 1, overflow = TextOverflow.Ellipsis, letterSpacing = 0.sp)
                    if (tablet) Spacer(Modifier.height(1.dp))
                    Column(Modifier.fillMaxWidth().padding(end = 64.dp)) {
                        val heat = raw.text("hot_num_txt", "hot_num")
                        val posts = raw.text("feed_comment_num_txt", "feed_comment_num", "feed_num_txt", "feed_num")
                        Text(listOfNotNull(heat.takeIf(String::isNotEmpty)?.let { "${it}热度" },
                            posts.takeIf(String::isNotEmpty)?.let { "${it}讨论" }).joinToString("  "),
                            color = foreground.copy(alpha = .58f), fontSize = 12.sp, lineHeight = 16.sp,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (followers.isNotEmpty()) {
                                Row(horizontalArrangement = Arrangement.spacedBy((-7).dp)) {
                                    followers.forEach { follower ->
                                        val avatar = follower.text("userAvatar", "avatar").ifEmpty {
                                            follower.optJSONObject("userInfo")?.text("userAvatar", "avatar").orEmpty()
                                        }
                                        ContentImage(api, avatar, null, Modifier.size(20.dp).clip(CircleShape)
                                            .background(cardColor).border(1.dp, foreground, CircleShape), ContentScale.Crop)
                                    }
                                }
                                Spacer(Modifier.width(8.dp))
                            }
                            val count = raw.text("follow_num_txt", "follow_num")
                            if (count.isNotEmpty()) {
                                Text("${count}关注", color = foreground.copy(alpha = .82f), fontSize = 12.sp,
                                    lineHeight = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                                MaterialGlyph("chevron_right_rounded", size = 14.dp, color = foreground.copy(alpha = .82f))
                            }
                        }
                    }
                }
                Box(Modifier.align(Alignment.TopEnd).padding(top = 25.dp).widthIn(min = 60.dp).heightIn(min = 30.dp)
                    .clip(RoundedCornerShape(7.dp)).background(if (following) cardColor else productAccent)
                    .clickable(enabled = !busy, onClick = follow).padding(horizontal = 6.dp, vertical = 4.dp),
                    contentAlignment = Alignment.Center) {
                    Text(if (following) "已关注" else "关注", color = if (following) foreground else Color.White,
                        fontSize = 14.sp, lineHeight = 18.sp, maxLines = 1)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Column(Modifier.padding(horizontal = 12.dp).fillMaxWidth().background(cardColor, RoundedCornerShape(8.dp))
            .padding(start = 16.dp, end = 16.dp, top = 11.dp, bottom = 6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("酷安评分", Modifier.weight(1f), color = foreground, fontSize = 14.sp, lineHeight = 17.sp,
                    fontWeight = FontWeight.ExtraBold, style = LocalTextStyle.current.copy(
                        textGeometricTransform = androidx.compose.ui.text.style.TextGeometricTransform(scaleX = 1.23f)))
                Text(if (unreleased) release?.let { "${it}上市" } ?: "未发布" else "详细数据",
                    color = foreground.copy(alpha = .6f), fontSize = if (unreleased) 12.sp else 10.sp, lineHeight = 16.sp)
                if (!unreleased) MaterialGlyph("chevron_right_rounded", size = 15.dp, color = foreground.copy(alpha = .6f))
            }
            Spacer(Modifier.height(7.dp))
            val ownerCount = raw.text("owner_star_total_count").toIntOrNull() ?: 0
            val ownerRating = ownerCount > 0 || unreleased && raw.text("category_id") == "1000"
            val gold = Color(0xffda9d15)
            if (unreleased) {
                Box(Modifier.fillMaxWidth().heightIn(min = 72.dp), contentAlignment = Alignment.Center) {
                    Text(buildAnnotatedString {
                        withStyle(SpanStyle(fontSize = 21.sp)) { append(EntityDetails.count(raw.optString("wish_count", "0"))) }
                        append(" 人想买")
                    }, color = foreground.copy(alpha = .6f), fontSize = 14.sp, lineHeight = 28.sp)
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(.4f).offset(y = 2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(score?.let { String.format(Locale.ROOT, "%.1f", it) } ?: "—", color = foreground.copy(alpha = .9f),
                            fontSize = 34.sp, lineHeight = 38.sp, fontWeight = FontWeight.Medium, maxLines = 1)
                        Spacer(Modifier.height(2.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            repeat(5) { index ->
                                val lit = score != null && index < (score / 2).roundToInt()
                                Box(Modifier.size(12.dp).background(if (lit) gold else foreground.copy(alpha = .28f), RoundedCornerShape(2.dp)),
                                    contentAlignment = Alignment.Center) {
                                    MaterialGlyph("star_rounded", size = 9.dp, color = Color.White.copy(alpha = if (lit) 1f else .55f))
                                }
                            }
                        }
                        Spacer(Modifier.height(3.dp))
                        Text(if (ownerRating) "机主评分" else "用户评分", color = foreground.copy(alpha = .6f), fontSize = 10.sp, lineHeight = 13.sp)
                    }
                    Column(Modifier.weight(.6f)) {
                        dimensions.forEach { (label, value) ->
                            Row(Modifier.height((14.3f * fontScale.coerceAtLeast(1f)).dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(label, Modifier.widthIn(min = 44.dp), color = foreground.copy(alpha = .62f), textAlign = TextAlign.End,
                                    fontSize = 10.sp, lineHeight = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Spacer(Modifier.width(8.dp))
                                Box(Modifier.weight(1f).height(8.dp).background(foreground.copy(alpha = .075f), CircleShape)) {
                                    if (value != null) Box(Modifier.fillMaxWidth(value / 10f).fillMaxHeight().background(gold, CircleShape))
                                }
                                Spacer(Modifier.width(8.dp))
                                Text(value?.let { String.format(Locale.ROOT, "%.1f", it) } ?: "—", Modifier.widthIn(min = 24.dp),
                                    color = foreground.copy(alpha = .9f), fontSize = 10.sp, lineHeight = 13.sp, maxLines = 1)
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            HorizontalDivider(thickness = 1.dp, color = foreground.copy(alpha = .07f))
            Spacer(Modifier.height(6.dp))
            val total = raw.text("star_total_count", "rating_total_num_txt", "rating_total_num")
            val detailed = raw.text(if (ownerRating) "v4_rating_owner_total_count" else "v4_rating_total_count", "rating_total_num_txt", "rating_total_num")
            val counts = listOfNotNull(if (ownerRating) "${ownerCount}机主点评" else total.takeIf(String::isNotEmpty)?.let { "${it}用户点评" },
                detailed.takeIf(String::isNotEmpty)?.let { "${it}详细点评" }).joinToString(" ")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(counts, Modifier.weight(1f), color = foreground.copy(alpha = .61f), fontSize = 12.sp, lineHeight = 16.sp,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.width(6.dp))
                ProductCapsuleAction("想买", foreground) { toast("已加入想买清单") }
                Spacer(Modifier.width(12.dp))
                ProductCapsuleAction(if (unreleased) "未发布" else "打分", foreground, enabled = !unreleased) { toast("评分功能需登录机主账号") }
            }
        }
        if (specs.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                specs.forEach { tag ->
                    Box(Modifier.heightIn(min = 30.dp).background(cardColor, RoundedCornerShape(8.dp)).padding(horizontal = 11.dp, vertical = 4.dp),
                        contentAlignment = Alignment.Center) {
                        Text(tag, color = foreground.copy(alpha = .88f), fontSize = 14.sp, lineHeight = 18.sp, maxLines = 1)
                    }
                }
            }
        }
    }
}

@Composable
private fun ProductCapsuleAction(label: String, foreground: Color, enabled: Boolean = true, onClick: () -> Unit) {
    Box(Modifier.widthIn(min = 48.dp).heightIn(min = 22.dp).clip(CircleShape)
        .then(if (enabled) Modifier.background(foreground.copy(alpha = .23f)) else Modifier.border(1.dp, foreground.copy(alpha = .23f), CircleShape))
        .clickable(enabled = enabled, onClick = onClick).padding(horizontal = 5.dp, vertical = 2.dp), contentAlignment = Alignment.Center) {
        Text(label, color = foreground.copy(alpha = if (enabled) .9f else .56f), fontSize = 12.sp, lineHeight = 16.sp, maxLines = 1)
    }
}
internal fun productSpecValue(source: JSONObject, aliases: List<String>, depth: Int = 0): String {
    if (depth > 8) return ""
    fun normalized(value: String) = value.replace(Regex("[\\s_./-]"), "").lowercase(Locale.ROOT)
    for (alias in aliases) for (key in source.keys()) {
        if (normalized(key) != normalized(alias)) continue
        val value = source.opt(key)
        val text = when (value) {
            is JSONObject -> productSpecValue(value, aliases, depth + 1)
            is JSONArray -> (0 until value.length()).joinToString("、") { value.optString(it) }
            null, JSONObject.NULL -> ""
            else -> value.toString().trim()
        }
        if (text.isNotEmpty() && text != "-" && !text.equals("null", true)) return text
    }
    for (key in source.keys()) source.optJSONObject(key)?.let { nested -> productSpecValue(nested, aliases, depth + 1).takeIf(String::isNotEmpty)?.let { return it } }
    return ""
}

internal fun productConfigRows(raw: JSONObject): List<Pair<String, String?>> {
    val rows = mutableListOf<Pair<String, String?>>()
    fun append(value: JSONObject, prefix: String, depth: Int) {
        if (depth > 8 || rows.size > 10000) return
        value.keys().forEach { key ->
            val name = if (prefix.isEmpty()) key else "$prefix / $key"
            when (val nested = value.opt(key)) {
                is JSONObject -> { if (depth == 0) rows.add(name to null); append(nested, if (depth == 0) "" else name, depth + 1) }
                is JSONArray -> (0 until nested.length()).joinToString("、") { nested.opt(it)?.toString().orEmpty() }.takeIf(String::isNotBlank)?.let { rows.add(name to it) }
                null, JSONObject.NULL -> Unit
                else -> nested.toString().trim().takeIf(String::isNotBlank)?.let { rows.add(name to it) }
            }
        }
    }
    append(raw, "", 0); return rows
}

internal fun fallbackProductSpecs(raw: JSONObject): List<Pair<String, String?>> {
    val result = mutableListOf<Pair<String, String?>>()
    fun group(title: String, vararg fields: Pair<String, String>) { val present = fields.filter { it.second.isNotBlank() && it.second != "-" }; if (present.isNotEmpty()) { result.add(title to null); result.addAll(present) } }
    group("基本信息", "上市时间" to raw.text("release_time_txt", "release_time"), "官方价格" to raw.text("price", "price_str").let { if (it.isEmpty() || it.startsWith("¥")) it else "¥$it" })
    group("性能与配置", "处理器 / 芯片" to raw.text("chip", "soc", "processor"), "存储组合" to "${raw.text("ram")} ${raw.text("rom")}".trim())
    group("屏幕规格", "屏幕尺寸" to raw.text("screen_size", "screen"), "材质 / 形态" to raw.text("screen_type"), "分辨率" to raw.text("screen_resolution"), "刷新率" to raw.text("screen_refresh_rate"))
    group("影像系统", "影像联名" to raw.text("camera_brand"), "后置主摄" to raw.text("main_camera", "camera"))
    group("续航与机身", "电池容量" to raw.text("battery"), "充电规格" to raw.text("charging"), "机身尺寸" to listOf(raw.text("thickness"), raw.text("weight")).filter(String::isNotEmpty).joinToString(" / "))
    return result
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun NativeProductSpecs(api: ContentApi, raw: JSONObject, configId: String, onSelect: (String) -> Unit,
    cache: MutableMap<String, List<Pair<String, String?>>>) {
    val configs = remember(raw) { raw.optJSONArray("configRows").objects() }
    val selected = configId.takeIf { id -> configs.any { it.text("id") == id } }
        ?: configs.firstOrNull()?.text("id").orEmpty()
    val fallback = remember(raw) { fallbackProductSpecs(raw) }
    val params = cache[selected] ?: fallback
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(api, selected, attempt) {
        error = null
        if (selected.isEmpty() || cache[selected] != null) return@LaunchedEffect
        loading = true
        try { val data = EntityDetails.objectValue(api.request("/v6/product/config", query = mapOf("id" to selected)).opt("data")); val result = productConfigRows(EntityDetails.objectValue(data.opt("config_data"))); check(result.isNotEmpty()) { "暂无参数配置" }; cache[selected] = result }
        catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message }
        finally { loading = false }
    }
    Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { configs.forEach { config -> com.green.note.ui.ReviewChoiceChip(selected == config.text("id"), onClick = { onSelect(config.text("id")) }, label = { Text(config.text("title")) }) } }
        if (loading || error != null || params.isEmpty()) LoadingFailure(loading, error, if (params.isEmpty()) "暂无参数" else "") { attempt++ }
        params.forEach { (name, value) ->
            if (value == null) Text(name, Modifier.padding(top = 20.dp, bottom = 8.dp), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            else { Row(Modifier.fillMaxWidth().padding(vertical = 12.dp)) { Text(name, Modifier.width(110.dp), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(16.dp)); Text(value, Modifier.weight(1f), fontSize = 13.sp) }; HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .4f)) }
        }
    }
}

internal data class ProductSelectorResult(val items: List<JSONObject>, val filters: List<JSONObject>, val sorts: Map<String, String>, val subScores: Map<String, String>)
internal class NativeProductSource {
    private val client = OkHttpClient.Builder().followRedirects(false).connectTimeout(15, TimeUnit.SECONDS).readTimeout(25, TimeUnit.SECONDS).callTimeout(35, TimeUnit.SECONDS).build()
    private val lifecycle = com.green.note.account.HttpSessionLifecycle(client, { client.connectionPool.evictAll() })
    var configuration: ProductSelectorResult? = null
        private set
    fun close() { lifecycle.close() }
    suspend fun load(page: Int, keyword: String, sort: String, filters: Map<String, List<String>>): ProductSelectorResult = withContext(Dispatchers.IO) {
        val base = "https://m.coolapk.com/mp/productSelector/configSearch".toHttpUrlOrNull()!!
        fun fetch(request: Request): String = lifecycle.readResponse(request.newBuilder().header("User-Agent", "Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36").build()) {
            check(it.isSuccessful) { "无法读取机型" }
            val body = it.body?.source() ?: error("选机中心返回空数据")
            require(!body.request(8L * 1024 * 1024 + 1)) { "选机中心响应过大" }; body.readUtf8()
        }
        if (configuration == null) {
            configuration = parse(fetch(Request.Builder().url(base.newBuilder().addQueryParameter("callFunction", "indexSearch").build()).build()))
            check(configuration!!.sorts.isNotEmpty()) { "选机中心页面结构已变化，请稍后重试" }
            if (page == 1 && keyword.isEmpty() && sort == "default" && filters.isEmpty()) return@withContext configuration!!
        }
        val form = FormBody.Builder().apply { filters.forEach { (key, values) -> values.forEachIndexed { index, value -> add("selectedFilters[$key][$index]", value) } } }.build()
        val root = JSONObject(fetch(Request.Builder().url(base.newBuilder().addQueryParameter("page", "$page").addQueryParameter("keyWord", keyword).addQueryParameter("sortValue", sort).build()).header("X-Requested-With", "XMLHttpRequest").post(form).build()))
        check(root.optInt("status", 200) in listOf(0, 200)) { root.optString("message", "无法读取机型") }
        check(root.opt("data") is String) { "选机中心返回了无法识别的数据" }
        parse(root.getString("data"))
    }
    companion object {
        fun parse(source: String): ProductSelectorResult {
            val document = Jsoup.parse(source)
            fun clean(value: String) = value.replace(Regex("\\s+"), " ").trim()
            val rows = document.select(".phone-item[data-product-id]").map { row -> JSONObject().put("id", row.attr("data-product-id")).put("title", clean(row.selectFirst(".phone-name")?.text().orEmpty()))
                .put("pic", row.selectFirst(".phone-image img")?.attr("src").orEmpty()).put("specs", clean(row.selectFirst(".phone-specs")?.text().orEmpty()))
                .put("price", clean(row.selectFirst(".phone-price")?.text().orEmpty()).replace(" ", ""))
                .put("tags", JSONArray(row.select(".phone-specs-tags .tag-item").map { clean(it.text()) })) }.filter { it.text("title").isNotEmpty() }
            val filters = document.select(".filter-section[data-group]").mapNotNull { group ->
                val title = group.selectFirst(".filter-section-title")?.clone()?.apply { select("svg,.expand-button").remove() }?.text().orEmpty()
                val options = group.select(".filter-modal-item[data]").map { JSONObject().put("title", clean(it.text())).put("value", it.attr("data")) }
                if (options.isEmpty()) null else JSONObject().put("id", group.attr("data-group")).put("title", clean(title)).put("options", JSONArray(options))
            }
            return ProductSelectorResult(rows, filters, document.select(".filter-item[data]").filter { it.attr("data") != "child" }.associate { it.attr("data") to clean(it.text()) }, document.select(".modal-item[data]").associate { it.attr("data") to clean(it.text()) })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun NativeProductSelector(api: ContentApi, onBack: () -> Unit, onSelected: (JSONObject) -> Unit) {
    val source = remember { NativeProductSource() }
    DisposableEffect(source) { onDispose { source.close() } }
    var query by remember { mutableStateOf("") }
    var sort by remember { mutableStateOf("default") }
    var filters by remember { mutableStateOf<Map<String, List<String>>>(emptyMap()) }
    var configuration by remember { mutableStateOf<ProductSelectorResult?>(null) }
    var filterGroup by remember { mutableStateOf<String?>(null) }
    var draft by remember { mutableStateOf<Map<String, List<String>>>(emptyMap()) }
    var subSort by remember { mutableStateOf(false) }
    var compared by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var compare by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val scroll = rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    val state = remember(source, query, sort, filters) { ContentListState { page, _, _ ->
        val value = source.load(page, query.trim(), sort, filters); configuration = source.configuration
        ContentPage(value.items, page, "", "", value.items.isNotEmpty())
    } }
    LaunchedEffect(state) { delay(350); state.load(true) }
    LaunchedEffect(state, scroll) { snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect { if (state.rows.isNotEmpty() && it >= state.rows.size - 3 && state.error == null) state.load() } }
    BackHandler { onBack() }
    if (compare) { NativeProductComparison(api, compared.firstOrNull() ?: JSONObject(), onBack = { compare = false }, initialProducts = compared); return }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.fillMaxWidth().height(34.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .06f), RoundedCornerShape(8.dp)), verticalAlignment = Alignment.CenterVertically) {
                com.green.note.ui.ReviewIconButton(onClick = onBack) { MaterialGlyph("arrow_back_rounded") }
                com.green.note.ui.ReviewBasicTextField(query, onValueChange = { query = it }, modifier = Modifier.weight(1f), singleLine = true, textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface), decorationBox = { inner -> if (query.isEmpty()) Text("搜索机型", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant); inner() })
                com.green.note.ui.ReviewIconButton(onClick = { scope.launch { state.load(true) } }) { MaterialGlyph("search_rounded") }
            }
        }
        Row(Modifier.height(44.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            (configuration?.sorts ?: mapOf("default" to "综合", "hot_num" to "热度", "owner_star_average_score" to "评分", "follow_num" to "关注数")).forEach { (key, title) -> com.green.note.ui.ReviewTextButton(onClick = { sort = key }) { Text(title, color = if (sort == key) Color(0xff009688) else MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp) } }
            Box { com.green.note.ui.ReviewTextButton(onClick = { subSort = true }) { Text("子项分"); MaterialGlyph("arrow_drop_down", size = 18.dp) }; com.green.note.ui.ReviewPopupMenu(subSort, onDismissRequest = { subSort = false }) { configuration?.subScores?.forEach { (key, title) -> com.green.note.ui.ReviewPopupMenuItem(text = { Text(title) }, onClick = { sort = key; subSort = false }) } } }
            com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = { if (!configuration?.filters.isNullOrEmpty()) { draft = filters.mapValues { it.value.toList() }; filterGroup = "" } }, enabled = configuration != null) { MaterialGlyph("filter_alt_outlined", size = 18.dp); com.green.note.ui.ReviewButtonIconGap(); Text("筛选") }
        }
        Row(Modifier.height(40.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("price" to "价格", "brand_id" to "品牌", "1012" to "发布时间", "1034" to "SoC型号", "1109" to "电池容量").forEach { (key, title) ->
                Row(Modifier.fillMaxHeight().background(MaterialTheme.colorScheme.onSurface.copy(alpha = .06f), RoundedCornerShape(6.dp)).clickable { if (configuration?.filters.orEmpty().any { it.text("id") == key }) { draft = filters.mapValues { it.value.toList() }; filterGroup = key } }.padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically) { Text(title, color = if (filters[key].isNullOrEmpty()) MaterialTheme.colorScheme.onSurfaceVariant else Color(0xff009688), fontSize = 14.sp); MaterialGlyph("expand_more", size = 16.dp) }
            }
        }
        Box(Modifier.weight(1f)) {
            ReviewRefreshBox(isRefreshing = state.refreshing, failed = state.error != null, onRefresh = { scope.launch { state.load(true) } }) {
                LazyColumn(Modifier.fillMaxSize(), state = scroll, contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 84.dp)) {
                    items(state.rows, key = { it.text("id") }) { row ->
                        Row(Modifier.fillMaxWidth().clickable { onSelected(row) }.padding(horizontal = 8.dp, vertical = 12.dp), verticalAlignment = Alignment.Top) {
                            EntityImage(api, row.text("pic"), Modifier.padding(top = 8.dp).size(56.dp, 64.dp), ContentScale.Fit) { MaterialGlyph("phone_android_outlined") }; Spacer(Modifier.width(20.dp))
                            Column(Modifier.weight(1f)) {
                                Text(row.text("title"), fontSize = 16.sp, fontWeight = FontWeight.Medium); Spacer(Modifier.height(6.dp))
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { EntityDetails.values(row, "tags").forEach { tag -> val color = if (tag.contains("新品")) Color.Red else if (tag.startsWith("评分")) Color(0xffad80eb) else Color(0xff2196f3); Text(tag, Modifier.background(color.copy(alpha = .14f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 3.dp), color = color, fontSize = 10.sp) } }
                                Spacer(Modifier.height(8.dp)); Text(row.text("specs"), fontSize = 12.sp, lineHeight = 18.sp, color = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.height(8.dp))
                                Row(verticalAlignment = Alignment.CenterVertically) { Text(row.text("price"), Modifier.weight(1f), color = Color(0xfff44336), fontSize = 18.sp, fontWeight = FontWeight.Medium)
                                    val chosen = compared.any { it.text("id") == row.text("id") }
                                    com.green.note.ui.ReviewOutlinedButton(onClick = { if (chosen) compared = compared.filterNot { it.text("id") == row.text("id") } else if (compared.size < 4) compared = compared + row else com.green.note.ui.AppToastState().showSnackbar("最多同时对比四款机型") }, modifier = Modifier.height(28.dp), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp)) { Text(if (chosen) "已添加" else "＋对比", fontSize = 11.sp) }
                                }
                            }
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .4f))
                    }
                    item { Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) { when { state.busy -> com.green.note.ui.ReviewCircularProgress(); state.error != null -> com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.load(state.rows.isEmpty()) } }) { Text(state.error.orEmpty()) }; state.rows.isEmpty() -> Text("暂无符合筛选条件的机型") } } }
                }
            }
            FloatingActionButton(onClick = com.green.note.ui.rememberHapticClick { compare = true }, Modifier.align(Alignment.BottomEnd).padding(16.dp), containerColor = Color(0xff009688)) { Text(if (compared.isEmpty()) "PK" else "PK ${compared.size}", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black) }
        }
    }
    filterGroup?.let { only ->
        val groups = configuration?.filters.orEmpty().filter { only.isEmpty() || it.text("id") == only }
        val filtersScroll = rememberScrollState()
        com.green.note.ui.ReviewScrollActivity(filtersScroll)
        com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { filterGroup = null }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            Column(Modifier.fillMaxWidth().height(with(androidx.compose.ui.platform.LocalDensity.current) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.height.toDp() * .75f })) {
                Text(if (only.isEmpty()) "筛选机型" else groups.firstOrNull()?.text("title").orEmpty(), Modifier.align(Alignment.CenterHorizontally).padding(12.dp), fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                Column(Modifier.weight(1f).verticalScroll(filtersScroll).padding(horizontal = 16.dp)) { groups.forEach { group ->
                    Text(group.text("title"), Modifier.padding(vertical = 10.dp), fontWeight = FontWeight.SemiBold)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { group.optJSONArray("options").objects().forEach { option ->
                        val key = group.text("id"); val value = option.text("value"); val selected = draft[key].orEmpty().contains(value)
                        com.green.note.ui.ReviewFilterChip(selected, onClick = { val values = if (selected) draft[key].orEmpty() - value else draft[key].orEmpty() + value; draft = if (values.isEmpty()) draft - key else draft + (key to values) }, label = { Text(option.text("title")) })
                    } }
                } }
                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) { com.green.note.ui.ReviewOutlinedButton(onClick = { draft = if (only.isEmpty()) emptyMap() else draft - only }, Modifier.weight(1f)) { Text("重置") }; com.green.note.ui.ReviewButton(onClick = { filters = draft; filterGroup = null }, Modifier.weight(1f)) { Text("确定") } }
            }
        }
    }
}

@Stable
private class ComparedProduct(initial: JSONObject) {
    val id = initial.text("id")
    var detail by mutableStateOf(initial)
    var configId by mutableStateOf("")
    var configName by mutableStateOf("")
    var price by mutableStateOf(initial.text("price", "price_str"))
    var specs by mutableStateOf(comparisonSpecs(initial, JSONObject()))
    var busy by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var generation = 0
}

internal fun comparisonSpecs(raw: JSONObject, config: JSONObject): Map<String, Map<String, String>> {
    val details = linkedMapOf<String, Map<String, String>>()
    config.keys().forEach { group -> val values = config.optJSONObject(group) ?: return@forEach
        val rows = productConfigRows(values).mapNotNull { (key, value) -> value?.let { key to it } }.toMap(); if (rows.isNotEmpty()) details[group] = rows
    }
    val flat = details.values.flatMap { it.entries }.associate { it.key to it.value }
    fun field(vararg keys: String): String = keys.firstNotNullOfOrNull { key -> flat[key]?.takeIf { it.isNotBlank() && it != "-" } }
        ?: productSpecValue(config, keys.toList()).ifEmpty { productSpecValue(raw, keys.toList()) }
    fun join(vararg values: String) = values.filter { it.isNotBlank() && it != "-" }.joinToString("\n")
    val basics = linkedMapOf(
        "性能" to linkedMapOf("芯片" to field("芯片", "处理器", "CPU型号", "CPU", "chip", "soc", "processor"), "RAM & ROM" to join(field("运行内存", "RAM", "ram"), field("机身存储", "ROM", "rom"))),
        "屏幕" to linkedMapOf("屏幕" to join(field("屏幕尺寸", "screen_size", "screen"), field("屏幕刷新率", "刷新率", "screen_refresh_rate"), field("分辨率", "screen_resolution"), field("屏幕材质", "屏幕类型", "screen_type"))),
        "影像" to linkedMapOf("影像联名" to field("影像联名", "camera_brand"), "后置主摄" to field("后置摄像头", "后置主摄", "main_camera", "camera")),
        "续航" to linkedMapOf("电池" to field("电池容量", "battery"), "充电" to field("有线充电", "充电功率", "快充", "charging")),
        "机身" to linkedMapOf("机身规格" to join(field("厚度", "thickness"), field("重量", "weight"))),
        "其他" to linkedMapOf("特色功能" to field("特色功能", "features"))
    )
    val result = linkedMapOf<String, Map<String, String>>()
    basics.forEach { (group, rows) -> result[group] = rows }
    details.forEach { (group, rows) -> result[group] = (result[group] ?: emptyMap()) + rows }
    return result
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NativeProductComparison(api: ContentApi, initial: JSONObject, onBack: () -> Unit, initialProducts: List<JSONObject> = emptyList()) {
    val products = remember { mutableStateListOf<ComparedProduct>().apply { (initialProducts.ifEmpty { listOf(initial) }).filter { it.text("id").isNotEmpty() }.distinctBy { it.text("id") }.take(4).forEach { add(ComparedProduct(it)) } } }
    var hideSame by remember { mutableStateOf(false) }
    var selector by remember { mutableStateOf(false) }
    var picker by remember { mutableStateOf<ComparedProduct?>(null) }
    val horizontal = com.green.note.ui.rememberReviewScrollState()
    val vertical = rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(vertical)
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val view = LocalView.current
    var shareBusy by remember { mutableStateOf(false) }
    val background = Color(0xff141416)
    fun chooseConfiguration(product: ComparedProduct) {
        if (product.detail.optJSONArray("configRows").objects().isEmpty()) com.green.note.ui.AppToastState().showSnackbar("当前机型暂无其他配置版本")
        else picker = product
    }
    suspend fun loadConfig(product: ComparedProduct, id: String) {
        val generation = ++product.generation
        product.configId = id; product.configName = product.detail.optJSONArray("configRows").objects().firstOrNull { it.text("id") == id }?.text("title").orEmpty(); product.busy = true; product.error = null
        try {
            val root = EntityDetails.objectValue(api.request("/v6/product/config", query = mapOf("id" to id)).opt("data"))
            check(root.length() > 0) { "暂无参数配置" }
            if (generation == product.generation && products.contains(product)) { product.specs = comparisonSpecs(product.detail, EntityDetails.objectValue(root.opt("config_data"))); root.text("price").takeIf(String::isNotEmpty)?.let { product.price = it } }
        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { if (generation == product.generation) product.error = failure.message }
        finally { if (generation == product.generation) product.busy = false }
    }
    suspend fun load(product: ComparedProduct) {
        product.busy = true
        try {
            val detail = EntityDetails.objectValue(api.request("/v6/product/detail", query = mapOf("id" to product.id)).opt("data"))
            if (!products.contains(product)) return
            if (detail.length() > 0) { product.detail = detail; product.specs = comparisonSpecs(detail, JSONObject()); product.price = detail.text("price", "price_str") }
            val config = product.detail.optJSONArray("configRows").objects().firstOrNull()?.text("id")
            if (!config.isNullOrEmpty()) loadConfig(product, config)
        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { product.error = failure.message }
        finally { product.busy = false }
    }
    LaunchedEffect(Unit) { products.toList().forEach { product -> launch { load(product) } } }
    BackHandler { if (selector) selector = false else onBack() }
    if (selector) { NativeProductSelector(api, onBack = { selector = false }, onSelected = { row ->
        selector = false
        if (products.none { it.id == row.text("id") } && products.size < 4) { val product = ComparedProduct(row); products.add(product); scope.launch { load(product) } }
        else com.green.note.ui.AppToastState().showSnackbar("该机型已在对比列表中")
    }); return }
    Column(Modifier.fillMaxSize().background(background)) {
        Row(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick = onBack, modifier = Modifier.width(56.dp)) { MaterialGlyph("close_rounded", color = Color.White) }; Spacer(Modifier.width(16.dp)); Text("配置对比", Modifier.weight(1f), color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold)
            com.green.note.ui.ReviewIconButton(onClick = { if (!shareBusy) scope.launch {
                shareBusy = true
                try {
                    val bitmap = android.graphics.Bitmap.createBitmap(view.width, view.height, android.graphics.Bitmap.Config.ARGB_8888)
                    view.draw(android.graphics.Canvas(bitmap))
                    val file = try { withContext(Dispatchers.IO) { val directory = java.io.File(context.cacheDir, "compose-share").apply { mkdirs() }; java.io.File(directory, "comparison-${System.currentTimeMillis()}.png").also { output -> output.outputStream().use { check(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)) } } } } finally { bitmap.recycle() }
                    val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.apk_files", file)
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "分享机型对比"))
                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("无法生成机型对比截图") }
                finally { shareBusy = false }
            } }, enabled = !shareBusy) { MaterialGlyph("ios_share_rounded", color = Color.White, size = 22.dp) }
        }
        Row(Modifier.fillMaxWidth().height(228.dp).padding(top = 8.dp, bottom = 14.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.width(90.dp).padding(start = 12.dp, end = 8.dp, top = 18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                ComparisonSwitch(hideSame) { hideSame = it }
                Spacer(Modifier.height(10.dp)); Text("隐藏相同配置", color = Color.White.copy(alpha = .7f), fontSize = 12.sp, textAlign = TextAlign.Center); Spacer(Modifier.height(6.dp)); Text(if (products.isEmpty()) "暂无对比机型" else "${products.size}款配置对比", color = Color.White.copy(alpha = .38f), fontSize = 11.sp, textAlign = TextAlign.Center)
            }
            Row(Modifier.weight(1f).horizontalScroll(horizontal)) {
                products.forEach { product -> Column(Modifier.width(172.dp).padding(horizontal = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopEnd) { MaterialGlyph("close", Modifier.clickable { product.generation++; products.remove(product) }.padding(start = 4.dp, end = 4.dp, bottom = 4.dp), size = 16.dp, color = Color.White.copy(alpha = .38f)) }
                    EntityImage(api, product.detail.text("logo", "cover", "pic"), Modifier.height(84.dp), ContentScale.Fit) { MaterialGlyph("phone_android_rounded", size = 64.dp, color = Color.White.copy(alpha = .3f)) }; Spacer(Modifier.height(10.dp))
                    Column(Modifier.width(150.dp).background(Color(0xff262628), RoundedCornerShape(8.dp)).clickable { chooseConfiguration(product) }.padding(horizontal = 8.dp, vertical = 7.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(product.detail.text("title"), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(product.configName.ifEmpty { "默认配置" }, color = Color.White.copy(alpha = .7f), fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Spacer(Modifier.height(8.dp)); Row(verticalAlignment = Alignment.CenterVertically) { Text(product.price.let { if (it.isEmpty()) "—" else if (it.startsWith("¥")) it else "¥$it" }, color = Color(0xffe54d42), fontSize = 16.sp, fontWeight = FontWeight.Bold); Spacer(Modifier.width(8.dp)); MaterialGlyph("swap_horiz_rounded", Modifier.clickable { chooseConfiguration(product) }, size = 18.dp, color = Color.White.copy(alpha = .54f)) }
                } }
                if (products.size < 4) Column(Modifier.padding(start = 8.dp, top = 20.dp, end = 16.dp).size(120.dp, 168.dp).background(Color(0xff1a1a1c), RoundedCornerShape(12.dp)).border(1.5.dp, Color(0xff38383a), RoundedCornerShape(12.dp)).clickable { selector = true }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) { MaterialGlyph("add_rounded", size = 36.dp, color = Color.White.copy(alpha = .54f)); Spacer(Modifier.height(8.dp)); Text("添加对比", color = Color.White.copy(alpha = .7f), fontSize = 13.sp, fontWeight = FontWeight.Medium) }
            }
        }
        HorizontalDivider(color = Color.White.copy(alpha = .12f))
        val groups = products.flatMap { it.specs.keys }.distinct()
        val reverseHorizontal = androidx.compose.ui.platform.LocalLayoutDirection.current == androidx.compose.ui.unit.LayoutDirection.Ltr
        LazyColumn(Modifier.weight(1f).scrollable(horizontal, Orientation.Horizontal, reverseDirection = reverseHorizontal), state = vertical, contentPadding = PaddingValues(bottom = 40.dp)) {
            if (products.isEmpty()) item { Text("点击上方“添加对比”选择机型", Modifier.fillMaxWidth().padding(vertical = 60.dp), color = Color.White.copy(alpha = .38f), fontSize = 14.sp, textAlign = TextAlign.Center) }
            else {
                item { Text("重要参数", Modifier.padding(start = 16.dp, top = 20.dp, end = 16.dp, bottom = 6.dp), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold) }
                groups.forEachIndexed { groupIndex, group ->
                    if (groupIndex == 6) item { Text("详细参数", Modifier.padding(start = 16.dp, top = 24.dp, end = 16.dp, bottom = 6.dp), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold) }
                    val keys = products.flatMap { it.specs[group].orEmpty().keys }.distinct().filter { key ->
                        val values = products.map { it.specs[group]?.get(key).orEmpty().trim() }
                        values.any { it.isNotEmpty() && it != "-" } && (!hideSame || products.size <= 1 || values.distinct().size > 1)
                    }
                    if (keys.isNotEmpty()) {
                        item { Text(group, Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 8.dp), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold) }
                        keys.forEach { key -> item {
                            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                                Text(key, Modifier.width(90.dp).padding(horizontal = 14.dp, vertical = 12.dp), color = Color.White.copy(alpha = .54f), fontSize = 13.sp, lineHeight = 17.55.sp)
                                Box(Modifier.weight(1f).clipToBounds()) { Row(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).width((products.size * 172 + if (products.size < 4) 140 else 0).dp).graphicsLayer { translationX = -horizontal.value.toFloat() }) {
                                    products.forEach { product -> Text(product.specs[group]?.get(key).orEmpty().ifEmpty { "-" }, Modifier.width(172.dp).padding(horizontal = 12.dp, vertical = 12.dp), color = Color.White, fontSize = 13.sp, lineHeight = 18.85.sp) }
                                } }
                            }
                            HorizontalDivider(color = Color.White.copy(alpha = .08f), thickness = .5.dp)
                        } }
                    }
                }
                products.filter { it.error != null || it.busy }.forEach { product -> item { LoadingFailure(product.busy, product.error, "") { scope.launch { load(product) } } } }
            }
        }
    }
    picker?.let { product -> com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { picker = null }, containerColor = Color(0xff1e1e22), contentColor = Color.White, shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)) {
        Text("选择 ${product.detail.text("title")} 配置版本", Modifier.padding(start = 20.dp, top = 16.dp, end = 20.dp, bottom = 8.dp), color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        HorizontalDivider(color = Color.White.copy(alpha = .12f))
        product.detail.optJSONArray("configRows").objects().forEach { config ->
            val selected = product.configId == config.text("id")
            ListItem(headlineContent = { Text(config.text("title"), color = if (selected) Color(0xff00b074) else Color.White, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal) }, trailingContent = { if (selected) MaterialGlyph("check_rounded", color = Color(0xff00b074)) }, modifier = Modifier.clickable { picker = null; scope.launch { loadConfig(product, config.text("id")) } }, colors = ListItemDefaults.colors(containerColor = Color.Transparent))
        }
        Spacer(Modifier.height(12.dp))
    } }
}

@Composable
private fun ComparisonSwitch(checked: Boolean, onChecked: (Boolean) -> Unit) {
    val fraction by androidx.compose.animation.core.animateFloatAsState(if (checked) 1f else 0f, androidx.compose.animation.core.tween(200), label = "comparison-switch")
    androidx.compose.foundation.Canvas(Modifier.size(51.dp, 31.dp).graphicsLayer { scaleX = .8f; scaleY = .8f }
        .toggleable(value = checked, role = androidx.compose.ui.semantics.Role.Switch, onValueChange = onChecked)) {
        val radius = size.height / 2
        drawRoundRect(lerp(Color(0xff2c2c2e), Color(0xff00b074), fraction), cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius))
        val center = androidx.compose.ui.geometry.Offset(radius + (size.width - size.height) * fraction, radius)
        drawCircle(Color.Black.copy(alpha = .16f), radius - 1.dp.toPx(), center.copy(y = center.y + 1.dp.toPx()))
        drawCircle(Color.White, radius - 2.dp.toPx(), center)
    }
}

@Composable
private fun EntityImage(api: ContentApi, url: String, modifier: Modifier, scale: ContentScale = ContentScale.Crop, showLoading: Boolean = true, fallback: @Composable () -> Unit) {
    var failed by remember(url, api.imageCacheScope()) { mutableStateOf(url.isBlank()) }
    Box(modifier, contentAlignment = Alignment.Center) {
        if (failed) fallback()
        if (url.isNotBlank()) ContentImage(api, url, null, Modifier.fillMaxSize(), scale, onError = { failed = true }, onDecoded = { _, _ -> failed = false }, showLoading = showLoading)
    }
}
