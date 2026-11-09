package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

internal fun activitySortCard(rows: List<JSONObject>): JSONObject? = rows.firstOrNull {
    it.text("entityTemplate") == "sortSelectCard" && it.optJSONArray("entities").objects().isNotEmpty()
}
internal fun visibleActivityRow(row: JSONObject, hasSortCard: Boolean): Boolean = row.text("entityTemplate") !in
    setOf("configCard", "sponsorCard", "noMoreDataCard", "fabCard", "iconTabLinkGridCard") &&
    (!hasSortCard || row.text("entityTemplate") != "sortSelectCard")

@Composable
internal fun ActivityTabBody(api: ContentApi, tab: JSONObject, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit,
    onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit,
    onMore: (JSONObject) -> Unit, onBack: () -> Unit, initialPage: ContentPage? = null, cacheTag: String? = null) {
    val originalRoute = tab.text("url")
    var route by remember(originalRoute) { mutableStateOf(originalRoute) }
    var selected by remember(originalRoute) { mutableStateOf("默认") }
    var sortCard by remember(originalRoute) { mutableStateOf(activitySortCard(initialPage?.rows.orEmpty())) }
    var seed by remember(originalRoute) { mutableStateOf(initialPage) }
    val preparation = LocalTopicPreparation.current
    val repository = remember(api) { ContentRepository(api) }
    if (route.isEmpty()) { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("暂无活动内容") }; return }
    if (isActivityDocument(route)) { key(route) { BrowserScreen(route, onBack, showToolbar = false, activityDocument = true, onNavigate = onLink) }; return }
    @Composable fun SortHeader(card: JSONObject) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("全部讨论", fontSize = 15.sp); Spacer(Modifier.width(8.dp))
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                Row(Modifier.horizontalScroll(rememberScrollState()).clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .08f)).padding(3.dp)) {
                    card.optJSONArray("entities").objects().forEach { choice ->
                        val title = choice.text("title")
                        Text(title, Modifier.clip(RoundedCornerShape(16.dp)).background(if (selected == title) MaterialTheme.colorScheme.onSurface.copy(alpha = .1f) else Color.Transparent)
                            .clickable { val url = choice.text("url"); if (url.isNotEmpty() && selected != title) { seed = null; sortCard = card; route = url; selected = title } }
                            .padding(horizontal = 10.dp, vertical = 5.dp), fontSize = 13.sp)
                    }
                }
            }
        }
    }
    val state = remember(api, originalRoute) {
        ContentListState(seed?.rows.orEmpty().filter { visibleActivityRow(it, sortCard != null) })
    }
    val requestRoute = route
    LaunchedEffect(state, requestRoute) {
        state.bind(requestRoute) { page, first, last ->
            val prepared = seed?.takeIf { page == 1 && requestRoute == originalRoute }
            val loaded = prepared ?: repository.page(contentRequest(requestRoute), page, first, last)
            if (prepared != null) seed = null
            if (sortCard == null && requestRoute == route) sortCard = activitySortCard(loaded.rows)
            if (page == 1 && cacheTag != null && requestRoute == originalRoute) preparation?.rememberPage(cacheTag, requestRoute, loaded)
            loaded.copy(rows = loaded.rows.filter { visibleActivityRow(it, sortCard != null) })
        }
    }
    ContentList(api, state, onOpen, onUser, onLink, onGallery, onLike, onMore,
        itemContent = { row ->
            if (row.text("entityTemplate") == "sortSelectCard") SortHeader(row)
            else EntityRow(api, if (row.text("entityType") == "feed") JSONObject(row.toString()).put("_composeOfficialLayout", true) else row,
                onOpen, onUser, onLink, onGallery, onLike, onMore)
        }, header = sortCard?.let { card -> { SortHeader(card) } }, loadInitially = false)
}
