package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.green.note.ui.*
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun homeScrollMetrics(firstIndex: Int, lastIndex: Int, firstOffset: Float, lastEnd: Float,
    itemCount: Int, viewportEnd: Float, firstScrollOffset: Float): Pair<Float, Float> {
    val average = ((lastEnd - firstOffset) / (lastIndex - firstIndex + 1).coerceAtLeast(1)).coerceAtLeast(0f)
    val remaining = (lastEnd + average * (itemCount - lastIndex - 1).coerceAtLeast(0) - viewportEnd).coerceAtLeast(0f)
    val pixels = (firstIndex * average + firstScrollOffset).coerceAtLeast(0f)
    return remaining to if (pixels + remaining == 0f) 0f else pixels / (pixels + remaining)
}

@Composable
internal fun HomeFeedScreen(api: ContentApi, state: HomeFeedState, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    val scope = rememberCoroutineScope(); val lifecycle = LocalLifecycleOwner.current.lifecycle
    val density = LocalDensity.current
    val preferences = LocalAppPreferences.current
    val bottomInset = with(density) { WindowInsets.navigationBars.getBottom(this).toDp() }
    val bottom = 20.dp + if (preferences.floatingNavBar)
        floatingNavigationHeight + floatingNavigationBottom(bottomInset) - bottomInset else 0.dp
    ReviewScrollActivity(state.scroll)
    LaunchedEffect(state, lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
        homeCacheRevision.collect { state.resume() }
    } }
    LaunchedEffect(state, lifecycle, density) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
        snapshotFlow {
            if (state.busy || state.error != null || !state.more && !state.hasBuffer) return@snapshotFlow null
            val info = state.scroll.layoutInfo; val visible = info.visibleItemsInfo
            val first = visible.firstOrNull(); val last = visible.lastOrNull()
            // shortcut: lazy engines realize different cache windows; compare the loading threshold on-device before changing cache policy.
            val metrics = if (first == null || last == null) Float.MAX_VALUE to 0f else homeScrollMetrics(first.index, last.index, first.offset.toFloat(),
                (last.offset + last.size).toFloat(), info.totalItemsCount, info.viewportEndOffset.toFloat(), state.scroll.firstVisibleItemScrollOffset.toFloat())
            val remaining = metrics.first / density.density
            when {
                state.hasBuffer && (remaining < 900 || metrics.second >= .45f) -> true to state.rows.size
                state.more && state.rows.isNotEmpty() && remaining < if (state.channelId == "headline") 1000 else 520 -> false to state.rows.size
                else -> null
            }
        }.collect { action ->
            if (action != null && !state.busy && state.error == null) {
                if (action.first) state.releaseBuffer() else state.load()
            }
        }
    } }
    if (state.rows.isEmpty() && state.cards.isEmpty()) {
        if (state.busy || !state.initialized) HomeFeedSkeleton()
        else HomeFeedError(state.error ?: "酷安暂时没有返回动态", Modifier.fillMaxSize()) { scope.launch { state.load(true) } }
        return
    }
    ReviewRefreshBox(state.refreshing, { scope.launch { state.load(true) } }, Modifier.fillMaxSize(), failed = state.error != null) {
        LazyColumn(state = state.scroll, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 2.dp, bottom = bottom)) {
            if (state.channelId in setOf("headline", "hot", "tutorial", "video") || state.cards.isNotEmpty()) item("home-header") {
                HomeFeedHeader(api, state.channelId, state.cards, state.activeIndex, { item, index -> scope.launch { state.select(item, index) } }, onOpen)
            }
            itemsIndexed(state.rows, key = { _, feed -> "home-feed:${feed.text("id")}" }) { index, original ->
                val rank = if (state.ranked && index < 20) index + 1 else 0
                val feed = remember(original, rank, state.channelId) { JSONObject(original.toString()).put("_composeHeadline", state.channelId == "headline").put("_composeRankNumber", rank) }
                FeedRow(api, feed, onOpen = onOpen, onUser = onUser, onLink = onLink, onGallery = onGallery, onLike = onLike, onMore = onMore)
            }
            item("home-footer") {
                when {
                    state.error != null -> com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = { scope.launch { state.load(state.rows.isEmpty()) } }, modifier = Modifier.fillMaxWidth()) {
                        MaterialGlyph("refresh_rounded"); ReviewButtonIconGap(); Text("加载失败，点击重试：${state.error}")
                    }
                    state.busy -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { ReviewCircularProgress() }
                    state.rows.isEmpty() -> HomeFeedError("酷安暂时没有返回动态", Modifier.fillMaxWidth()) { scope.launch { state.load(true) } }
                    else -> Spacer(Modifier.height(12.dp))
                }
            }
        }
    }
}

@Composable
private fun HomeFeedError(message: String, modifier: Modifier, retry: () -> Unit) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(Modifier.padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            MaterialGlyph("cloud_off_outlined", size = 38.dp, color = MaterialTheme.colorScheme.outline)
            Spacer(Modifier.height(12.dp)); Text(message, textAlign = TextAlign.Center)
            Spacer(Modifier.height(14.dp)); com.green.note.ui.ReviewFilledTonalButton(onClick = retry) { Text("重试") }
        }
    }
}

@Composable
internal fun HomeFeedSkeleton() {
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val bar = if (dark) Color.White.copy(alpha = .08f) else Color.Black.copy(alpha = .06f)
    LazyColumn(Modifier.fillMaxSize(), userScrollEnabled = false, contentPadding = PaddingValues(vertical = 8.dp)) {
        items(4) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp).fillMaxWidth().background(MaterialTheme.colorScheme.surface, RoundedCornerShape(16.dp)).padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(36.dp).background(bar, CircleShape)); Spacer(Modifier.width(10.dp))
                    Column { Box(Modifier.size(90.dp, 12.dp).background(bar, RoundedCornerShape(6.dp))); Spacer(Modifier.height(6.dp)); Box(Modifier.size(60.dp, 9.dp).background(bar, RoundedCornerShape(4.5.dp))) }
                }
                Spacer(Modifier.height(14.dp)); Box(Modifier.fillMaxWidth().height(13.dp).background(bar, RoundedCornerShape(6.dp)))
                Spacer(Modifier.height(8.dp)); Box(Modifier.width(220.dp).height(13.dp).background(bar, RoundedCornerShape(6.dp))); Spacer(Modifier.height(12.dp))
            }
        }
    }
}
