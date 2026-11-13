package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ContentList(api: ContentApi, state: ContentListState, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit,
    onMore: (JSONObject) -> Unit, modifier: Modifier = Modifier,
    itemContent: (@Composable (JSONObject) -> Unit)? = null, indexedItemContent: (@Composable (Int, JSONObject) -> Unit)? = null, beforeRows: (@Composable () -> Unit)? = null,
    initialBodyAnchor: Boolean = false, bodyAnchorIndex: Int = 1, lazyItemCount: Int = 0, lazyContent: (androidx.compose.foundation.lazy.LazyListScope.() -> Unit)? = null,
    contentPadding: PaddingValues? = null, scroll: androidx.compose.foundation.lazy.LazyListState = rememberLazyListState(), selectable: Boolean = false,
    refreshAction: (() -> Unit)? = null, emptyContent: (@Composable () -> Unit)? = null, endText: String = "", showAccessErrors: Boolean = true, commentErrors: Boolean = false, emptyHeightFraction: Float? = null,
    refreshShowText: Boolean = true, refreshTextDimension: androidx.compose.ui.unit.Dp? = null,
    flingBehavior: androidx.compose.foundation.gestures.FlingBehavior = androidx.compose.foundation.gestures.ScrollableDefaults.flingBehavior(),
    loadInitially: Boolean = true, fallbackRows: List<JSONObject> = emptyList(),
    accessErrorContent: (@Composable (Boolean, () -> Unit) -> Unit)? = null, header: (@Composable () -> Unit)? = null) {
    com.green.note.ui.ReviewScrollActivity(scroll)
    val scope = rememberCoroutineScope()
    val deviceRecovery = LocalCommentDeviceRecovery.current.takeIf { commentErrors }
    val importing = deviceRecovery?.importing == true
    val importRevision = deviceRecovery?.revision ?: 0L
    var handledImportRevision by remember(state) { mutableLongStateOf(importRevision) }
    val emptyHeight = with(androidx.compose.ui.platform.LocalDensity.current) {
        (androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.height * (emptyHeightFraction ?: if (itemContent == null && indexedItemContent == null) .55f else .2f)).toDp()
    }
    val displayedRows = state.rows.ifEmpty { fallbackRows }
    val recoveryBeforeRows = commentErrors && state.accessRestricted
    val listPadding = contentPadding ?: if (displayedRows.isEmpty()) PaddingValues(0.dp) else PaddingValues(top = if (header == null) 10.dp else 0.dp, bottom = 24.dp)
    var anchored by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(initialBodyAnchor, bodyAnchorIndex, recoveryBeforeRows) { if (initialBodyAnchor && !anchored) { scroll.scrollToItem(if (header == null) 0 else bodyAnchorIndex + if (recoveryBeforeRows) 1 else 0); anchored = true } }
    LaunchedEffect(state, loadInitially, importing, importRevision) {
        if (importing) return@LaunchedEffect
        val imported = handledImportRevision != importRevision
        handledImportRevision = importRevision
        // Views that bind or reload outside this list opt out with loadInitially = false.
        if (loadInitially && imported) state.load(true)
        else if (loadInitially && state.needsInitialLoad && state.error == null) state.load(refresh = state.rows.isNotEmpty())
    }
    LaunchedEffect(state, scroll, lazyItemCount, header != null, beforeRows != null, recoveryBeforeRows, importing) {
        if (importing) return@LaunchedEffect
        snapshotFlow { Triple(scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0, state.rows.size, state.busy) }.distinctUntilChanged().collect { (last, count, busy) ->
            val leading = lazyItemCount + (if (header == null) 0 else 1) + (if (beforeRows == null) 0 else 1) + (if (recoveryBeforeRows) 1 else 0)
            if (!busy && count > 0 && last >= leading + count - 3 && state.more && state.error == null) state.load()
        }
    }
    com.green.note.ui.ReviewRefreshBox(isRefreshing = state.refreshing, onRefresh = { if (!importing) { if (refreshAction != null) refreshAction() else scope.launch { state.load(true) } } }, modifier = modifier.fillMaxSize(), failed = state.error != null, showText = refreshShowText, textDimension = refreshTextDimension) {
        val list: @Composable () -> Unit = { LazyColumn(state = scroll, modifier = Modifier.fillMaxSize(), contentPadding = listPadding, flingBehavior = flingBehavior) {
            if (header != null) item { header() }
            lazyContent?.invoke(this)
            if (recoveryBeforeRows) item(key = "comment:recovery") {
                if (accessErrorContent != null) accessErrorContent(displayedRows.isNotEmpty()) { scope.launch { state.load() } }
                else CommentRecoveryNotice(state, displayedRows.isNotEmpty(),
                    onRetry = { scope.launch { state.load() } }, onVerify = { scope.launch { state.verify(api) } })
            }
            if (beforeRows != null) item { beforeRows() }
            itemsIndexed(displayedRows, key = { _, row -> entityKey(row) }) { index, original ->
                fun grouped(item: JSONObject?) = item?.optBoolean("_composeGroupProducts") == true && item.text("entityType") == "product"
                val row = if (grouped(original)) JSONObject(original.toString()).put("_composeGroupStart", !grouped(displayedRows.getOrNull(index - 1))).put("_composeGroupEnd", !grouped(displayedRows.getOrNull(index + 1))) else original
                if (indexedItemContent != null) indexedItemContent(index, row) else if (itemContent != null) itemContent(row)
                else EntityRow(api, row, onOpen, onUser, onLink, onGallery, onLike, onMore)

            }
            if (recoveryBeforeRows) {
                // The recovery notice already appears before the comments; keep readable rows intact.
            } else if (state.accessRestricted && accessErrorContent != null) item {
                accessErrorContent(displayedRows.isNotEmpty()) { scope.launch { state.load() } }
            } else if (state.accessRestricted && state.verificationChallenge != null) item {
                Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(if (displayedRows.isNotEmpty()) "已保留已加载的评论，剩余评论暂不可用" else "暂时无法加载评论",
                        color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                    if (state.verificationChallenge == null) Text(state.error.orEmpty(),
                        color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                    Row {
                        if (state.verificationChallenge != null) com.green.note.ui.ReviewTextButton(enabled = !state.busy,
                            onClick = { scope.launch { state.verify(api) } }) { Text(if (state.verifying) "正在验证" else "完成验证并重试") }
                        com.green.note.ui.ReviewTextButton(enabled = !state.busy, onClick = { scope.launch { state.load() } }) { Text("重试") }
                    }
                }
            } else if (displayedRows.isEmpty()) item {
                if (emptyContent != null && !state.busy && state.error == null) emptyContent()
                else Box(Modifier.fillMaxWidth().height(emptyHeight), contentAlignment = Alignment.Center) {
                    if (state.busy) com.green.note.ui.ReviewCircularProgress()
                    else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        val hidden = !showAccessErrors && isContentAccessError(state.error)
                        Text(if (hidden) "暂无内容" else state.error ?: "暂无内容")
                        if (state.error != null && !hidden) com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.load() } }) { Text("重试") }
                    }
                }
            } else if (state.busy || state.error != null || !state.more && endText.isNotEmpty()) item {
                when {
                    state.busy -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
                    state.error != null -> if (!isContentAccessError(state.error)) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.load() } }) { Text("加载失败，点击重试：${state.error}") } }
                    else -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { Text(endText, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp) }
                }
            }
        } }
        if (selectable) androidx.compose.foundation.text.selection.SelectionContainer(Modifier.fillMaxSize()) { list() } else list()
    }
}

