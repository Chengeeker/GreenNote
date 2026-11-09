package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SearchScreen(api: ContentApi, onBack: () -> Unit, onSearch: (String, String) -> Unit, initialQuery: String = "") {
    val context = LocalContext.current
    val focus = LocalFocusManager.current
    val scope = rememberCoroutineScope()
    val colors = MaterialTheme.colorScheme
    var query by rememberSaveable { mutableStateOf(initialQuery) }
    var initialSubmitted by rememberSaveable { mutableStateOf(false) }
    var history by remember { mutableStateOf<List<String>>(emptyList()) }
    var expanded by rememberSaveable { mutableStateOf(false) }
    var hot by remember { mutableStateOf<List<String>>(emptyList()) }
    var groups by remember { mutableStateOf<List<SearchHotGroup>>(emptyList()) }
    var suggestions by remember { mutableStateOf<List<String>>(emptyList()) }
    var hotError by remember { mutableStateOf<String?>(null) }
    var hotLoading by remember { mutableStateOf(true) }
    var suggestLoading by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    var clear by remember { mutableStateOf(false) }
    val scroll = rememberLazyListState()
    ReviewScrollActivity(scroll)
    val pager = rememberPagerState { groups.size }
    fun submit(value: String) {
        val term = value.trim()
        if (term.isEmpty()) return
        if (term.length > 1024) { AppToastState().showSnackbar("搜索词过长"); return }
        query = term; focus.clearFocus()
        scope.launch {
            try { history = SearchHistory.save(context, term) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { AppToastState().showSnackbar("搜索历史保存失败") }
            onSearch(term, "all")
        }
    }
    LaunchedEffect(Unit) {
        try { history = SearchHistory.read(context) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { AppToastState().showSnackbar("搜索历史读取失败") }
        if (!initialSubmitted && initialQuery.isNotBlank()) { initialSubmitted = true; submit(initialQuery) }
    }
    LaunchedEffect(api, attempt) {
        hotLoading = true; hotError = null
        try {
            val response = api.request("/v6/search", query = mapOf("type" to "hotSearch", "refresh" to if (attempt == 0) "0" else "1", "returnType" to "all"))
            val data = response.opt("data") ?: response
            hot = SearchData.keywords(data).take(12); groups = SearchData.groups(data)
            if (groups.isNotEmpty() && pager.currentPage >= groups.size) pager.scrollToPage(groups.lastIndex)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { hotError = error.message }
        finally { hotLoading = false }
    }
    LaunchedEffect(api, query) {
        suggestions = emptyList(); suggestLoading = query.isNotBlank()
        if (query.isBlank()) return@LaunchedEffect
        delay(350)
        try { suggestions = SearchData.suggestions(api.request("/v6/search/suggest", query = mapOf("key" to query.trim())).opt("data")) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { }
        finally { suggestLoading = false }
    }
    Column(Modifier.fillMaxSize()) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).contentToolbarBorder().padding(start = 8.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.fillMaxWidth().height(40.dp).clip(RoundedCornerShape(20.dp)).background(colors.surfaceContainerHighest.copy(alpha = .5f)), verticalAlignment = Alignment.CenterVertically) {
                ContentIcon("arrow_back_rounded", "返回", onBack, Modifier.size(40.dp))
                BasicTextField(query, { query = it }, Modifier.weight(1f), singleLine = true,
                    textStyle = TextStyle(localeList=com.green.note.ui.ReviewTextLocales,fontSize= 14.5.sp, lineHeight = 18.125.sp, color = colors.onSurface),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit(query) }),
                    decorationBox = { field -> if (query.isEmpty()) Text("选机中心", color = colors.onSurfaceVariant.copy(alpha = .6f), fontSize = 14.sp); field() })
                ContentIcon("search_rounded", "搜索", { submit(query) }, Modifier.size(40.dp))
            }
        }
        val querying = query.isNotBlank()
        LazyColumn(state = scroll, modifier = Modifier.fillMaxSize().navigationBarsPadding(), contentPadding = PaddingValues(start = if (querying) 16.dp else 8.dp, top = 8.dp, end = if (querying) 16.dp else 8.dp, bottom = 24.dp)) {
            if (querying) {
                if (suggestLoading) item { Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress(Modifier.size(24.dp), strokeWidth = 2.5.dp) } }
                items(suggestions.take(8)) { value -> SearchSuggestion(value, false) { submit(value) } }
                if (!suggestLoading && suggestions.isEmpty()) item { SearchSuggestion("搜索“${query.trim()}”", true) { submit(query) } }
            } else {
                item { SearchCard {
                    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text("搜索历史", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            if (history.isNotEmpty()) ContentIcon("delete_outline_rounded", "清空搜索历史", { clear = true }, Modifier.size(40.dp))
                        }
                        if (history.isEmpty()) Text("暂无搜索历史", Modifier.padding(vertical = 8.dp), color = colors.onSurfaceVariant)
                        else FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            (if (expanded) history else history.take(10)).forEach { value -> SearchChip(value) { submit(value) } }
                        }
                        if (history.size > 10) com.green.note.ui.ReviewTextButton(onClick = { expanded = !expanded }, Modifier.align(Alignment.CenterHorizontally), iconPadding = true) {
                            MaterialGlyph(if (expanded) "keyboard_arrow_up_rounded" else "keyboard_arrow_down_rounded")
                            com.green.note.ui.ReviewButtonIconGap(); Text(if (expanded) "收起搜索历史" else "展开更多搜索历史")
                        }
                    }
                }; Spacer(Modifier.height(12.dp)) }
                item { SearchCard {
                    Column(Modifier.padding(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 12.dp)) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text("热门搜索", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            if (hotLoading) Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress(Modifier.size(18.dp), strokeWidth = 2.dp) }
                            else ContentIcon("refresh_rounded", "刷新热门搜索", { attempt++ }, Modifier.size(40.dp))
                        }
                        if (hot.isEmpty()) {
                            if (hotLoading) Box(Modifier.fillMaxWidth().padding(vertical = 20.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress(Modifier.size(24.dp), strokeWidth = 2.5.dp) }
                            else Text(hotError ?: "暂无热门搜索", Modifier.padding(vertical = 8.dp), color = colors.onSurfaceVariant)
                        } else FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { hot.forEach { value -> SearchChip(value) { submit(value) } } }
                    }
                } }
                if (groups.isNotEmpty()) {
                    item { Spacer(Modifier.height(14.dp)); Row(Modifier.horizontalScroll(rememberScrollState())) {
                        groups.forEachIndexed { index, group -> Column(Modifier.clickable { scope.launch { pager.animateScrollToPage(index, animationSpec = tween(260, easing = CubicBezierEasing(.215f, .61f, .355f, 1f))) } }
                            .padding(top = 6.dp, end = 12.dp, bottom = 5.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(group.title, fontSize = 16.sp, fontWeight = if (pager.currentPage == index) FontWeight.Bold else FontWeight.Medium, color = if (pager.currentPage == index) colors.primary else colors.onSurfaceVariant)
                            Spacer(Modifier.height(4.dp)); Box(Modifier.width(if (pager.currentPage == index) 44.dp else 0.dp).height(3.dp).background(colors.primary, RoundedCornerShape(2.dp)))
                        } }
                    }; Spacer(Modifier.height(8.dp)) }
                    item { BoxWithConstraints {
                        val count = groups.maxOf { it.items.size }.coerceIn(1, 10)
                        HorizontalPager(state = pager, pageSize = PageSize.Fixed(maxWidth * .82f), modifier = Modifier.height((24 + 46 * count).dp), verticalAlignment = Alignment.Top) { index ->
                            SearchCard(Modifier.padding(end = 12.dp)) { Column(Modifier.padding(vertical = 12.dp)) {
                                groups[index].items.take(10).forEachIndexed { rank, row -> Row(Modifier.fillMaxWidth().height(46.dp).clickable { submit(SearchData.title(row)) }.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    SearchRankBadge(rank); Spacer(Modifier.width(10.dp)); Text(SearchData.title(row), Modifier.weight(1f), fontSize = 14.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    val heat = row.text("hotNum", "hotnum")
                                    if (heat.isNotEmpty()) { MaterialGlyph("local_fire_department_rounded", size = 17.dp, color = colors.primary); Spacer(Modifier.width(4.dp)); Text(heat, fontSize = 13.5.sp, color = colors.primary) }
                                } }
                            } }
                        }
                    } }
                }
            }
        }
    }
    if (clear) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { clear = false }, title = { Text("清空搜索历史") }, text = { Text("确定要清空全部搜索历史记录吗？") },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { clear = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = { scope.launch {
            try { SearchHistory.clear(context); history = emptyList(); clear = false }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { AppToastState().showSnackbar("搜索历史清除失败") }
        } }) { Text("清空") } })
}

