package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun discoveryBody(row: JSONObject) = row.text("entityType").lowercase().let { it.contains("feed") || it.contains("dyharticle") }
internal fun discoveryVisible(row: JSONObject) = row.text("entityTemplate") !in setOf("configCard", "sponsorCard", "noMoreDataCard", "noMoreData", "fabCard")
internal fun discoveryRequest(route: String): ContentRequest {
    val value = route.replace("\${uid}", "")
    return if (value.startsWith("/page?") || value.startsWith("/v6/") || value.startsWith("/user/")) contentRequest(value)
    else if (value.startsWith("/page/dataList?")) contentRequest(value.replaceFirst("/page/dataList?", "/v6/page/dataList?"))
    else ContentRequest("/v6/page/dataList", mapOf("url" to value))
}

@Stable
internal class DiscoveryState(private val api: ContentApi, val title: String, private val route: String) {
    var headers by mutableStateOf<List<JSONObject>>(emptyList()); private set
    private var initialSelection by mutableStateOf("")
    val selected get() = list.appliedSource as? String ?: initialSelection
    private var source = route
    private var requestedSelection: String? = null
    private val repo = ContentRepository(api)
    val list = ContentListState { page, first, last ->
        var result = repo.page(discoveryRequest(if (page == 1) route else source), page, first, last)
        if (page == 1) {
            headers = result.rows.filter { !discoveryBody(it) && !(title == "酷品" && it.text("entityType") == "pear_goods") && discoveryVisible(it) }
                .filter { title != "看看号" || it.text("entityTemplate") !in setOf("unLoginCard", "imageCard") && !it.text("title").contains("我订阅") }
            val config = result.rows.firstOrNull { it.text("entityTemplate") == "configCard" && cardExtra(it).text("flexList") == "1" }?.let(::cardExtra)
            val flex = config?.text("url").orEmpty()
            if (flex.isNotEmpty()) { source = flex; result = repo.page(discoveryRequest(flex), 1) }
            else {
                val selector = headers.firstOrNull { it.text("entityTemplate") in setOf("selectorLinkCard", "sortSelectCard") }
                val options = selector?.optJSONArray("entities").objects()
                val chosen = options.firstOrNull { it.text("title") == selector?.let(::cardExtra)?.text("selectedTab") } ?: options.firstOrNull()
                initialSelection = chosen?.text("url").orEmpty(); source = initialSelection.ifEmpty { route }
            }
        }
        visiblePage(result)
    }

    suspend fun select(next: String) {
        if (next.isEmpty() || next == selected && !list.busy && list.error == null) return
        if (next == requestedSelection && list.error != null) {
            list.load()
            return
        }
        requestedSelection = next
        list.bind(next) { page, first, last -> visiblePage(repo.page(discoveryRequest(next), page, first, last)) }
    }

    private fun visiblePage(result: ContentPage) = result.copy(rows = result.rows.filter {
        (discoveryBody(it) || title == "酷品" && it.text("entityType") == "pear_goods") && discoveryVisible(it)
    })
}

