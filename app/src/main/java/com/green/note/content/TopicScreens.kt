package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.DrawModifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.LayoutModifier
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import androidx.compose.ui.unit.offset
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.fractionalVerticalPadding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject
import kotlin.math.floor
import kotlin.math.roundToInt

internal fun topicProfile(tag: String, title: String = ""): JSONObject {
    val value = "$tag$title".lowercase().replace(" ", "").replace("-", "")
    val features = listOf("柔光玻璃", "灵动岛", "流体云", "自由小窗", "实况照片", "负一屏", "控制中心", "息屏", "锁屏", "小布", "小爱", "原子通知", "原子岛", "胶囊", "动态岛", "超级互联", "互联", "超级壁纸", "状态栏", "通知中心", "相机水印", "水印", "动效", "小组件", "carplay", "carlink")
    val index = when {
        value.contains("coloros") || value.contains("欢太") || value.contains("oppo") && value.contains("os") -> 0
        listOf("hyperos", "澎湃", "miui").any(value::contains) -> if (listOf("柔光玻璃", "超级互联", "小爱", "动效", "锁屏", "小窗", "负一屏", "流体", "相机", "控制中心").any(value::contains)) 1 else 2
        value.contains("originos") || value.contains("funtouch") || value.contains("vivo") && value.contains("os") -> 3
        value.contains("harmonyos") || value.contains("鸿蒙") || value.contains("huawei") && value.contains("os") -> 4
        value.contains("ios") || value.contains("ipados") || value.contains("apple") && value.contains("os") -> 5
        listOf("oneui", "samsung", "三星").any(value::contains) -> 6
        listOf("flyme", "meizu", "魅族").any(value::contains) -> 7
        listOf("magicos", "magicui", "honor", "荣耀").any(value::contains) -> 8
        features.any(value::contains) -> 9
        else -> 10
    }
    val result = JSONObject(topicProfileDefaults.getJSONObject(index).toString().replace("__TITLE__", title.ifEmpty { tag }))
    val suffix = mapOf(0 to "宝藏功能大赏", 2 to "超级互联新特性体验", 3 to "原子岛与蓝心小V体验征集", 4 to "纯血鸿蒙先锋体验大赏", 5 to "个性化与全新功能讨论", 6 to "全新动效与Galaxy AI体验", 7 to "无界互联体验讨论", 8 to "平台级AI体验征集")[index]
    if (suffix != null) result.put("activityTitle", title.ifEmpty { tag } + suffix)
    return result
}

internal fun systemIdentity(value: String): Pair<String, String?>? {
    val name = value.lowercase().replace(Regex("[\\s_-]"), "").replace(Regex("^(小米|华为|三星|荣耀|魅族|vivo|oppo|一加)"), "")
    for (aliases in listOf(listOf("originos"), listOf("funtouchos", "funtouch"), listOf("hyperos", "澎湃os", "澎湃"), listOf("miui"), listOf("coloros"), listOf("oxygenos"), listOf("harmonyos", "鸿蒙"), listOf("emui"), listOf("magicos"), listOf("magicui"), listOf("oneui"), listOf("realmeui"), listOf("flyme"), listOf("ipados"), listOf("ios"), listOf("android", "aosp"), listOf("redmagicos", "redmagic"), listOf("myui"), listOf("nothingos"))) {
        val alias = aliases.firstOrNull(name::startsWith) ?: continue
        return aliases.first() to Regex("^[^0-9]*([0-9]+)").find(name.removePrefix(alias))?.groupValues?.get(1)
    }
    return null
}

