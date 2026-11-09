package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.Context
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.platform.LocalFocusManager
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
internal fun searchQuery(keyword: String, type: String, sort: String, filter: String): Map<String, String> = buildMap {
    put("type", if (type == "all" && sort != "default") "feed" else type)
    put("searchValue", keyword); put("show_flag", "1")
    if (type in setOf("all", "feed")) {
        put("sort", if (sort == "exact") "default" else sort); put("sortType", sort)
        if (sort == "exact") put("isExact", "1")
        if (type == "feed" && filter != "all") put("feedType", filter)
    }
}

@Composable
internal fun SearchResultsScreen(api: ContentApi, initialQuery: String, initialType: String, onBack: () -> Unit,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    val tabs = listOf("综合" to "all", "数码" to "product", "动态" to "feed", "话题" to "feedTopic", "用户" to "user", "二手" to "ershou", "应用" to "apk")
    val pager = rememberPagerState(initialPage = tabs.indexOfFirst { it.second == initialType }.coerceAtLeast(0)) { tabs.size }
    var keyword by rememberSaveable { mutableStateOf(initialQuery) }
    var input by rememberSaveable { mutableStateOf(initialQuery) }
    var allSort by rememberSaveable { mutableStateOf("default") }
    var feedSort by rememberSaveable { mutableStateOf("default") }
    var filter by rememberSaveable { mutableStateOf("all") }
    val context = LocalContext.current
    val focus = LocalFocusManager.current
    val scope = rememberCoroutineScope()
    val repository = remember(api) { ContentRepository(api) }
    val lists = remember(api, keyword) { mutableMapOf<String, ContentListState>() }
    val saved = rememberSaveableStateHolder()
    fun submit() {
        val next = input.trim()
        if (next.isEmpty() || next == keyword) return
        if (next.length > 1024) { AppToastState().showSnackbar("搜索词过长"); return }
        keyword = next; allSort = "default"; feedSort = "default"; filter = "all"; focus.clearFocus()
        scope.launch {
            try { SearchHistory.save(context, next) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { AppToastState().showSnackbar("搜索历史保存失败") }
        }
    }
    val open: (JSONObject) -> Unit = { row -> if (row.text("_switchSearchTab") == "user") scope.launch { pager.animateScrollToPage(4) } else onOpen(row) }
    val foreground = if(MaterialTheme.colorScheme.background.luminance() < .5f)Color.White else MaterialTheme.colorScheme.onSurface
    Column(Modifier.fillMaxSize()) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp))
            Row(Modifier.weight(1f).padding(end = 16.dp).height(38.dp).clip(RoundedCornerShape(19.dp)).background(foreground.copy(alpha = .08f)).padding(start = 14.dp, end = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                BasicTextField(input, { input = it }, Modifier.weight(1f), singleLine = true, textStyle = TextStyle(localeList=com.green.note.ui.ReviewTextLocales,fontSize= 14.sp, color = foreground), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit() }),
                    decorationBox = { field -> if(input.isEmpty()) Text("搜索酷安",fontSize=14.sp,color=foreground.copy(alpha=.38f));field() })
                Box(Modifier.size(38.dp).clickable { submit() },contentAlignment=Alignment.Center) { MaterialGlyph("search_rounded",size=20.dp,color=foreground.copy(alpha=.6f)) }
            }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
            tabs.forEachIndexed { index, pair ->
                // Flutter Tab measures the complete unwrapped label: 46dp + 3.5dp indicator.
                Column(Modifier.clickable { scope.launch { pager.animateScrollToPage(index) } }.padding(horizontal=12.dp).width(IntrinsicSize.Max).height(49.5.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                    Box(Modifier.weight(1f),contentAlignment=Alignment.Center) { Text(pair.first,style=MaterialTheme.typography.titleSmall,fontSize=15.sp,fontWeight=if(index==pager.currentPage)FontWeight.Bold else FontWeight.Normal,color=foreground.copy(alpha=if(index==pager.currentPage)1f else .6f),maxLines=1,softWrap=false) }
                    Box(Modifier.fillMaxWidth().height(3.5.dp).background(if(index==pager.currentPage)Color(0xff00b075) else Color.Transparent))
                }
            }
        }
        HorizontalPager(pager,modifier=Modifier.weight(1f),verticalAlignment=Alignment.Top) { index ->
            ActivePage(index == pager.currentPage) {
                val type=tabs[index].second
                val sort=if(type=="all")allSort else if(type=="feed")feedSort else "default"
                val selectedFilter=if(type=="feed")filter else "all"
                val listKey = "$keyword:$type"
                val state = lists.getOrPut(listKey) { ContentListState() }
                val request = ContentRequest("/v6/search", searchQuery(keyword, type, sort, selectedFilter))
                LaunchedEffect(state, request) {
                    state.bind(request) { page, first, last -> repository.page(request, page, first, last) }
                }
                val combined = type == "all" && (state.appliedSource as? ContentRequest)?.query?.get("type") != "feed"
                val firstFeed = remember(state.rows) { state.rows.firstOrNull(::searchFeedEntity) }
                val changeSort:(String)->Unit={if(type=="all")allSort=it else feedSort=it}
                saved.SaveableStateProvider(listKey) {
                    ContentList(api,state,open,onUser,onLink,onGallery,onLike,onMore,
                        header=if(type=="feed" || type=="all" && (!combined || state.rows.isEmpty())) ({ SearchFeedHeader(sort,changeSort,if(type=="feed")filter else null,{filter=it}) }) else null,
                        itemContent={row ->
                            if(combined && row===firstFeed)SearchFeedHeader(sort,changeSort,null,{})
                            EntityRow(api,row,open,onUser,onLink,onGallery,onLike,onMore)
                            if(combined && firstFeed==null && row===state.rows.lastOrNull()) {
                                SearchFeedHeader(sort,changeSort,null,{})
                                if(state.more)Box(Modifier.fillMaxWidth().padding(vertical=18.dp),contentAlignment=Alignment.Center) { com.green.note.ui.ReviewCircularProgress(Modifier.size(20.dp),strokeWidth=2.dp) }
                            }
                        }, loadInitially = false)
                }
            }
        }
    }
}

