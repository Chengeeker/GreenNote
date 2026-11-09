package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.rememberReviewScrollState
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

internal data class HomeChannel(val id: String, val title: String, val route: String)
internal val defaultHomeChannels = listOf(
    HomeChannel("topic", "话题", "/page?url=V11_VERTICAL_TOPIC&title=话题"), HomeChannel("follow", "关注", "/page?url=V15_HOME_TAB_FOLLOW"),
    HomeChannel("headline", "头条", "/v6/main/headline"), HomeChannel("hot", "热榜", "/page?url=V9_HOME_TAB_RANKING"),
    HomeChannel("tutorial", "教程", "/page?url=V11_HOME_TAB_JC"), HomeChannel("video", "视频", "/page?url=V9_HOME_TAB_SHIPIN"))
internal val moreHomeChannels = listOf(
    HomeChannel("news", "快讯", "/page?url=V11_HOME_TAB_NEWS"), HomeChannel("new_device", "新机", "/page?url=V11_HOME_NEW"),
    HomeChannel("car", "汽车", "/page?url=V11_HOME_CAR"), HomeChannel("unboxing", "开箱", "/page?url=V13_IOSHOME_OPENSHOW"),
    HomeChannel("photo", "摄影", "/page?url=V13_HOME_SHEYING"), HomeChannel("game", "游戏", "/page?url=V15_YOUXI"),
    HomeChannel("peripherals", "外设", "/page?url=V14_WAISHE"), HomeChannel("theme", "美化", "/page?url=V11_HOME_MEIHUA"),
    HomeChannel("live", "直播", "/page?url=V9_HOME_TAB_LIVE"), HomeChannel("qa", "问答", "/page?url=V9_HOME_TAB_WENDA"),
    HomeChannel("coupons", "神券", "/page?url=V11_FIND_GOODS"), HomeChannel("latest", "最新", "#/feed/newestList"),
    HomeChannel("digest", "精选", "#/feed/digestList?type=1"), HomeChannel("picture", "酷图", "#/feed/coolPictureRankList"),
    HomeChannel("editor", "编辑精选", "#/feed/editorChoiceList"), HomeChannel("questions", "问答", "#/feed/myQaFeedList"))
internal val allHomeChannels = (defaultHomeChannels + moreHomeChannels).associateBy(HomeChannel::id)
internal fun restoreHomeChannels(ids: List<String>) = ids.distinct().mapNotNull(allHomeChannels::get).ifEmpty { defaultHomeChannels }

internal data class MainTabRoutes(val home: Map<String, String>, val discovery: Map<String, String>)
internal fun parseMainTabRoutes(root: JSONObject): MainTabRoutes {
    val home = linkedMapOf<String, String>(); val discovery = linkedMapOf<String, String>()
    var homeSeen = false; var discoverySeen = false
    val names = (defaultHomeChannels + moreHomeChannels.take(11)).associate { it.title to it.id }
    root.optJSONArray("data").objects().forEach { row ->
        if (!homeSeen && row.text("title") in setOf("首页TAB配置", "首页")) { homeSeen = true; row.optJSONArray("entities").objects().forEach { entry ->
            val id = names[entry.text("title")]; val route = entry.text("url")
            if (id != null && route.isNotEmpty()) home[id] = if (id == "headline" || route == "/main/headline") "/v6/main/headline" else route
        } }
        if (!discoverySeen && row.text("title") in setOf("发现", "发现TAB配置")) { discoverySeen = true; row.optJSONArray("entities").objects().forEach { entry ->
            val title = entry.text("title").let { if (it == "好物") "好物榜" else it }
            val route = entry.text("url", "page_name")
            if (title in setOf("酷品", "生活", "二手", "酷图", "宠物", "运动", "看看号", "商家", "好物榜") && route.isNotEmpty()) discovery[title] = route
        } }
    }
    return MainTabRoutes(home, discovery)
}