@Composable private fun SearchCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) = Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerLow,
    border = BorderStroke(.8.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .25f)), shadowElevation = 1.dp, content = content)

@Composable private fun SearchChip(text: String, onClick: () -> Unit) {
    Text(text, Modifier.clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .55f)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp), fontSize = 13.sp)
}

@Composable private fun SearchSuggestion(text: String, primary: Boolean, onClick: () -> Unit) {
    ReviewTileLayout(Modifier.clickable(onClick = onClick), horizontalPadding = 14.dp,
        leading = { MaterialGlyph("search_rounded", color = if (primary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }) {
        Text(text, fontSize = 15.sp, lineHeight = 20.25.sp, fontWeight = adjustedWeight(600))
    }
}

@Composable private fun SearchRankBadge(index: Int) {
    val colors = listOf(Color(0xfff44336), Color(0xffff9800), Color(0xffffc107))
    Box(Modifier.width(24.dp).then(if (index < 3) Modifier.height(24.dp).background(colors[index], RoundedCornerShape(6.dp)) else Modifier), contentAlignment = Alignment.Center) {
        Text("${index + 1}", color = if (index < 3) Color.White else MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (index < 3) 13.sp else 16.sp, fontWeight = if (index < 3) FontWeight.Bold else FontWeight.Normal, textAlign = TextAlign.Center)
    }
}