@Composable
internal fun DiscoveryScreen(api: ContentApi, state: DiscoveryState, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit,
    onCoolPictureGallery: (List<String>, Int, JSONObject) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    val scope = rememberCoroutineScope(); val list = state.list
    val pictures = state.title == "酷图"; val waterfall = pictures || state.title in setOf("二手", "商家")
    val scroll = rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    val session = LocalContentSession.current; val login = LocalContentLogin.current
    var subscriptions by remember { mutableStateOf<List<JSONObject>>(emptyList()) }; var subscriptionsMore by remember { mutableStateOf(false) }; var subscriptionError by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(state) { if (list.rows.isEmpty() && list.error == null) list.load(true) }
    LaunchedEffect(state.title, session) {
        if (state.title == "看看号" && session.authenticated) try {
            val page = parsePage(api.request("/v6/user/dyhFollowList", query = mapOf("page" to "1")), 1); subscriptions = page.rows; subscriptionsMore = page.more
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { subscriptionError = "订阅状态暂未加载" }
    }
    val display = remember(list.rows, pictures, state.title) {
        val result = mutableListOf<Pair<List<JSONObject>, Int>>()
        var index = 0
        while (index < list.rows.size) {
            val row = list.rows[index++]
            if (pictures) { val count = feedImages(row).size.coerceAtLeast(if (row.text("message_cover", "cover", "pic").isEmpty()) 0 else 1); repeat(count) { result.add(listOf(row) to it) } }
            else if (state.title == "酷品" && row.text("entityType") == "pear_goods") {
                val group = mutableListOf(row); while (index < list.rows.size && group.size < 3 && list.rows[index].text("entityType") == "pear_goods") group.add(list.rows[index++]); result.add(group to -1)
            } else result.add(listOf(row) to 0)
        }; result
    }
    LaunchedEffect(state, display.size, scroll) {
        snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect { last ->
            if (!waterfall && list.rows.isNotEmpty() && last >= display.size - 3 && list.error == null) list.load()
        }
    }
    fun open(row: JSONObject) { if (row.optBoolean("_composeDiscoverySelect") || row.optBoolean("_composeSortRequest")) scope.launch { state.select(row.text("url")) } else onOpen(row) }
    @Composable fun Headers() {
        Spacer(Modifier.height(8.dp))
        if (state.title == "看看号") {
            DiscoverySurface {
            Row(Modifier.fillMaxWidth().clickable { if (session.authenticated) onLink("/v6/user/dyhFollowList") else com.green.note.ui.AppToastState().showSnackbar(session.loginRequiredMessage) }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { Text("我订阅的看看号", fontSize = 17.sp); subscriptionError?.let { Text(it, fontSize = 11.sp) } }
                subscriptions.take(2).forEach { ContentAvatar(api, it.text("logo", "userAvatar"), "", 28.dp); Spacer(Modifier.width(2.dp)) }
                if (subscriptions.isNotEmpty()) Box(Modifier.size(30.dp).background(androidx.compose.ui.graphics.Color(0xFF009688), RoundedCornerShape(99.dp)), contentAlignment = Alignment.Center) { Text("${subscriptions.size}${if (subscriptionsMore) "+" else ""}", color = androidx.compose.ui.graphics.Color.White, fontSize = 12.sp) }
                MaterialGlyph("chevron_right")
            }
            }
        }
        state.headers.forEach { header ->
            key(entityKey(header)) { EntityRow(api, JSONObject(header.toString()).put("_composeCardContext", "discovery").put("_composeDiscoveryChannel", state.title).put("_composeSelectedRoute", state.selected), ::open, onUser, onLink, onGallery, onLike, onMore) }
        }
    }
    @Composable fun Footer() {
        Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (list.error != null) com.green.note.ui.ReviewTextButton(onClick = { scope.launch { list.load(list.rows.isEmpty()) } }) { Text("加载失败，点击重试：${list.error}") }
            else if (list.busy) com.green.note.ui.ReviewCircularProgress() else if (list.rows.isEmpty() && state.headers.isEmpty()) Text("暂无内容")
        }
        Spacer(Modifier.height(90.dp)); Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
    }
    val lanes = remember(list.rows, pictures) { discoveryLanes(list.rows, pictures) }
    val tiles = remember(lanes) { lanes.flatten().associateBy { it.key } }
    val density = androidx.compose.ui.platform.LocalDensity.current
    val dark = MaterialTheme.colorScheme.surface.let { it.red + it.green + it.blue < 1.5f }
    com.green.note.ui.ReviewRefreshBox(list.refreshing, { scope.launch { list.load(true) } }, Modifier.fillMaxSize().background(if(dark)androidx.compose.ui.graphics.Color(0xff101010) else MaterialTheme.colorScheme.surface), failed = list.error != null) {
        if (waterfall) com.green.note.ui.FixedLaneList(
            lanes = lanes.map { lane -> lane.map { it.key } },
            estimatedHeight = { key, width -> val tile=tiles.getValue(key); if(pictures)(width/tile.ratio+with(density){4.dp.toPx()}).toInt() else (width/.75f+with(density){160.dp.toPx()}).toInt() },
            header = { Headers() }, footer = { Footer() },
            itemContent = { key -> val tile = tiles.getValue(key); if(pictures)DiscoveryPictureTile(api,tile.row,tile.imageIndex,onCoolPictureGallery) else DiscoveryWaterfallCard(api,tile.row,state.title=="二手",::open,onUser) },
            onNearEnd = { if(list.rows.isNotEmpty() && list.error==null && !list.busy)scope.launch{list.load()} },
            modifier = Modifier.fillMaxSize(), horizontalSpacing = if (state.title == "二手") 4.dp else 8.dp,
            verticalSpacing = 0.dp, contentPadding = PaddingValues(horizontal = if (state.title == "二手") 4.dp else 8.dp)
        ) else LazyColumn(state=scroll,modifier=Modifier.fillMaxSize()) {
            item(key="headers"){Headers()}
            items(display,key={"body:${entityKey(it.first.first())}:${it.second}"}) { (rows,image) -> val row=rows.first()
                when {
                    image == -1 -> Row(Modifier.padding(start = 8.dp, end = 8.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { repeat(3) { i -> Box(Modifier.weight(1f)) { rows.getOrNull(i)?.let { DiscoveryGoodsTile(api, it, ::open, pear = true) } } } }
                    row.text("entityTemplate") == "goodsRankingCard" -> DiscoveryGoodsRanking(api, row, ::open)
                    else -> EntityRow(api, JSONObject(row.toString()).put("_composeCardContext", "discovery").put("_composeDiscoveryChannel", state.title).put("_composeOfficialLayout", true).also { entity ->
                        if (state.title == "看看号") row.optJSONArray("relationRows").objects().firstOrNull { it.text("url").startsWith("/dyh/") }?.let { entity.put("_composeDiscoveryArticleSource", it) }
                    }, ::open, onUser, onLink, onGallery, onLike, onMore)
                }
            }
            item(key="footer"){Footer()}
        }
    }
}