@Stable
internal class HomeChannelState(private val context: Context, private val scope: CoroutineScope) {
    var channels by mutableStateOf(defaultHomeChannels); private set
    var selectedId by mutableStateOf("headline"); private set
    var showOverlay by mutableStateOf(false)
    var editing by mutableStateOf(false)
    private val mutex = Mutex()
    private var revision = 0
    val selectedIndex get() = channels.indexOfFirst { it.id == selectedId }.coerceAtLeast(0)
    private fun prefs() = context.getSharedPreferences("greennote_compose_content", Context.MODE_PRIVATE)
    suspend fun restore() {
        val before = revision
        val restored = withContext(Dispatchers.IO) { mutex.withLock {
            val preferences = prefs()
            val ids = if (preferences.contains("home_channels_v2")) runCatching { JSONArray(preferences.getString("home_channels_v2", "[]")).let { array -> (0 until array.length().coerceAtMost(22)).map(array::optString) } }.getOrDefault(emptyList())
            else runCatching { SearchHistory.decodeLegacy(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).all["flutter.home_channels_v2"], maxItems = 22) }.getOrDefault(emptyList())
            val result = restoreHomeChannels(ids)
            if (!preferences.contains("home_channels_v2")) check(preferences.edit().putString("home_channels_v2", JSONArray(result.map(HomeChannel::id)).toString()).commit())
            result
        } }
        if (revision == before) replace(restored, persist = false)
    }
    fun select(index: Int) { channels.getOrNull(index)?.let { selectedId = it.id } }
    fun choose(channel: HomeChannel) {
        if (editing) { if (channels.size > 1) replace(channels.filter { it.id != channel.id }) }
        else { selectedId = channel.id; showOverlay = false }
    }
    fun add(channel: HomeChannel) { if (channels.none { it.id == channel.id }) replace(channels + channel) }
    fun reset() { replace(defaultHomeChannels); selectedId = "headline" }
    private fun replace(next: List<HomeChannel>, persist: Boolean = true) {
        if (next.isEmpty()) return
        channels = next
        if (next.none { it.id == selectedId }) selectedId = next.first().id
        if (persist) { revision++; val ids = next.map(HomeChannel::id); scope.launch { try {
            withContext(Dispatchers.IO) { mutex.withLock { check(prefs().edit().putString("home_channels_v2", JSONArray(ids).toString()).commit()) } }
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("频道设置保存失败") } } }
    }
}

@Composable
internal fun HomeChannelOverlay(state: HomeChannelState) {
    val scheme = MaterialTheme.colorScheme
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .56f)).clickable { state.showOverlay = false })
        Column(Modifier.fillMaxWidth().heightIn(max = with(LocalDensity.current) { (LocalWindowInfo.current.containerSize.height * .65f).toDp() })
            .clip(RoundedCornerShape(bottomStart = 20.dp, bottomEnd = 20.dp)).background(com.green.note.ui.LocalScaffoldColor.current)
            .verticalScroll(rememberReviewScrollState()).padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("我的频道", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)); Spacer(Modifier.width(10.dp))
                Text("点击进入频道", style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant); Spacer(Modifier.weight(1f))
                com.green.note.ui.ReviewTextButton(onClick = { state.editing = !state.editing }) { Text(if (state.editing) "完成" else "编辑") }
                ContentIcon("expand_less_rounded", "收起", { state.showOverlay = false })
            }
            Spacer(Modifier.height(10.dp)); HomeChannelGrid(state.channels, state, true)
            Spacer(Modifier.height(24.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("更多频道", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)); Spacer(Modifier.width(10.dp))
                Text("点击添加新频道", style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant); Spacer(Modifier.weight(1f))
                com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = state::reset) { MaterialGlyph("refresh_rounded"); com.green.note.ui.ReviewButtonIconGap(); Text("恢复默认") }
            }
            Spacer(Modifier.height(10.dp)); HomeChannelGrid(moreHomeChannels.filter { candidate -> state.channels.none { it.id == candidate.id } }, state, false)
        }
    }
}

@Composable
private fun HomeChannelGrid(channels: List<HomeChannel>, state: HomeChannelState, selected: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        channels.chunked(4).forEach { line -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            line.forEach { channel ->
                val active = selected && state.selectedId == channel.id
                Box(Modifier.weight(1f).aspectRatio(2.2f).clip(RoundedCornerShape(10.dp))
                    .clickable { if (selected) state.choose(channel) else state.add(channel) }
                    .background(if (active) scheme.primaryContainer else scheme.surfaceContainerHighest.copy(alpha = .35f))
                    .border(if (active) 1.2.dp else .8.dp, if (active) scheme.primary else scheme.outlineVariant.copy(alpha = .25f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                    Text(channel.title, Modifier.padding(horizontal = 4.dp), fontSize = 13.sp, fontWeight = if (active) FontWeight.Bold else FontWeight.Normal,
                        textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (active) scheme.onPrimaryContainer else scheme.onSurface)
                    if (selected && state.editing) MaterialGlyph("remove_circle", Modifier.align(Alignment.TopEnd).padding(end = 2.dp), size = 16.dp, color = scheme.error)
                }
            }
            repeat(4 - line.size) { Spacer(Modifier.weight(1f)) }
        } }
    }
}