internal fun topicRequest(tag: String, profile: JSONObject, tab: Int, sort: String, product: String): ContentRequest {
    if (profile.optBoolean("isSystem") && tab == 2) return ContentRequest("/v6/search", mapOf("type" to "product", "searchValue" to profile.text("searchBrand").ifEmpty { tag }))
    val rated = profile.optBoolean("hasRating")
    val order = if (!rated) listOf("hot", "dateline_desc", "lastupdate_desc")[tab] else when (sort) { "latest" -> "dateline_desc"; "hot" -> "hot"; else -> "lastupdate_desc" }
    val rating = rated && tab == if (profile.optBoolean("isSystem")) 3 else 1
    val query = mutableMapOf("tag" to tag, "listType" to order)
    if (order == "hot") query.putAll(mapOf("sort" to "hot", "sortField" to "rank_score"))
    if (rating) query["feedType"] = "rating"
    if (profile.optBoolean("isSystem") && tab == 0) query["feedType"] = "digest"
    if (rating && product.isNotEmpty()) { query.remove("tag"); query.remove("feedType"); query.putAll(mapOf("url" to "/page?url=/product/feedList", "id" to product, "type" to "rating")); return ContentRequest("/v6/page/dataList", query) }
    return ContentRequest("/v6/topic/tagFeedList", query)
}

