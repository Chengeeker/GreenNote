package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.rememberScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.scrollBy
import androidx.compose.ui.semantics.verticalScrollAxisRange
import androidx.compose.ui.semantics.ScrollAxisRange
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.AppToastState
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.OfficialHomeTheme
import com.green.note.ui.ReviewModalBottomSheet
import com.green.note.ui.ReviewScrollActivity
import com.green.note.ui.adjustedWeight
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

internal data class CrowdTestAction(val label: String, val canRegister: Boolean, val actionUrl: String, val winnersUrl: String)
internal fun eventTime(event: JSONObject, vararg keys: String): Long? = keys.firstNotNullOfOrNull { event.text(it).toLongOrNull()?.takeIf { value -> value > 0 } }
internal fun validCrowdTestRegistrationUrl(raw: String): Boolean = runCatching {
    java.net.URI(raw).let { it.scheme == "https" && !it.host.isNullOrEmpty() && it.rawUserInfo == null }
}.getOrDefault(false)
internal fun crowdTestAction(event: JSONObject, nowSeconds: Long = System.currentTimeMillis() / 1000): CrowdTestAction {
    val start = eventTime(event, "time_reg_start", "registrationStart", "registration_start")
    val end = eventTime(event, "time_reg_end", "registrationEnd", "registration_end")
    val eventEnd = eventTime(event, "time_end", "eventEnd", "event_end")
    val stage = event.text("stage_status", "stageStatus").toIntOrNull()
    val action = event.text("action_url", "actionUrl")
    val winners = event.text("prizeUserUrl")
    val joined = event.text("is_join_status") == "1"
    val canRegister = !joined && (stage == null || stage == 1) && start != null && end != null &&
        nowSeconds >= start && nowSeconds <= end && validCrowdTestRegistrationUrl(action)
    val label = when {
        winners.isNotEmpty() -> "查看众测名单"
        stage == 2 -> "暂未公布众测名单"
        stage == 3 || eventEnd != null && nowSeconds > eventEnd -> "活动已结束"
        start != null && nowSeconds < start -> "报名未开始"
        end != null && nowSeconds > end -> "暂未公布众测名单"
        joined -> "已报名"
        canRegister -> "立即报名"
        else -> "暂不可报名"
    }
    return CrowdTestAction(label, canRegister, action, winners)
}
private fun eventDate(seconds: Long?): String = seconds?.let {
    runCatching { java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT).format(java.util.Date(Math.multiplyExact(it, 1000L))) }.getOrNull()
} ?: "待公布"
private fun eventRows(value: Any?): List<JSONObject> = when (value) { is JSONObject -> listOf(value); is JSONArray -> value.objects(); else -> emptyList() }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun EventDetailScreen(api: ContentApi, id: String, onBack: () -> Unit, onOpen: (JSONObject) -> Unit,
    onUser: (String) -> Unit, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit,
    onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    var event by remember(id, api) { mutableStateOf<JSONObject?>(null) }
    var error by remember(id) { mutableStateOf<String?>(null) }
    var revision by remember(id) { mutableIntStateOf(0) }
    var expanded by rememberSaveable(id) { mutableStateOf(false) }
    var showNotice by remember(id) { mutableStateOf(false) }
    var clockRevision by remember(id) { mutableIntStateOf(0) }
    val identity = remember(id, api) { api.imageCacheScope() }
    val session = LocalContentSession.current
    val toast = remember { AppToastState() }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val safeTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    LaunchedEffect(id, api, revision) {
        error = null
        try {
            val loaded = api.request("/v6/event/detail", query = mapOf("id" to id)).optJSONObject("data") ?: error("活动详情数据为空")
            check(identity == api.imageCacheScope()) { "账号已变更" }
            event = loaded
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "活动详情加载失败" }
    }
    val row = event
    if (row == null) {
        Column(Modifier.fillMaxSize().background(com.green.note.ui.LocalScaffoldColor.current).statusBarsPadding()) {
            com.green.note.ui.ReviewToolbarIcons() { Row(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
                ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(16.dp))
                Text("酷安众测", fontSize = 18.sp, fontWeight = adjustedWeight(700))
            } }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (error == null) com.green.note.ui.ReviewCircularProgress() else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(error.orEmpty()); com.green.note.ui.ReviewTextButton(onClick = { revision++ }) { Text("重试") }
                }
            }
        }
        return
    }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val background = if (dark) Color(0xff101010) else MaterialTheme.colorScheme.surfaceContainerLow
    val picture = row.text("logo").let { if (it.startsWith("//")) "https:$it" else it }
    val notice = row.text("notice_rule", "noticeRule")
    val sponsors = eventRows(row.opt("sponsorUser"))
    val prizes = eventRows(row.opt("sponsorPrize"))
    val tabs = eventRows(row.opt("tabList"))
    val pager = rememberPagerState { tabs.size.coerceAtLeast(1) }
    val tabWidths = remember(tabs.map { it.text("title") }) { mutableStateMapOf<Int, androidx.compose.ui.unit.Dp>() }
    var indicatorJourney by remember { mutableStateOf<Pair<Float, Int>?>(null) }
    var indicatorGeneration by remember { mutableIntStateOf(0) }
    val start = eventTime(row, "time_reg_start", "registrationStart", "registration_start")
    val end = eventTime(row, "time_reg_end", "registrationEnd", "registration_end")
    val nowSeconds = System.currentTimeMillis() / 1000
    val action = remember(row, clockRevision, nowSeconds) { crowdTestAction(row, nowSeconds) }
    fun act() {
        if (action.winnersUrl.isNotEmpty()) { onOpen(JSONObject().put("_composeHeadlineTarget", true).put("title", "众测名单").put("url", action.winnersUrl)); return }
        val now = System.currentTimeMillis() / 1000
        clockRevision++
        if (end == null || now > end) { toast.showSnackbar("报名已结束"); return }
        if (!session.authenticated || session.anonymous) { toast.showSnackbar(if (session.anonymous) "当前为匿名登录，无法使用此功能" else "请先登录"); return }
        if (!validCrowdTestRegistrationUrl(action.actionUrl)) { toast.showSnackbar("活动报名地址无效"); return }
        if (identity != api.imageCacheScope()) { toast.showSnackbar("账号已变更"); return }
        onOpen(JSONObject().put("_composeInAppBrowser", true).put("url", action.actionUrl))
    }
    OfficialHomeTheme {
        val cardColor = if (dark) Color(0xff1e1e1e) else MaterialTheme.colorScheme.surface
        @Composable fun Card(content: @Composable ColumnScope.() -> Unit) {
            Column(Modifier.fillMaxWidth().padding(start = 9.dp, end = 9.dp, bottom = 12.dp).clip(RoundedCornerShape(8.dp)).background(cardColor).padding(12.dp), content = content)
        }
        @Composable fun Header() {
            Column {
                Box(Modifier.fillMaxWidth()) {
                    if (picture.isNotEmpty()) {
                        var failed by remember(picture, identity) { mutableStateOf(false) }
                        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(background)) {
                            if (!failed) ContentImage(api, picture, null, Modifier.fillMaxSize(), ContentScale.Crop, heroCornerRadius = 0.dp, onError = { failed = true })
                        }
                        Box(Modifier.fillMaxWidth().offset(y = 110.dp).height(94.dp).background(Brush.verticalGradient(listOf(background.copy(alpha = 0f), background))))
                    }
                    com.green.note.ui.ReviewToolbarIcons(Color.White) {
                        ContentIcon("arrow_back", "返回", onBack, Modifier.padding(start = 8.dp, top = safeTop + 6.dp))
                    }
                    Box(Modifier.padding(top = if (picture.isEmpty()) safeTop + 56.dp else 152.dp)) {
                        Card {
                            Text(row.text("title"), fontSize = 18.sp, fontWeight = adjustedWeight(600))
                            Spacer(Modifier.height(8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                MaterialGlyph("alarm", size = 14.dp); Spacer(Modifier.width(4.dp))
                                Text("报名时间：${eventDate(start)}至${eventDate(end)}", Modifier.weight(1f), fontSize = 14.sp)
                            }
                            Spacer(Modifier.height(12.dp))
                            com.green.note.ui.ReviewButton(onClick = ::act, enabled = action.winnersUrl.isNotEmpty() || action.canRegister,
                                modifier = Modifier.fillMaxWidth().height(40.dp), shape = RoundedCornerShape(6.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xff009688), contentColor = Color.White)) {
                                Text(action.label, fontSize = 16.sp)
                            }
                            if (notice.isNotEmpty()) com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = { showNotice = true }, contentPadding = PaddingValues(0.dp),
                                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurfaceVariant)) {
                                MaterialGlyph("help_outline", size = 12.dp); com.green.note.ui.ReviewButtonIconGap(); Text("众测须知", fontSize = 12.sp)
                            }
                        }
                    }
                }
                if (notice.isNotEmpty()) Card {
                    Text("报名须知", fontSize = 16.sp, fontWeight = adjustedWeight(600)); Spacer(Modifier.height(12.dp))
                    EventNoticeText(notice, expanded)
                    com.green.note.ui.ReviewTextButton(onClick = { expanded = !expanded }, contentPadding = PaddingValues(0.dp), colors = ButtonDefaults.textButtonColors(contentColor = Color(0xff009688))) { Text(if (expanded) "收起" else "展开") }
                }
                if (sponsors.isNotEmpty()) Card {
                    Text("主办方", fontSize = 16.sp, fontWeight = adjustedWeight(600)); Spacer(Modifier.height(12.dp))
                    sponsors.forEach { user -> key(user.text("uid")) { EventSponsor(api, user, onUser) } }
                }
                if (prizes.isNotEmpty()) Card {
                    Text("活动奖品", fontSize = 16.sp, fontWeight = adjustedWeight(600)); Spacer(Modifier.height(12.dp))
                    prizes.forEach { prize -> Row(verticalAlignment = Alignment.CenterVertically) {
                        if (prize.text("logo").isNotEmpty()) ContentImage(api, prize.text("logo"), null, Modifier.size(48.dp), ContentScale.Fit, heroCornerRadius = 0.dp)
                        Spacer(Modifier.width(12.dp)); Text(prize.text("title"), Modifier.weight(1f), fontSize = 16.sp)
                    } }
                }
            }
        }
        EventNestedContent(Modifier.fillMaxSize().background(background), header = { Header() }, tabs = {
            if (tabs.isNotEmpty()) TabRow(pager.currentPage, Modifier.height(48.dp), containerColor = cardColor, contentColor = Color(0xff009688), divider = {}, indicator = { positions ->
                if (positions.isNotEmpty()) {
                    val value = (pager.currentPage + pager.currentPageOffsetFraction).coerceIn(0f, positions.lastIndex.toFloat())
                    fun bounds(at: Float): Pair<Float, Float> {
                        val low = kotlin.math.floor(at).toInt().coerceIn(0, positions.lastIndex)
                        val high = kotlin.math.ceil(at).toInt().coerceIn(0, positions.lastIndex)
                        fun edge(index: Int): Pair<Float, Float> {
                            val position = positions[index]; val width = tabWidths[index] ?: 24.dp
                            val left = (position.left + (position.width - width) / 2).value
                            return left to left + width.value
                        }
                        val a = edge(low); val b = edge(high); val fraction = at - low
                        return a.first + (b.first - a.first) * fraction to a.second + (b.second - a.second) * fraction
                    }
                    val journey = indicatorJourney
                    val from = journey?.first ?: kotlin.math.floor(value)
                    val to = journey?.second?.toFloat() ?: kotlin.math.ceil(value)
                    val fraction = if (from == to) 0f else ((value - from) / (to - from)).coerceIn(0f, 1f)
                    val a = bounds(from); val b = bounds(to)
                    val accelerate = (1 - kotlin.math.cos(fraction * Math.PI / 2)).toFloat()
                    val decelerate = kotlin.math.sin(fraction * Math.PI / 2).toFloat()
                    val left = a.first + (b.first - a.first) * if (to >= from) accelerate else decelerate
                    val right = a.second + (b.second - a.second) * if (to >= from) decelerate else accelerate
                    Box(Modifier.fillMaxWidth().wrapContentSize(Alignment.BottomStart).offset(x = left.dp)
                        .width((right - left).coerceAtLeast(0f).dp).height(3.dp).background(Color(0xff009688), RoundedCornerShape(topStart = 3.dp, topEnd = 3.dp)))
                }
            }) {
                tabs.forEachIndexed { index, tab -> Tab(pager.currentPage == index, com.green.note.ui.rememberHapticClick {
                    val generation = ++indicatorGeneration
                    indicatorJourney = (pager.currentPage + pager.currentPageOffsetFraction) to index
                    scope.launch { try { pager.animateScrollToPage(index, animationSpec = androidx.compose.animation.core.tween(300, easing = androidx.compose.animation.core.CubicBezierEasing(.25f, .1f, .25f, 1f))) } finally { if (generation == indicatorGeneration) indicatorJourney = null } }
                }, Modifier.height(48.dp),
                    selectedContentColor = Color(0xff009688), unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    text = { Text(tab.text("title"), fontSize = 18.sp, onTextLayout = { layout -> tabWidths[index] = with(density) { layout.size.width.toDp() } }) }) }
            }
        }) {
            if (tabs.isEmpty()) {
                val scroll = rememberScrollState(); ReviewScrollActivity(scroll)
                Box(Modifier.fillMaxSize().verticalScroll(scroll), contentAlignment = Alignment.Center) { Text("暂无相关讨论") }
            }
            else HorizontalPager(pager, Modifier.fillMaxSize()) { page ->
                ActivityTabBody(api, tabs[page], onOpen, onUser, onLink, onGallery, onLike, onMore, onBack)
            }
        }
        if (showNotice) {
            val height = with(density) { LocalWindowInfo.current.containerSize.height.toDp() } * .75f
            ReviewModalBottomSheet(onDismissRequest = { showNotice = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
                val scroll = rememberScrollState(); ReviewScrollActivity(scroll)
                Column(Modifier.height(height).verticalScroll(scroll).padding(20.dp)) {
                    Text("众测须知", style = MaterialTheme.typography.titleLarge); Spacer(Modifier.height(16.dp)); Text(notice)
                }
            }
        }
    }
}