internal fun searchFeedEntity(row:JSONObject)=row.text("entityType","entity_type").lowercase() in setOf("feed","article","feedarticle","feed_article") || row.has("message") && row.text("id").isNotEmpty()

@Composable
private fun SearchFeedHeader(sort:String,onSort:(String)->Unit,filter:String?,onFilter:(String)->Unit) {
    var menu by remember { mutableStateOf(false) }
    val dark = MaterialTheme.colorScheme.background.luminance() < .5f
    val foreground = if(dark)Color.White else MaterialTheme.colorScheme.onSurface
    Row(Modifier.fillMaxWidth().padding(start=14.dp,top=if(filter==null)12.dp else 8.dp,end=14.dp,bottom=6.dp),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
        if(filter==null) Text("动态",fontSize=15.sp,fontWeight=FontWeight.Bold,color=foreground)
        Row(Modifier.height(28.dp).clip(RoundedCornerShape(14.dp)).background(foreground.copy(alpha=.08f)).padding(2.dp)) {
            listOf("综合" to "default","实时" to "dateline","热度" to "hot","评论" to "reply","精确" to "exact").forEach { (label,value) ->
                Box(Modifier.fillMaxHeight().clip(RoundedCornerShape(12.dp)).background(if(sort==value)if(dark)Color(0xff2c313a) else MaterialTheme.colorScheme.surfaceContainerHigh else Color.Transparent).clickable { onSort(value) }.padding(horizontal=8.dp),contentAlignment=Alignment.Center) {
                    Text(label,fontSize=12.sp,fontWeight=if(sort==value)FontWeight.Bold else FontWeight.Normal,color=if(sort==value)Color(0xff00b075) else foreground.copy(alpha=.7f))
                }
            }
        }
        if(filter!=null) Box {
            Row(Modifier.height(28.dp).clip(RoundedCornerShape(14.dp)).background(foreground.copy(alpha=.08f)).clickable {menu=true}.padding(horizontal=10.dp,vertical=3.dp),verticalAlignment=Alignment.CenterVertically) {
                Text(when(filter){"feedArticle"->"图文";"feed"->"纯文字";else->"全部"},fontSize=12.sp,fontWeight=FontWeight.Medium,color=foreground)
                Spacer(Modifier.width(4.dp));MaterialGlyph("arrow_drop_down_rounded",size=16.dp,color=foreground.copy(alpha=.7f))
            }
            com.green.note.ui.ReviewPopupMenu(menu,{menu=false},containerColor=if(dark)Color(0xff22252c) else MaterialTheme.colorScheme.surfaceContainerLow,shape=RoundedCornerShape(12.dp)) {
                listOf("全部" to "all","图文" to "feedArticle","纯文字" to "feed").forEach { (label,value)->com.green.note.ui.ReviewPopupMenuItem(text={Text(label,fontSize=13.sp,color=if(filter==value)Color(0xff00b075) else foreground,fontWeight=if(filter==value)FontWeight.Bold else FontWeight.Normal)},onClick={onFilter(value);menu=false}) }
            }
        }
    }
}