@Composable
internal fun TopicScreen(api: ContentApi, tag: String, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit,
    onBack: () -> Unit, onSearch: (String) -> Unit, onCompose: (String) -> Unit, initial: JSONObject? = null) {
    val cleanTag = remember(tag) { tag.trim().removePrefix("/t/").substringBefore('?').replace("#", "").trim() }
    val preparation = LocalTopicPreparation.current
    val prepared = remember(api, cleanTag) { preparation?.ready(cleanTag) }
    var detail by remember(cleanTag) { mutableStateOf<JSONObject?>(prepared?.detail?.let { JSONObject(it.toString()) }) }; var product by remember { mutableStateOf<JSONObject?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }; var revision by remember { mutableIntStateOf(0) }
    var following by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }
    var sort by rememberSaveable { mutableStateOf("default") }
    val scope = rememberCoroutineScope(); val session = LocalContentSession.current; val login = LocalContentLogin.current
    val identity = remember { api.imageCacheScope() }; val toast = remember { com.green.note.ui.AppToastState() }
    LaunchedEffect(api, cleanTag, revision) {
        failure = null
        try {
            val root = if (revision == 0 && prepared != null) prepared.detail else api.request("/v6/topic/newTagDetail", query = mapOf("tag" to cleanTag)); val result = root.optJSONObject("data") ?: root
            check(identity == api.imageCacheScope()) { "账号已变化" }; detail = result
            following = result.optJSONObject("userAction")?.text("follow") in setOf("1", "true") || result.text("isFollow", "is_follow", "followed") in setOf("1", "true")
            if (topicProfile(cleanTag, result.text("title")).optBoolean("hasRating")) {
                val wanted = systemIdentity(result.text("title").ifEmpty { cleanTag })
                if (wanted != null) for (type in listOf("product", "feedTopic")) {
                    val rows = extractEntities(api.request("/v6/search", query = mapOf("type" to type, "searchValue" to cleanTag, "page" to "1")))
                    val match = rows.firstOrNull { row -> systemIdentity(row.text("title", "name"))?.let { it.first == wanted.first && (it.second == null || wanted.second == null || it.second == wanted.second) } == true }
                    if (match != null) { product = JSONObject(match.toString()).put("_catalog", type); break }
                }
            }
        } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { if (detail == null) failure = error.message }
    }
    val row = detail ?: initial ?: JSONObject().put("title", cleanTag)
    val title = row.text("title", "tag", "name").ifEmpty { initial?.text("title").orEmpty().ifEmpty { cleanTag } }
    val profile = remember(cleanTag, title) { topicProfile(cleanTag, title) }
    val tabs = row.optJSONArray("tabList").objects()
    val activity = tabs.any { it.text("title") in setOf("活动详情", "有奖活动") } || cleanTag == "人像摄影"
    val rated = !activity && profile.optBoolean("hasRating")
    val system = rated && profile.optBoolean("isSystem")
    val titles = if (activity) tabs.map { it.text("title") } else if (system) listOf("新特性", "讨论", "机型区", "点评") else if (rated) listOf("讨论", "点评") else listOf("热门", "最新发布", "最新回复")
    val pager = rememberPagerState(initialPage = if (activity) tabs.indexOfFirst { it.text("page_name") == row.text("selectedTab") }.coerceAtLeast(0) else if (system) 1 else 0) { titles.size }
    val states = remember(api, cleanTag) { mutableMapOf<String, ContentListState>() }
    val routes = remember(cleanTag) { mutableStateMapOf<Int, Pair<String, String>>() }
    var collapsed by remember { mutableFloatStateOf(0f) }; var headerHeight by remember { mutableIntStateOf(0) }
    var toolbarCollapsed by remember { mutableFloatStateOf(0f) }
    val toolbarDp = if (rated) 56.dp else 52.dp
    val toolbarHeight = with(androidx.compose.ui.platform.LocalDensity.current) { toolbarDp.toPx() + WindowInsets.statusBars.getTop(this) }
    val nested = remember(rated, toolbarHeight) { object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (available.y >= 0) { if (!rated) return Offset.Zero; val reveal = available.y.coerceAtMost(toolbarCollapsed); toolbarCollapsed -= reveal; return Offset(0f, reveal) }
            val bar = if (rated) (-available.y).coerceAtMost((toolbarHeight - toolbarCollapsed).coerceAtLeast(0f)) else 0f
            toolbarCollapsed += bar
            val delta = (-available.y - bar).coerceAtMost((headerHeight - collapsed).coerceAtLeast(0f)); collapsed += delta; return Offset(0f, -delta - bar)
        }
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            if (available.y <= 0) return Offset.Zero
            val delta = available.y.coerceAtMost(collapsed); collapsed -= delta; return Offset(0f, delta)
        }
    } }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val plainCardColor = if (dark) if (com.green.note.ui.LocalAppPreferences.current.pureBlackDark) Color(0xFF121212) else Color(0xFF1B1C20) else MaterialTheme.colorScheme.surfaceContainerLowest
    val background = if (rated) Color(profile.text("primaryBg").toLong(16)) else if (activity) {
        if (cleanTag == "人像摄影") if (dark) Color(0xFF63643C) else androidx.compose.ui.graphics.lerp(Color(0xFF63643C), Color.White, .85f)
        else if (dark) Color(0xFF414058) else Color(0xFFE5E3EF)
    } else com.green.note.ui.LocalScaffoldColor.current
    val foreground = if (rated) Color.White else if (activity) if (dark) Color(0xFFDDDDDD) else Color(0xFF252431) else MaterialTheme.colorScheme.onSurface
    val initialImage = initial?.text("logo", "pic", "cover").orEmpty()
    val accent = Color(profile.text("accentColor").toLong(16))
    val logo = if (activity) row.text("logo") else row.text("logo", "icon").takeUnless { it.contains("none.gif") || it.contains("default_tag") }.orEmpty().ifEmpty { initialImage }.ifEmpty { row.text("pic", "avatar") }.ifEmpty { systemPresetLogo(title).orEmpty() }
    val cover = row.text("cover", "banner", "background", "bg_pic", "background_url").takeUnless { it == logo || it.contains("none.gif") || it.contains("default_tag") }.orEmpty().ifEmpty { initial?.text("cover").orEmpty().takeUnless { it == logo || it == initial?.text("logo") }.orEmpty() }
    fun follow() {
        if (session.anonymous) { toast.showSnackbar(session.loginRequiredMessage); return }; if (busy) return
        scope.launch { busy = true; try { check(identity == api.imageCacheScope()) { "账号已变化" }; api.request(if (following) "/v6/feed/unFollowTag" else "/v6/feed/followTag", query = mapOf("tag" to cleanTag)); following = !following; preparation?.following(cleanTag, following) }
            catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { toast.showSnackbar(error.message ?: "关注失败") } finally { busy = false } }
    }
    @Composable fun Header() {
        val headerModifier = if (!activity && !rated) Modifier.padding(horizontal = 12.dp, vertical = 8.dp).clip(RoundedCornerShape(20.dp)).background(plainCardColor) else Modifier
        Column(headerModifier) {
            if (cover.isNotEmpty() && !activity && !rated) Box(Modifier.fillMaxWidth().height(120.dp).clickable { onGallery(listOf(cover), 0, null) }) {
                ContentImage(api, cover, null, Modifier.fillMaxSize(), showDefaultError = false); Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, plainCardColor.copy(alpha = .8f)))))
            }
            Column(Modifier.padding(start = if (activity) 12.dp else 16.dp, end = if (activity) 12.dp else 16.dp, top = if (activity) 8.dp else if (rated) 4.dp else 16.dp, bottom = if (activity) 12.dp else if (rated) 10.dp else 16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (activity) { if (logo.isNotEmpty()) ContentImage(api, logo, null, Modifier.size(80.dp).clip(RoundedCornerShape(8.dp))) }
                    else TopicLogo(api, logo, initialImage, title, accent) { onGallery(listOf(it), 0, null) }
                    Spacer(Modifier.width(if (activity) 10.dp else 14.dp))
                    Column(Modifier.weight(1f)) {
                        if (rated) TopicRatingText(title, color = foreground, fontSize = 21.sp, fontWeight = FontWeight.Bold, letterSpacing = .2.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        else Text(if (activity) title else "#$title#", color = foreground, fontSize = if (activity) 20.sp else 18.sp, fontWeight = if (activity) FontWeight.Medium else com.green.note.ui.adjustedWeight(700), letterSpacing = 0.sp, maxLines = if (activity) 2 else 1, overflow = TextOverflow.Ellipsis)
                        val stats = if (rated || activity) "${row.text("hot_num_txt", "hot_num", "hotNum").ifEmpty { "—" }}热度  ${row.text("commentnum_txt", "comment_num", "commentnum", "feed_num", "feedNum").ifEmpty { "—" }}讨论"
                            else topicStats(row)
                        if (stats.isNotEmpty()) { Spacer(Modifier.height(if (activity) 8.dp else 4.dp)); if (rated) TopicRatingText(stats, color = foreground.copy(alpha = .65f), fontSize = 12.sp) else Text(stats, color = if (!activity) MaterialTheme.colorScheme.onSurfaceVariant else foreground.copy(alpha = .65f), fontSize = if (activity) 13.sp else 12.sp) }
                        if (rated) { Spacer(Modifier.height(6.dp)); TopicCreatorRow(api, row, background) }
                        if (activity) { Spacer(Modifier.height(8.dp)); Row(verticalAlignment = Alignment.CenterVertically) {
                            row.optJSONArray("recent_follow_list").objects().take(3).forEach { user -> ContentAvatar(api, user.text("userAvatar"), user.text("username"), 18.dp) { onUser(user.text("uid")) } }
                            Spacer(Modifier.width(6.dp)); Text("${row.text("follownum_txt", "follow_num", "follownum").ifEmpty { "—" }}关注", color = foreground.copy(alpha = .65f), fontSize = 13.sp)
                        } }
                    }
                    Spacer(Modifier.width(if (rated) 10.dp else 8.dp))
                    if (activity) com.green.note.ui.ReviewButton(onClick = ::follow, enabled = !busy, modifier = Modifier.defaultMinSize(minWidth = 58.dp, minHeight = 30.dp).height(30.dp), shape = RoundedCornerShape(5.dp), contentPadding = PaddingValues(horizontal = 12.dp), border = if (following) androidx.compose.foundation.BorderStroke(1.dp, foreground.copy(alpha = .25f)) else null, colors = ButtonDefaults.buttonColors(containerColor = if (following) Color.Transparent else Color(0xFF009688), contentColor = if (following) foreground.copy(alpha = .65f) else Color.White)) { Text(if (following) "已关注" else "关注") }
                    else TopicFollowButton(following, busy, rated, ::follow)
                }
                val description = if (activity) row.text("intro", "description") else row.text("description", "intro", "content")
                if (!rated && description.isNotEmpty()) { Spacer(Modifier.height(12.dp)); if (activity) CompositionLocalProvider(LocalContentColor provides foreground) { ContentRichText(description, onLink = onLink, fontSize = 15.sp, lineHeight = 24.75.sp) } else Text(description, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp, lineHeight = 18.2.sp) }
                if (activity) row.optJSONArray("recommendRows").objects().flatMap { it.optJSONArray("entities").objects() }.forEach { recommendation ->
                    com.green.note.ui.ReviewTileLayout(Modifier.padding(top = 10.dp).clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = .17f)).clickable { onOpen(JSONObject(recommendation.toString()).put("_composeHeadlineTarget", true)) }, horizontalPadding = 12.dp, trailing = { MaterialGlyph("chevron_right", color = foreground) }) {
                        Text(androidx.compose.ui.text.buildAnnotatedString { pushStyle(androidx.compose.ui.text.SpanStyle(color = Color(0xFF00DDCA))); append(recommendation.text("entityTypeName") + "  "); pop(); append(recommendation.text("title")) }, color = foreground, fontSize = 15.sp, lineHeight = 20.25.sp, fontWeight = com.green.note.ui.adjustedWeight(600))
                    }
                }
                if (!rated && !activity && failure != null) { Spacer(Modifier.height(8.dp)); Text(failure.orEmpty(), fontSize = 12.sp, color = MaterialTheme.colorScheme.error) }
            }
            if (rated) TopicRatingHeader(row, profile, product, onLink)
            if ((rated || activity) && failure != null) Text(failure.orEmpty(), Modifier.padding(horizontal = if (rated) 16.dp else 0.dp, vertical = 4.dp), fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
            if (rated) Spacer(Modifier.height(4.dp))
        }
    }
    @Composable fun Content() {
    com.green.note.ui.GlassBackdropHost(modifier = Modifier.fillMaxSize(), content = {
        Box(Modifier.fillMaxSize().background(background)) {
        if (rated) TopicAtmosphere(api, cover, background, accent)
        Column(Modifier.fillMaxSize().nestedScroll(nested)) {
            Box(Modifier.clipToBounds().layout { measurable, constraints -> val child = measurable.measure(constraints.copy(minHeight = 0)); val shift = if (rated) toolbarCollapsed.toInt().coerceIn(0, child.height) else 0; layout(child.width, child.height - shift) { child.placeRelative(0, -shift) } }) {
            Row(Modifier.statusBarsPadding().height(toolbarDp).fillMaxWidth().contentToolbarBorder(!rated && !activity), verticalAlignment = Alignment.CenterVertically) {
                com.green.note.ui.ReviewToolbarIcons(foreground) { ContentIcon(if (rated) "arrow_back_rounded" else "arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(16.dp))
                    Text(if (!rated && !activity) "#$title#" else "", Modifier.weight(1f), style = androidx.compose.ui.text.TextStyle(
                        localeList = com.green.note.ui.ReviewTextLocales, fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700),
                        platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false)))
                    if (rated || activity) ContentIcon(if (rated) "search_rounded" else "search", "搜索", { onSearch(title) })
                    if (rated) Spacer(Modifier.width(4.dp)) }
            }
            }
            Box(Modifier.clipToBounds().layout { measurable, constraints ->
                val child = measurable.measure(constraints.copy(minHeight = 0)); headerHeight = child.height
                val shift = collapsed.coerceIn(0f, child.height.toFloat()).toInt()
                layout(child.width, child.height - shift) { child.placeRelative(0, -shift) }
            }) { Header() }
            if (titles.isNotEmpty()) Surface(color = if (rated) Color(profile.text("surfaceBg").toLong(16)) else if (activity) if (dark) Color(0xFF1E1E1E) else Color.White else MaterialTheme.colorScheme.surface) {
                Column {
                    TopicTabs(titles, pager.currentPage, activity, rated) { index -> scope.launch { pager.animateScrollToPage(index) } }
                    if (rated) Row(Modifier.fillMaxWidth().height(38.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) { Text(when (titles[pager.currentPage]) { "点评" -> "全部点评"; "机型区" -> "适配机型"; "新特性" -> "精选动态"; else -> "全部讨论" }, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold); if (titles[pager.currentPage] == "讨论") { Spacer(Modifier.width(2.dp)); MaterialGlyph("keyboard_arrow_down_rounded", size = 18.dp, color = Color.White.copy(alpha = .7f)) } }
                        Row(Modifier.height(28.dp).clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = .08f)).padding(2.dp)) { listOf("默认" to "default", "最新" to "latest", "热度" to "hot").forEach { (label, value) -> val selectedColor by androidx.compose.animation.animateColorAsState(if (sort == value) Color.White.copy(alpha = .22f) else Color.Transparent, androidx.compose.animation.core.tween(180), label = "Topic sort"); Text(label, Modifier.clip(RoundedCornerShape(12.dp)).background(selectedColor).clickable { sort = value }.padding(horizontal = 10.dp, vertical = 3.dp), color = if (sort == value) Color.White else Color.White.copy(alpha = .65f), fontSize = 12.sp, fontWeight = if (sort == value) FontWeight.Bold else FontWeight.Normal) } }
                    }
                }
            }
            if (titles.isEmpty()) Box(Modifier.fillMaxWidth().weight(1f).background(if (activity) if (dark) Color(0xFF101010) else Color.White else background), contentAlignment = Alignment.Center) { if (activity) Text("暂无活动内容") } else HorizontalPager(pager, Modifier.weight(1f).background(if (activity) if (dark) Color(0xFF101010) else Color.White else background)) { page ->
                val activityRoute = routes[page]?.first ?: tabs.getOrNull(page)?.text("url").orEmpty()
                if (activity) ActivityTabBody(api, tabs[page], onOpen, onUser, onLink, onGallery, onLike, onMore, onBack, initialPage = prepared?.firstPage?.takeIf { activityRoute == prepared.firstRoute }, cacheTag = cleanTag.takeIf { activityRoute == prepared?.firstRoute || page == tabs.indexOfFirst { it.text("page_name") == row.text("selectedTab") }.coerceAtLeast(0) })
                else {
                    val selection = routes[page]
                    val request = selection?.first?.let(::contentRequest)
                        ?: topicRequest(cleanTag, profile, page, sort, product?.takeIf { it.text("_catalog") == "product" }?.text("id", "productId").orEmpty())
                    val state = states.getOrPut("$rated:$system:$page") { ContentListState() }
                    LaunchedEffect(state, request) {
                        state.bind(request) { number, first, last ->
                            val result = topicPage(api, request, number, first, last)
                            val rows = if (number == 1 && selection != null && activitySortCard(result.rows) == null) {
                                listOfNotNull(activitySortCard(state.rows)) + result.rows
                            } else result.rows
                            result.copy(rows = normalizeSpecializedCards(rows.map { JSONObject(it.toString()).put("_composeCardContext", if (system) "system" else "api").put("_selectedSortTitle", selection?.second.orEmpty()) }))
                        }
                    }
                    ContentList(api, state, { entity -> if (entity.optBoolean("_composeSortRequest")) routes[page] = entity.text("url") to entity.text("title") else onOpen(entity) }, onUser, onLink, onGallery, onLike, onMore, loadInitially = false)
                }
            }
        }
        }
    }, overlay = {
        Box(Modifier.fillMaxSize()) { com.green.note.ui.GreenComposeFab(onClick = { onCompose(title) }, modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)) }
    })
    }
    if (activity) com.green.note.ui.OfficialHomeTheme { Content() } else Content()
}

