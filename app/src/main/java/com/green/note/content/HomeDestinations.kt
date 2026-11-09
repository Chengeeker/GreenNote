package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.layout
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

internal data class HomeDestination(val kind: String, val title: String, val route: String)
internal val homeDestinations = linkedMapOf(
    "值得看" to HomeDestination("editorial", "编辑精选", "/page?url=V8_ZHUANTI_20180327"),
    "热闻" to HomeDestination("news", "每日热闻", "/page?url=V8_JINRI_NEWS"),
    "活动" to HomeDestination("activities", "活动", "/page?url=V11_ACTIVITIES"),
    "玩机大神" to HomeDestination("users", "推荐关注", "/page?url=V8_RECOMMEND_USER"),
    "投票" to HomeDestination("polls", "投票", "#/feed/digestList?type=16&message_status=all"),
    "头条榜" to HomeDestination("headlines", "更多精彩", "/page?url=V9_LISHITOUTIAO_NEW"),
    "官方频道" to HomeDestination("official", "官方频道", "/page?url=V11_ZHUANTI_EDITORIALDEPARTMENT_20211117"),
)
internal fun homeDestination(title: String, route: String): HomeDestination? = homeDestinations[title] ?: homeDestinations.values.firstOrNull {
    it.route == route || it.route.substringAfter("url=", "").takeIf(String::isNotEmpty)?.let(route::contains) == true
}

@Composable
internal fun HomeDestinationScreen(api: ContentApi, kind: String, title: String, route: String, onBack: () -> Unit,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit, onCompose: () -> Unit) {
    com.green.note.ui.OfficialHomeTheme { HomeDestinationContent(api, kind, title, route, onBack, onOpen, onUser, onLink, onGallery, onLike, onMore, onCompose) }
}

@Composable
private fun HomeDestinationContent(api: ContentApi, kind: String, title: String, route: String, onBack: () -> Unit,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit, onCompose: () -> Unit) {
    val repo = remember(api) { ContentRepository(api) }; val scope = rememberCoroutineScope()
    var root by remember { mutableStateOf<ContentPage?>(null) }; var failure by remember { mutableStateOf<String?>(null) }; var revision by remember { mutableIntStateOf(0) }
    val states = remember(api, route, revision) { mutableMapOf<String, ContentListState>() }
    LaunchedEffect(route, revision) { try { root = repo.page(contentRequest(route), 1); failure = null } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { failure = error.message } }
    val tabs = root?.rows.orEmpty().filter { it.text("entityTemplate") == "iconTabLinkGridCard" }.flatMap { it.optJSONArray("entities").objects() }
    val headers = root?.rows.orEmpty().filter { it.text("entityTemplate") !in setOf("configCard", "sponsorCard", "noMoreDataCard", "fabCard", "iconTabLinkGridCard") }
    fun decorate(row: JSONObject, rank: Int) = JSONObject(row.toString()).put("_composeCardContext", "home").put("_composeHomeDestination", kind).put("_composeRowRank", rank)
        .put("_composeOfficialLayout", true).put("_composeEditorialCover", kind == "editorial" && row.text("entityTemplate") == "feedCover")
    var collapsed by remember { mutableFloatStateOf(0f) }; var headerHeight by remember { mutableIntStateOf(0) }
    val nested = remember { object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset { if (available.y >= 0) return Offset.Zero; val delta = (-available.y).coerceAtMost((headerHeight - collapsed).coerceAtLeast(0f)); collapsed += delta; return Offset(0f, -delta) }
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset { if (available.y <= 0) return Offset.Zero; val delta = available.y.coerceAtMost(collapsed); collapsed -= delta; return Offset(0f, delta) }
    } }
    @Composable fun Page(source: String) {
        val state = states.getOrPut(source) { ContentListState { page, first, last ->
            val result = if (source == route && page == 1) root ?: repo.page(contentRequest(source), page) else repo.page(contentRequest(source), page, first, last)
            result.copy(rows = result.rows.filter { it.text("entityTemplate") !in setOf("configCard", "sponsorCard", "noMoreDataCard", "fabCard", "iconTabLinkGridCard") }.mapIndexed { index, row -> decorate(row, (page - 1) * 20 + index + 1) })
        } }
        key(source, revision) { ContentList(api, state, onOpen, onUser, onLink, onGallery, onLike, onMore) }
    }
    val dark = MaterialTheme.colorScheme.surface.red + MaterialTheme.colorScheme.surface.green + MaterialTheme.colorScheme.surface.blue < 1.5f
    com.green.note.ui.GlassBackdropHost(modifier = Modifier.fillMaxSize(), content = {
        Column(Modifier.fillMaxSize().background(if (dark) androidx.compose.ui.graphics.Color(0xFF101010) else com.green.note.ui.LocalScaffoldColor.current).nestedScroll(nested)) {
            Row(Modifier.fillMaxWidth().height(56.dp).background(if (dark) androidx.compose.ui.graphics.Color(0xFF1E1E1E) else MaterialTheme.colorScheme.surface), verticalAlignment = Alignment.CenterVertically) { ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(4.dp)); Text(title, Modifier.weight(1f), fontSize = 20.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Medium)
                if (kind !in setOf("activities", "users", "polls", "headlines")) ContentIcon("refresh_rounded", "刷新", { revision++ }) }
            when {
                root == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { if (failure == null) com.green.note.ui.ReviewCircularProgress() else com.green.note.ui.ReviewTextButton(onClick = { revision++ }) { Text(failure.orEmpty()) } }
                tabs.isEmpty() || kind == "polls" -> Page(route)
                else -> {
                    val pager = rememberPagerState { tabs.size }
                    Box(Modifier.clipToBounds().layout { measurable, constraints -> val child = measurable.measure(constraints.copy(minHeight = 0)); headerHeight = child.height; val shift = collapsed.coerceIn(0f, child.height.toFloat()).toInt(); layout(child.width, child.height - shift) { child.placeRelative(0, -shift) } }) {
                        Column { headers.forEachIndexed { index, row -> EntityRow(api, decorate(row, index + 1), onOpen, onUser, onLink, onGallery, onLike, onMore) } }
                    }
                    ScrollableTabRow(pager.currentPage, edgePadding = 0.dp, divider = {}) { tabs.forEachIndexed { index, row -> Tab(pager.currentPage == index, com.green.note.ui.rememberHapticClick { scope.launch { pager.animateScrollToPage(index) } }, text = { Text(row.text("title"), fontSize = 16.sp) }) } }
                    HorizontalPager(pager, Modifier.weight(1f)) { index -> Page(tabs[index].text("url")) }
                }
            }
        }
    }, overlay = {
        Box(Modifier.fillMaxSize()) { if (kind == "news") com.green.note.ui.GreenComposeFab(onClick = onCompose, modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)) }
    })
}