internal fun isContentAccessError(error: String?): Boolean = error != null &&
    (listOf("验证码", "受限", "限制", "403").any(error::contains) || error.contains("captcha", ignoreCase = true))

@Composable
internal fun EntityRow(api: ContentApi, row: JSONObject, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    if (hasSpecializedCard(row)) { SpecializedEntityCard(api, row, onOpen, onUser, onLink, onGallery, onLike, onMore); return }
    val type = row.text("entityType", "entity_type").lowercase()
    when {
        type == "feed_detail_reply_sponsor_card" || row.text("message") == "FEED_DETAIL_REPLY_SPONSOR_CARD" -> Unit

        type == "card" -> {
            val children = row.optJSONArray("entities").objects()
            if (row.text("title").isNotEmpty()) Row(Modifier.fillMaxWidth().clickable { onOpen(row) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(row.text("title"), Modifier.weight(1f), fontSize = 16.sp, fontWeight = FontWeight.Medium)
                if (row.text("url").isNotEmpty()) MaterialGlyph("chevron_right_rounded", size = 20.dp)
            }
            children.forEach { child -> EntityRow(api, child, onOpen, onUser, onLink, onGallery, onLike, onMore) }
        }
        type.contains("collection") -> CollectionLibraryTile(row, true, true, onOpen, grouped = false)
        contentEntityIsFeed(row) && row.text("id", "feedId", "feed_id").isNotEmpty() -> FeedRow(api, row, onOpen = onOpen,
            onUser = onUser, onLink = onLink, onGallery = onGallery, onLike = onLike, onMore = onMore)
        else -> ContentEntityRow(api, row, onOpen)
    }
}
