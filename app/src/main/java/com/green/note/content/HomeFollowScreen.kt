package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewCircularProgress
import com.green.note.ui.ReviewRefreshBox
import com.green.note.ui.ReviewScrollActivity
import com.green.note.ui.floatingNavigationBottom
import com.green.note.ui.floatingNavigationHeight
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
internal fun HomeFollowScreen(api: ContentApi, session: ContentSession, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit,
    onMore: (JSONObject) -> Unit, onLogin: () -> Unit, official: OfficialHomeFollowState?, local: LocalHomeFollowState?) {
    val preferences = com.green.note.ui.LocalAppPreferences.current
    val bottomInset = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    // Scaffold already excludes the system inset; a floating bar still overlays the content.
    val bottom = 20.dp + if (preferences.floatingNavBar)
        floatingNavigationHeight + floatingNavigationBottom(bottomInset) - bottomInset else 0.dp
    if (session.anonymous) {
        if (local == null) FollowStatus("正在读取关注来源", true)
        else key(local) { LocalFollowTimeline(api, local, bottom, onOpen, onUser, onLink, onGallery, onLike, onMore) }
    } else if (!session.authenticated) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(Modifier.padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            MaterialGlyph("person_add_alt_1_rounded", size = 42.dp); Spacer(Modifier.height(12.dp))
            Text("登录后查看关注动态", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(6.dp)); Text("未登录时酷安可能返回推荐内容，不能代表你的关注列表。", textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp)); com.green.note.ui.ReviewFilledTonalButton(onClick = onLogin) { Text("登录酷安") }
        }
    } else if (official != null) key(official) { OfficialFollowTimeline(api, official, bottom, onOpen, onUser, onLink, onGallery, onLike, onMore) }
}

