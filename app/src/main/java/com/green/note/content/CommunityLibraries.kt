package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.green.note.ui.AppToastState
import com.green.note.ui.LocalAppPreferences
import com.green.note.ui.LocalScaffoldColor
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewRefreshBox
import com.green.note.ui.ReviewScrollActivity
import com.green.note.ui.adjustedWeight
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONObject

internal data class CommunityLibraryRoute(val title: String, val path: String)
internal fun communityLibraryRoutes(kind: String): List<CommunityLibraryRoute> = when (kind) {
    "history" -> listOf(CommunityLibraryRoute("浏览历史", "/v6/user/hitHistoryList"))
    "anylist" -> listOf(CommunityLibraryRoute("万物清单", "/v6/user/productAlbumList"))
    "dyh" -> listOf(CommunityLibraryRoute("关注的号", "/v6/user/dyhFollowList"), CommunityLibraryRoute("订阅的号", "/v6/user/dyhSubscribe"), CommunityLibraryRoute("管理的号", "/v6/user/editorDyhList"))
    "albums" -> listOf(CommunityLibraryRoute("我的应用集", "/v6/user/albumList"))
    else -> error("不支持的资料库")
}
internal fun communityLibraryMatches(row: JSONObject, query: String): Boolean = query.isBlank() || row.toString().lowercase().contains(query.trim().lowercase())

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CommunityLibraryScreen(api: ContentApi, kind: String, uid: String, session: ContentSession, onBack: () -> Unit,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit,
    onCreate: () -> Unit, initialTab: Int = 0, creationRevision: Int = 0) {
    val routes = remember(kind) { communityLibraryRoutes(kind) }
    var selected by rememberSaveable(kind, uid) { mutableIntStateOf(initialTab.coerceIn(routes.indices)) }
    var draft by rememberSaveable(kind, uid) { mutableStateOf("") }
    var query by rememberSaveable(kind, uid) { mutableStateOf("") }
    var seenCreationRevision by remember { mutableIntStateOf(creationRevision) }
    val owner = api.imageCacheScope(); val effectiveUid = uid.ifEmpty { session.uid }
    val route = routes[selected]
    val repo = remember(api) { ContentRepository(api) }
    // Search intentionally filters response content, never sends the local filter as a server query.
    val state = remember(api, owner, kind, effectiveUid, selected, query) {
        ContentListState { page, first, last -> repo.page(ContentRequest(route.path, mapOf("uid" to effectiveUid) + if (kind == "history") mapOf("type" to "feed") else emptyMap()), page, first, last) }
    }
    val display = remember(state.rows, query) { state.rows.filter { communityLibraryMatches(it, query) } }
    val scroll = rememberLazyListState(); val scope = rememberCoroutineScope()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val keyboard = LocalSoftwareKeyboardController.current
    val currentState by rememberUpdatedState(state)
    ReviewScrollActivity(scroll)
    LaunchedEffect(state) { state.load(); scroll.scrollToItem(0) }
    val lifecycleState by lifecycle.currentStateFlow.collectAsState()
    LaunchedEffect(creationRevision, lifecycleState) {
        if (kind == "anylist" && lifecycleState.isAtLeast(Lifecycle.State.RESUMED) && seenCreationRevision != creationRevision) {
            snapshotFlow { currentState.busy }.first { !it }
            currentState.load(true)
            seenCreationRevision = creationRevision
        }
    }
    LaunchedEffect(state, scroll, display.size) {
        snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1 }.distinctUntilChanged().collect { last ->
            if (display.isNotEmpty() && last >= display.size - 2 && state.error == null && !state.busy) state.load()
        }
    }
    fun submit() { query = draft.trim(); keyboard?.hide() }
    val scheme = MaterialTheme.colorScheme
    Box(Modifier.fillMaxSize().background(LocalScaffoldColor.current)) {
        Column(Modifier.fillMaxSize()) {
            val toolbarBorder=MaterialTheme.colorScheme.outlineVariant.copy(alpha=.24f)
            com.green.note.ui.ReviewToolbarIcons() { Row(Modifier.fillMaxWidth().height(52.dp).drawWithContent { drawContent(); val stroke=.5.dp.toPx(); drawRect(toolbarBorder, topLeft=androidx.compose.ui.geometry.Offset(0f,size.height-stroke), size=androidx.compose.ui.geometry.Size(size.width,stroke)) }, verticalAlignment = Alignment.CenterVertically) {
                com.green.note.ui.ReviewIconButton(onClick = onBack, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back", contentDescription = "返回") }
                Spacer(Modifier.width(16.dp))
                Text(if (kind == "dyh") "我的看看号" else routes.first().title, Modifier.weight(1f), fontSize = 18.sp, fontWeight = adjustedWeight(700))
            } }
            if (routes.size > 1) FlowRow(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                routes.forEachIndexed { index, item -> com.green.note.ui.ReviewChoiceChip(selected == index, onClick = { selected = index }, label = { Text(item.title) }) }
            }
            Box(Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 8.dp)) {
                if (kind == "history") {
                    val searchColor = if (LocalAppPreferences.current.pureBlackDark && scheme.surface == Color.Black) Color(0xff1c1c1e) else scheme.surfaceContainerHigh
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).background(searchColor, RoundedCornerShape(50)).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        MaterialGlyph("search_rounded", color = scheme.onSurface); Spacer(Modifier.width(16.dp))
                        BasicTextField(draft, { draft = it }, Modifier.weight(1f).padding(vertical = 12.dp), singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit() }),
                            textStyle = MaterialTheme.typography.bodyLarge.copy(color = scheme.onSurface), cursorBrush = SolidColor(scheme.primary),
                            decorationBox = { field -> Box { if (draft.isEmpty()) Text("筛选已加载内容", color = scheme.onSurfaceVariant); field() } })
                    }
                } else CommunityFormField(draft, { draft = it }, "筛选已加载内容", prefixIcon = "search", onSubmit = { submit() })
            }
            ReviewRefreshBox(state.refreshing, { scope.launch { state.load(true) } }, Modifier.weight(1f), failed = state.error != null) {
                LazyColumn(Modifier.fillMaxSize(), state = scroll, contentPadding = PaddingValues(top = if (display.isEmpty()) 0.dp else 10.dp, bottom = 24.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding())) {
                    items(display, key = ::entityKey) { item ->
                        if (kind == "history") Column(Modifier.padding(vertical = 8.dp)) {
                            Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) { MaterialGlyph("history", size = 18.dp, color = scheme.primary); Spacer(Modifier.width(8.dp)); Text(relativeTime(item.text("dateline", "lastupdate"))) }
                            if (item.text("entityType").equals("history", true)) ListItem(headlineContent = { Text(item.text("title", "name")) }, supportingContent = { Text(item.text("subTitle", "description")) }, trailingContent = { MaterialGlyph("chevron_right") }, modifier = Modifier.clickable { item.text("url").takeIf(String::isNotEmpty)?.let(onLink) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent))
                            else EntityRow(api, item, onOpen, onUser, onLink, onGallery, onLike, onMore)
                        } else ListItem(headlineContent = { Text(item.text("title", "name")) }, supportingContent = { Text(item.text("description", "intro")) }, trailingContent = { MaterialGlyph("chevron_right") }, modifier = Modifier.clickable {
                            val id = item.text("id", "entityId")
                            if (id.isNotEmpty()) onOpen(JSONObject(item.toString()).put("id", id).put("entityType", when (kind) { "anylist" -> "anylist"; "dyh" -> "dyh"; else -> "album" }))
                        }, colors = ListItemDefaults.colors(containerColor = Color.Transparent))
                    }
                    item {
                        Column(Modifier.fillMaxWidth().then(if (display.isEmpty()) Modifier.heightIn(min = with(androidx.compose.ui.platform.LocalDensity.current) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.height.toDp() * .2f }) else Modifier.padding(24.dp)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                            when {
                                state.busy -> com.green.note.ui.ReviewCircularProgress()
                                state.error != null -> { Text(state.error.orEmpty()); com.green.note.ui.ReviewTextButton(onClick = { scope.launch { state.load(display.isEmpty()) } }) { Text("重试") } }
                                display.isEmpty() -> Text("暂无内容")
                                !state.more -> Text("没有更多了", color = scheme.onSurfaceVariant, fontSize = 12.sp)
                            }
                        }
                    }
                }
            }
        }
        if (kind == "anylist") ExtendedFloatingActionButton(onClick = {
            if (!session.authenticated || session.anonymous) AppToastState().showSnackbar("请先使用酷安账号登录")
            else onCreate()
        }, modifier = Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(16.dp), shape = RoundedCornerShape(20.dp), containerColor = scheme.primaryContainer, contentColor = scheme.onPrimaryContainer,
            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 1.5.dp, pressedElevation = 3.dp), icon = { MaterialGlyph("add") }, text = { Text("创建清单") })
    }
}