@Composable
private fun EventNoticeText(notice: String, expanded: Boolean) {
    var overflows by remember(notice, expanded) { mutableStateOf(false) }
    val fadeHeight = with(LocalDensity.current) { 21.sp.toPx() }
    val fade = if (!expanded && overflows) Modifier.graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
        drawContent()
        drawRect(Brush.verticalGradient(listOf(Color.White, Color.Transparent), startY = (size.height - fadeHeight).coerceAtLeast(0f), endY = size.height), blendMode = BlendMode.DstIn)
    } else Modifier
    Text(notice, fade, maxLines = if (expanded) Int.MAX_VALUE else 5, overflow = TextOverflow.Clip,
        fontSize = 14.sp, lineHeight = 21.sp, onTextLayout = { overflows = it.hasVisualOverflow })
}

@Composable
private fun EventSponsor(api: ContentApi, user: JSONObject, onUser: (String) -> Unit) {
    val uid = user.text("uid")
    var following by remember(uid) { mutableStateOf(api.isUserFollowed(user)) }
    var busy by remember(uid) { mutableStateOf(false) }
    val identity = remember(api, uid) { api.imageCacheScope() }
    val session = LocalContentSession.current
    val scope = rememberCoroutineScope()
    val toast = remember { AppToastState() }
    fun follow() {
        if (busy) return
        if (!session.authenticated && !session.anonymous) { toast.showSnackbar("请先登录"); return }
        scope.launch {
            busy = true
            try {
                check(identity == api.imageCacheScope()) { "账号已变更" }
                val profile = if (session.anonymous) api.request("/v6/user/space", query = mapOf("uid" to uid)).optJSONObject("data") ?: user else user
                check(identity == api.imageCacheScope()) { "账号已变更" }
                following = api.followUser(JSONObject(user.toString()).apply {
                    listOf("username", "userAvatar").forEach { key -> profile.text(key).takeIf(String::isNotEmpty)?.let { put(key, it) } }
                }, following)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { toast.showSnackbar(failure.message ?: "关注失败") }
            finally { busy = false }
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(40.dp).clickable { onUser(uid) }) {
            ContentAvatar(api, user.text("userAvatar"), user.text("username"), 40.dp)
            if (user.text("verify_status") == "1") Box(Modifier.align(Alignment.BottomEnd).size(14.dp)
                .background(Color(0xff448aff), CircleShape).border(1.5.dp, MaterialTheme.colorScheme.surface, CircleShape), contentAlignment = Alignment.Center) {
                MaterialGlyph("check_rounded", size = 10.dp, color = Color.White)
            }
        }
        Spacer(Modifier.width(16.dp)); Text(user.text("username"), Modifier.weight(1f), fontSize = 16.sp)
        com.green.note.ui.ReviewOutlinedButton(onClick = ::follow, enabled = !busy, modifier = Modifier.defaultMinSize(minWidth = 56.dp, minHeight = 28.dp),
            contentPadding = PaddingValues(horizontal = 12.dp), border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xff009688)),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xff009688))) { Text(if (following) "已关注" else "关注", fontSize = 12.sp) }
    }
}