@Composable
private fun OfficialFollowTimeline(api: ContentApi, state: OfficialHomeFollowState, bottom: androidx.compose.ui.unit.Dp,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    val scope = rememberCoroutineScope(); val lifecycle = LocalLifecycleOwner.current.lifecycle
    val density = LocalDensity.current.density
    ReviewScrollActivity(state.scroll)
    LaunchedEffect(state, lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
        state.resume()
        awaitCancellation()
    } }
    LaunchedEffect(state, lifecycle, density) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
        snapshotFlow {
            val info = state.scroll.layoutInfo; val visible = info.visibleItemsInfo
            val first = visible.firstOrNull(); val last = visible.lastOrNull()
            val metrics = if (first == null || last == null) Float.MAX_VALUE to 0f else homeScrollMetrics(first.index, last.index, first.offset.toFloat(),
                (last.offset + last.size).toFloat(), info.totalItemsCount, info.viewportEndOffset.toFloat(), state.scroll.firstVisibleItemScrollOffset.toFloat())
            listOf(metrics.first / density, metrics.second, state.rows.size.toFloat(), if (state.busy) 1f else 0f, if (state.hasBuffer) 1f else 0f)
        }.distinctUntilChanged().collect { metrics ->
            if (!state.busy && state.error == null) {
                if (state.hasBuffer && (metrics[0] < 900 || metrics[1] >= .45f)) state.releaseBuffer()
                else if (state.rows.isNotEmpty() && metrics[0] < 520) state.load()
            }
        }
    } }
    com.green.note.ui.OfficialHomeTheme {
        val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
        ReviewRefreshBox(state.refreshing, { scope.launch { state.load(true) } }, Modifier.fillMaxSize().background(if (dark) Color(0xff101010) else MaterialTheme.colorScheme.surface), failed = state.error != null) {
            LazyColumn(state = state.scroll, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 2.dp, bottom = bottom)) {
                item("follow-header") { FollowingHeader(api, state.recentCards + state.cards, state.recentFeeds, state.selected, onUser) { type -> scope.launch { state.select(type) } } }
                items(state.rows, key = { "follow:${it.text("id")}" }) { feed -> FeedRow(api, feed, onOpen = onOpen, onUser = onUser, onLink = onLink, onGallery = onGallery, onLike = onLike, onMore = onMore) }
                item("follow-footer") {
                    when {
                        state.error != null -> com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = { scope.launch { state.load(state.rows.isEmpty()) } }) { MaterialGlyph("refresh_rounded"); com.green.note.ui.ReviewButtonIconGap(); Text("加载失败，点击重试：${state.error}") }
                        state.busy || !state.initialized -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { ReviewCircularProgress() }
                        state.rows.isEmpty() -> Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            MaterialGlyph("cloud_off_outlined", size = 38.dp, color = MaterialTheme.colorScheme.outline); Spacer(Modifier.height(12.dp))
                            Text("酷安暂时没有返回动态", textAlign = TextAlign.Center); Spacer(Modifier.height(14.dp))
                            com.green.note.ui.ReviewFilledTonalButton(onClick = { scope.launch { state.load(true) } }) { Text("重试") }
                        }
                        else -> Spacer(Modifier.height(12.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun FollowingHeader(api: ContentApi, cards: List<JSONObject>, feeds: List<JSONObject>, selected: String, onUser: (String) -> Unit, onSelect: (String) -> Unit) {
    val users = remember(cards, feeds) { recentFollowingUsers(cards, feeds) }
    val scheme = MaterialTheme.colorScheme; val dark = scheme.surface.luminance() < .5f
    Column(Modifier.fillMaxWidth().background(if (dark) Color(0xff101010) else scheme.surface)) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(start = 8.dp, top = 6.dp, end = 8.dp, bottom = 2.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.width(58.dp).clickable { onSelect("") }, horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(38.dp).background(Color(0xff00ac86), CircleShape), contentAlignment = Alignment.Center) { MaterialGlyph("people", size = 20.dp, color = Color.White) }
                Spacer(Modifier.height(4.dp)); Text("最近更新", fontSize = 11.5.sp)
            }
            users.forEach { user -> Column(Modifier.width(58.dp).clickable { onUser(user.text("uid")) }, horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(38.dp)) {
                    ContentAvatar(api, user.text("userAvatar"), "", 38.dp)
                    if (user.text("verify_status") in setOf("1", "true")) Box(Modifier.align(Alignment.BottomEnd).size(13.3.dp)
                        .background(if (user.text("verify_show_type").toIntOrNull()?.let { it != 0 } == true) Color(0xff448aff) else Color(0xffffc107), CircleShape)
                        .border(1.5.dp, scheme.surface, CircleShape), contentAlignment = Alignment.Center) { MaterialGlyph("check_rounded", size = 9.5.dp, color = Color.White) }
                }
                Spacer(Modifier.height(4.dp)); Text(user.text("username"), maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 11.5.sp)
            } }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(start = 8.dp, top = 2.dp, end = 8.dp, bottom = 4.dp)) {
            listOf("" to "全部", "circle" to "好友关注", "topic" to "话题关注", "product" to "数码关注", "apk" to "应用关注").forEach { (value, label) ->
                com.green.note.ui.ReviewChoiceChip(selected==value,onClick={onSelect(value)},label={Text(label)},modifier=Modifier.padding(end=8.dp),
                    showCheckmark=false,shrinkWrap=true,compact=true,padding=PaddingValues(horizontal=10.dp),labelPadding=PaddingValues(0.dp),
                    side=androidx.compose.foundation.BorderStroke(1.2.dp,if(selected==value)scheme.primary else Color.Transparent),
                    backgroundColor=if(dark)Color(0xff1e1e1e)else scheme.surfaceContainerLow,selectedColor=if(dark)Color(0xff1e1e1e)else scheme.primaryContainer,
                    labelStyle=androidx.compose.ui.text.TextStyle(fontSize=12.sp,color=if(selected==value)scheme.primary else scheme.onSurface))
            }
        }
    }
}