@Composable
private fun TopicRatingText(value: String, modifier: Modifier = Modifier,
    fontSize: androidx.compose.ui.unit.TextUnit, color: Color,
    fontWeight: FontWeight? = null, letterSpacing: androidx.compose.ui.unit.TextUnit? = null,
    textAlign: androidx.compose.ui.text.style.TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE, overflow: TextOverflow = TextOverflow.Clip) {
    val base = LocalTextStyle.current
    val style = base.copy(fontSize = fontSize, color = color, fontWeight = fontWeight ?: base.fontWeight,
        letterSpacing = letterSpacing ?: base.letterSpacing, textAlign = textAlign ?: base.textAlign)
    val metrics = com.green.note.ui.rememberFlutterArticleStyle(
        androidx.compose.ui.text.AnnotatedString(value), style, plainTitle = true)
    Text(value, modifier = modifier.then(metrics.modifier), style = metrics.style,
        onTextLayout = metrics.onTextLayout, maxLines = maxLines, overflow = overflow)
}

/** The four rows share fractional padding boundaries, as Flutter's double-valued Column does. */
internal data class TopicDimensionPadding(private val padding: Dp, private val index: Int) : LayoutModifier, DrawModifier {
    init { require(padding.value.isFinite() && padding.value >= 0f && index in 0..3) }

