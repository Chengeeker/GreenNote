package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun homeTopicTarget(value: String, title: String): ContentRequest {
    var raw = value.trim().removePrefix("/page?url=")
    if ('%' in raw) raw = runCatching { java.net.URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8") }.getOrDefault(raw)
    return ContentRequest("/v6/page/dataList", mapOf("url" to raw) + if (title.isEmpty()) emptyMap() else mapOf("title" to title))
}

internal fun homeTopicHeat(row: JSONObject): String {
    val raw = row.text("hotNumTxt", "hot_num_txt", "hot_num", "hotNum").replace("热度", "").trim()
    val number = raw.toDoubleOrNull()
    return if (number != null && number >= 10000) String.format(java.util.Locale.ROOT, "%.1f万", number / 10000) else raw
}

@Stable
internal class HomeTopicState(private val api: ContentApi) {
    private val owner = api.imageCacheScope()
    var topics by mutableStateOf<List<JSONObject>?>(null); private set
    var error by mutableStateOf<String?>(null); private set
    var selected by mutableIntStateOf(1)
    val leftScroll = androidx.compose.foundation.lazy.LazyListState()
    private var gridRequest: ContentRequest? = null
    private var gridState: ContentListState? = null
    var gridScroll = androidx.compose.foundation.lazy.LazyListState(); private set
    fun grid(request: ContentRequest): ContentListState {
        if (gridRequest != request) {
            gridRequest = request; gridScroll = androidx.compose.foundation.lazy.LazyListState()
            gridState = ContentListState { page, first, last ->
                val result = ContentRepository(api).page(request, page, first, last)
                result.copy(rows = result.rows.filter { it.text("title", "name", "tag", "tagName").isNotEmpty() })
            }
        }
        return checkNotNull(gridState)
    }
    suspend fun load() {
        topics = null; error = null
        try {
            val loaded = ContentRepository(api).page(ContentRequest("/v6/page/dataList", mapOf("url" to "V11_VERTICAL_TOPIC", "title" to "话题")), 1)
            if (owner != api.imageCacheScope()) return
            topics = loaded.rows.flatMap { it.optJSONArray("entities").objects() }.filter { it.has("title") && !it.isNull("title") && it.has("url") && !it.isNull("url") }
            if (topics.isNullOrEmpty()) error = "酷安没有返回话题分区"
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: failure.toString() }
    }
}

@Composable
internal fun HomeTopicScreen(api: ContentApi, onOpen: (JSONObject) -> Unit, state: HomeTopicState? = null) {
    val owner = api.imageCacheScope()
    val retained = state ?: remember(api, owner) { HomeTopicState(api) }
    val topics = retained.topics; val error = retained.error
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(retained, attempt) { if (attempt > 0 || retained.topics == null && retained.error == null) retained.load() }
    val entries = topics
    if (error != null || entries == null || entries.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            if (error == null) ReviewCircularProgress()
            else Column(Modifier.padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                MaterialGlyph("cloud_off_outlined", size = 38.dp, color = MaterialTheme.colorScheme.outline)
                Spacer(Modifier.height(12.dp)); Text(error.orEmpty(), textAlign = TextAlign.Center)
                Spacer(Modifier.height(14.dp)); com.green.note.ui.ReviewFilledTonalButton(onClick = { attempt++ }) { Text("重试") }
            }
        }
        return
    }
    val index = retained.selected.coerceIn(0, entries.lastIndex)
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.surface.luminance() < .5f
    val panel = if (dark) Color(0xff1e1e1e) else scheme.surface
    val gutter = if (dark) Color(0xff101010) else scheme.surfaceContainerLow
    val leftScroll = retained.leftScroll
    ReviewScrollActivity(leftScroll)
    Row(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.width(84.dp).fillMaxHeight().background(panel), state = leftScroll) {
            itemsIndexed(entries) { position, item ->
                Box(Modifier.fillMaxWidth().heightIn(min = 43.dp).background(if (position == index) gutter else Color.Transparent)
                    .drawBehind { if (position == index) drawRect(scheme.primary, size = Size(3.dp.toPx(), size.height)) }
                    .clickable { retained.selected = position }, contentAlignment = Alignment.Center) {
                    Text(item.text("title"), Modifier.padding(start = 9.dp, end = 6.dp, top = 10.dp, bottom = 10.dp), fontSize = 14.sp, lineHeight = 16.8.sp,
                        textAlign = TextAlign.Center, color = if (position == index) scheme.primary else LocalContentColor.current)
                }
            }
        }
        val request = homeTopicTarget(entries[index].text("url"), entries[index].text("title"))
        val grid = retained.grid(request)
        key(request, owner) { HomeTopicGrid(api, grid, retained.gridScroll, onOpen,
            Modifier.weight(1f).fillMaxHeight().background(gutter).padding(start = 8.dp, top = 8.dp, end = 8.dp).clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)).background(panel)) }
    }
}