// Header is measured unbounded (a long notice/sponsor list may exceed the viewport), but only
// the viewport is placed. The inner tab owns its lazy list; upward scroll collapses this header
// first, and downward unconsumed scroll expands it only when the inner list has reached its start.
@Composable
private fun EventNestedContent(modifier: Modifier, header: @Composable () -> Unit, tabs: @Composable () -> Unit, body: @Composable () -> Unit) {
    var collapsed by remember { mutableFloatStateOf(0f) }
    var headerHeight by remember { mutableIntStateOf(0) }
    fun consume(delta: Float): Float {
        val old = collapsed
        collapsed = (collapsed - delta).coerceIn(0f, headerHeight.toFloat())
        return old - collapsed
    }
    val headerScroll = rememberScrollableState(::consume)
    val scope = rememberCoroutineScope()
    ReviewScrollActivity(headerScroll)
    val nested = remember { object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset = if (available.y < 0) Offset(0f, consume(available.y)) else Offset.Zero
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset = if (available.y > 0) Offset(0f, consume(available.y)) else Offset.Zero
    } }
    Layout(modifier = modifier.clipToBounds().nestedScroll(nested).semantics {
        verticalScrollAxisRange = ScrollAxisRange({ collapsed }, { headerHeight.toFloat() })
        scrollBy { _, y -> scope.launch { headerScroll.scroll { scrollBy(-y) } }; true }
    }, content = {
        Box(Modifier.fillMaxWidth().scrollable(headerScroll, Orientation.Vertical)) { header() }
        Box(Modifier.fillMaxWidth()) { tabs() }
        Box(Modifier.fillMaxSize()) { body() }
    }) { measurables, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val heading = measurables[0].measure(Constraints.fixedWidth(width))
        headerHeight = heading.height
        if (collapsed > heading.height) collapsed = heading.height.toFloat()
        val shift = collapsed.coerceIn(0f, heading.height.toFloat()).toInt()
        val tabBar = measurables[1].measure(Constraints.fixedWidth(width))
        val tabY = heading.height - shift
        val bodyY = tabY + tabBar.height
        val content = measurables[2].measure(Constraints.fixed(width, (height - bodyY).coerceAtLeast(0)))
        layout(width, height) {
            heading.placeRelative(0, -shift)
            tabBar.placeRelative(0, tabY)
            content.placeRelative(0, bodyY)
        }
    }
}