    private fun inset(density: Float) = (padding.value * density).coerceIn(0f, 32767f)
    private fun prefix(density: Float) = (index * 2f * inset(density)).roundToInt()
    private fun total(density: Float) = ((index + 1) * 2f * inset(density)).roundToInt() - prefix(density)
    // Carry the previous fractional boundary into this row's local draw origin.
    internal fun contentTop(density: Float) = (2 * index + 1) * inset(density) - prefix(density)
    private fun finite(value: Int) = value.coerceIn(0, 262142)
    private fun available(height: Int, density: Float) =
        if (height == Constraints.Infinity) height else (height - total(density)).coerceAtLeast(0)
    private fun sum(height: Int, density: Float) = (finite(height).toLong() + total(density)).coerceAtMost(262142).toInt()

    override fun MeasureScope.measure(measurable: Measurable, constraints: Constraints): androidx.compose.ui.layout.MeasureResult {
        val child = measurable.measure(constraints.offset(vertical = -total(density)))
        return layout(constraints.constrainWidth(child.width), constraints.constrainHeight(sum(child.height, density))) {
            child.place(0, floor(contentTop(density)).toInt())
        }
    }

    override fun ContentDrawScope.draw() {
        val top = contentTop(density)
        translate(top = top - floor(top)) { this@draw.drawContent() }
    }

    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurable: IntrinsicMeasurable, height: Int) =
        finite(measurable.minIntrinsicWidth(available(height, density)))
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurable: IntrinsicMeasurable, height: Int) =
        finite(measurable.maxIntrinsicWidth(available(height, density)))
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurable: IntrinsicMeasurable, width: Int) =
        sum(measurable.minIntrinsicHeight(width), density)
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurable: IntrinsicMeasurable, width: Int) =
        sum(measurable.maxIntrinsicHeight(width), density)
}