@Composable
private fun HomeTopicGrid(api: ContentApi, state: ContentListState, scroll: androidx.compose.foundation.lazy.LazyListState, onOpen: (JSONObject) -> Unit, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    ReviewScrollActivity(scroll)
    val window = LocalWindowInfo.current.containerSize
    val emptyHeight = with(LocalDensity.current) { (window.height * .2f).toDp() }
    val refreshWidth = with(LocalDensity.current) { window.width.toDp() } - 80.dp
    LaunchedEffect(state) { if (state.needsInitialLoad && state.error == null) state.load() }
    LaunchedEffect(state, scroll) { snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect { row ->
        if (state.rows.isNotEmpty() && row * 3 >= state.rows.size - 9 && state.error == null) state.load()
    } }
    ReviewRefreshBox(state.refreshing, { scope.launch { state.load(true) } }, modifier, failed = state.error != null, showText = false, textDimension = refreshWidth) {
        LazyColumn(Modifier.fillMaxSize(), state = scroll, contentPadding = PaddingValues(start = 8.dp, end = 8.dp, bottom = 96.dp)) {
            itemsIndexed(state.rows.chunked(3), key = { _, items -> entityKey(items.first()) }) { _, items ->
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                    items.forEach { item -> HomeTopicTile(api, item, onOpen, Modifier.weight(1f).fillMaxHeight()) }
                    repeat(3 - items.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            item {
                if (state.rows.isEmpty()) Box(Modifier.fillMaxWidth().height(emptyHeight), contentAlignment = Alignment.Center) {
                    if (state.busy) ReviewCircularProgress() else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error ?: "暂无内容")
                        if (state.error != null) com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.load(true) } }) { Text("重试") }
                    }
                } else if (state.busy) Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { ReviewCircularProgress() }
                else if (state.error != null && !isContentAccessError(state.error)) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.load() } }) { Text("加载失败，点击重试：${state.error}") }
                }
            }
        }
    }
}

@Composable
private fun HomeTopicTile(api: ContentApi, row: JSONObject, onOpen: (JSONObject) -> Unit, modifier: Modifier) {
    val title = row.text("title", "name", "tag", "tagName")
    val logo = row.text("logo", "icon", "pic", "avatar")
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.surface.luminance() < .5f
    val muted = if (dark) Color(0xffb8b8b8) else scheme.onSurfaceVariant
    var failed by remember(logo, api.imageCacheScope()) { mutableStateOf(false) }
    Column(modifier.clickable { val tag = todayTopicTag(row); if (tag.isNotEmpty()) onOpen(JSONObject(row.toString()).put("entityType", "topic").put("tag", tag)) }
        .padding(start = 4.dp, top = 12.dp, end = 4.dp, bottom = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(56.dp).clip(RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            if (logo.isEmpty() || failed) MaterialGlyph("tag", color = scheme.onSurfaceVariant)
            else ContentImage(api, logo, title, Modifier.fillMaxSize(), heroCornerRadius = 10.dp, onError = { failed = true })
        }
        Spacer(Modifier.height(10.dp))
        Text(title, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, fontSize = 14.sp, lineHeight = 16.8.sp,
            color = if (dark) Color(0xffd0d0d0) else scheme.onSurface)
        Spacer(Modifier.weight(1f)); Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            MaterialGlyph("local_fire_department_outlined", size = 11.dp, color = muted)
            Text(homeTopicHeat(row).ifEmpty { "暂无热度" }, Modifier.weight(1f, fill = false), maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 11.sp, lineHeight = 13.2.sp, color = muted)
        }
    }
}