@Composable
private fun LocalFollowTimeline(api: ContentApi, state: LocalHomeFollowState, bottom: androidx.compose.ui.unit.Dp,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    val scope = rememberCoroutineScope(); val lifecycle = LocalLifecycleOwner.current.lifecycle
    val density = LocalDensity.current.density
    ReviewScrollActivity(state.scroll)
    LaunchedEffect(state, lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
        if (!state.initialized && state.sourceError == null) state.refresh()
        awaitCancellation()
    } }
    LaunchedEffect(state) { snapshotFlow {
        val info = state.scroll.layoutInfo; val visible = info.visibleItemsInfo; val last = visible.lastOrNull()
        val average = visible.map { it.size }.average().takeIf { it.isFinite() } ?: 0.0
        if (last == null) Double.MAX_VALUE else ((info.totalItemsCount - last.index - 1) * average + last.offset + last.size - info.viewportEndOffset).coerceAtLeast(0.0) / density
    }.distinctUntilChanged().collect { remaining -> if (state.rows.isNotEmpty() && remaining < 650 && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) state.loadMore() } }
    ReviewRefreshBox(state.loading && state.initialized, { scope.launch { state.refresh() } }, Modifier.fillMaxSize(), failed = state.sourceError != null || state.failed > 0) {
        LazyColumn(state = state.scroll, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottom)) {
            items(state.rows, key = { "local-follow:${it.text("id")}" }) { feed -> FeedRow(api, feed, onOpen = onOpen, onUser = onUser, onLink = onLink, onGallery = onGallery, onLike = onLike, onMore = onMore) }
            item("local-follow-footer") {
                val waiting = state.loading || !state.initialized && state.sourceError == null
                if (state.rows.isEmpty()) when {
                    waiting -> FollowStatus(if (state.readingFollowing || !state.initialized && state.source.publicUid.isNotEmpty()) "正在读取 UID 对应的关注列表" else "正在汇总关注动态 ${state.progress}/${state.total}", true)
                    state.sourceError != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        FollowStatus("读取 UID 对应的关注列表失败：${state.sourceError}"); com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.refresh() } }) { Text("重试") }
                    }
                    state.userIds.isEmpty() -> FollowStatus(if (state.source.publicUid.isNotEmpty()) "该 UID 暂时没有关注用户" else "在博主主页点击关注，最新动态会显示在这里")
                    state.hasMore -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        FollowStatus(if (state.failed > 0) "${state.failed} 位用户暂时无法读取，可下拉重试" else "暂时没有较新的动态")
                        com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.loadMore() } }) { Text("加载更早动态") }
                    }
                    state.failed > 0 -> FollowStatus("获取关注动态失败，向下拉动重试")
                    else -> FollowStatus("你关注的用户暂时没有发布动态")
                } else when {
                    state.loading || state.loadingMore -> FollowStatusRow(if (state.loading) "正在汇总关注动态 ${state.progress}/${state.total}" else "正在加载更早动态", true)
                    state.sourceError != null -> FollowStatusRow("刷新关注列表失败，已保留现有动态：${state.sourceError}")
                    state.hasMore -> Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                        com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.loadMore() } }) { Text(if (state.failed > 0) "继续加载（${state.failed} 位用户暂时不可用）" else "加载更早动态") }
                    }
                    state.failed > 0 -> FollowStatusRow("${state.failed} 位用户的动态加载失败，下拉可重试")
                    else -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { Text("没有更多动态") }
                }
            }
        }
    }
}

@Composable
private fun FollowStatus(message: String, progress: Boolean = false) {
    Box(Modifier.fillMaxWidth().height(260.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (progress) { ReviewCircularProgress(Modifier.size(28.dp), strokeWidth = 2.5.dp); Spacer(Modifier.height(14.dp)) }
            Text(message, Modifier.padding(horizontal = 28.dp), textAlign = TextAlign.Center)
        }
    }
}
@Composable
private fun FollowStatusRow(message: String, progress: Boolean = false) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (progress) { ReviewCircularProgress(Modifier.size(20.dp), strokeWidth = 2.dp); Spacer(Modifier.width(16.dp)) }
        Text(message, style = MaterialTheme.typography.bodyMedium, fontSize = 15.sp, lineHeight = 20.25.sp, fontWeight = com.green.note.ui.adjustedWeight(600))
    }
}