@Composable
private fun TopicRatingHeader(row: JSONObject, profile: JSONObject, product: JSONObject?, onLink: (String) -> Unit) {
    val gold = Color(0xFFFFB300)
    val score = product?.text("star_average_score", "score", "star_score")?.toDoubleOrNull()?.takeIf { it > 0 }
        ?: row.text("score", "star_average_score", "star_score").toDoubleOrNull()?.takeIf { it > 0 }
    val scoreLabel = score?.let { String.format(java.util.Locale.US, "%.1f", it) } ?: "—"
    val scoreMetrics = com.green.note.ui.rememberFlutterArticleStyle(
        androidx.compose.ui.text.AnnotatedString(scoreLabel),
        LocalTextStyle.current.copy(fontSize = 38.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold, color = gold),
        plainTitle = true)
    Column(Modifier.padding(start = 14.dp, top = 10.dp, end = 14.dp, bottom = 8.dp).dropShadow(RoundedCornerShape(16.dp), Shadow(8.dp, Color.Black.copy(alpha = .15f), offset = DpOffset(0.dp, 2.dp))).clip(RoundedCornerShape(16.dp)).background(Color(profile.text("cardBg").toLong(16))).padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) { TopicRatingText("酷安评分", fontSize = 15.sp, fontWeight = FontWeight.Bold, letterSpacing = .2.sp, color = Color.White); Row(verticalAlignment = Alignment.CenterVertically) { TopicRatingText("详细数据", fontSize = 12.sp, color = Color.White.copy(alpha = .55f)); Spacer(Modifier.width(2.dp)); MaterialGlyph("chevron_right_rounded", size = 15.dp, color = Color.White.copy(alpha = .55f)) } }
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.width(90.dp), horizontalAlignment = Alignment.CenterHorizontally) { Text(scoreLabel, modifier = scoreMetrics.modifier, style = scoreMetrics.style, onTextLayout = scoreMetrics.onTextLayout); Spacer(Modifier.height(4.dp)); Row { repeat(5) { MaterialGlyph(if (score != null) "star_rounded" else "star_outline_rounded", size = 13.dp, color = gold) } }; Spacer(Modifier.height(4.dp)); TopicRatingText("用户评分", fontSize = 11.sp, color = Color.White.copy(alpha = .55f)) }
            Spacer(Modifier.width(14.dp))
            if (profile.optBoolean("isSystem")) {
                val dimensions = profile.getJSONArray("dimensions"); val scores = row.optJSONArray("dimensionScores") ?: org.json.JSONArray()
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) { repeat(2) { column -> Column(Modifier.weight(1f)) { for (i in column * 4 until minOf(column * 4 + 4, dimensions.length())) {
                    Row(Modifier.then(TopicDimensionPadding(2.2.dp, i - column * 4)), verticalAlignment = Alignment.CenterVertically) { TopicRatingText(dimensions.getString(i), Modifier.width(52.dp), fontSize = 10.5.sp, color = Color.White.copy(alpha = .75f), maxLines = 1, overflow = TextOverflow.Ellipsis); Spacer(Modifier.width(3.dp)); TopicScoreBar((scores.optDouble(i, 0.0) / 10).toFloat(), Modifier.weight(1f)); Spacer(Modifier.width(4.dp)); TopicRatingText(if (scores.isNull(i)) "—" else String.format(java.util.Locale.US, "%.1f", scores.optDouble(i)), Modifier.width(20.dp), textAlign = androidx.compose.ui.text.style.TextAlign.End, fontSize = 9.5.sp, color = Color.White.copy(alpha = .6f)) }
                } } } }
            } else {
                val counts = (5 downTo 1).map { star -> row.text("star$star", "star_$star").toIntOrNull() }; val total = counts.filterNotNull().sum().coerceAtLeast(1)
                Column(Modifier.weight(1f)) { counts.forEachIndexed { index, count -> Row(Modifier.fractionalVerticalPadding(1.5.dp), verticalAlignment = Alignment.CenterVertically) { TopicRatingText("${5-index}星", Modifier.width(24.dp), fontSize = 10.5.sp, color = Color.White.copy(alpha = .7f)); Spacer(Modifier.width(4.dp)); TopicScoreBar((count ?: 0).toFloat() / total, Modifier.weight(1f)); Spacer(Modifier.width(6.dp)); TopicRatingText(count?.toString() ?: "—", Modifier.width(22.dp), textAlign = androidx.compose.ui.text.style.TextAlign.End, fontSize = 10.sp, color = Color.White.copy(alpha = .6f)) } } }
            }
        }
        Spacer(Modifier.height(12.dp)); HorizontalDivider(thickness = .6.dp, color = Color.White.copy(alpha = .08f)); Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { TopicRatingText("${row.text("commentnum", "feed_comment_num", "feedCommentNumTxt").ifEmpty { "—" }}用户点评", Modifier.weight(1f), fontSize = 12.sp, color = Color.White.copy(alpha = .55f)); TopicRatingText("不可点评", Modifier.background(Color.White.copy(alpha = .12f), RoundedCornerShape(12.dp)).padding(horizontal = 10.dp, vertical = 4.dp), color = Color.White.copy(alpha = .7f), fontSize = 11.sp) }
    }
    val activity = row.text("activityTitle", "activity_title").ifEmpty { profile.text("activityTitle") }
    if (profile.optBoolean("isSystem")) {
        if (activity.isNotEmpty()) Row(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 8.dp).clip(RoundedCornerShape(12.dp)).background(Color(profile.text("surfaceBg").toLong(16))).border(1.dp, Color(profile.text("accentColor").toLong(16)).copy(alpha = .25f), RoundedCornerShape(12.dp)).clickable { onLink("/t/${android.net.Uri.encode(activity)}") }.padding(1.dp).padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) { Text("有奖活动", Modifier.background(Color(0xFFFF9800).copy(alpha = .2f), RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp), color = gold, fontSize = 11.sp, fontWeight = FontWeight.Bold); Spacer(Modifier.width(8.dp)); Text(activity, Modifier.weight(1f), color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis); MaterialGlyph("chevron_right_rounded", size = 16.dp, color = Color.White.copy(alpha = .55f)) }
    } else row.text("description", "intro", "content").ifEmpty { profile.text("description") }.takeIf(String::isNotEmpty)?.let { Text(it, Modifier.padding(start = 16.dp, top = 2.dp, end = 16.dp, bottom = 10.dp), color = Color.White.copy(alpha = .75f), fontSize = 13.sp, lineHeight = 18.85.sp) }
}
