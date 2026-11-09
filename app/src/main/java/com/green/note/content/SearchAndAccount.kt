package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun marketRequest(route: String): ContentRequest {
    val request = contentRequest(route)
    return if (request.path == "/v6/apk/recommendList") request.copy(query = mapOf("apkType" to "1", "title" to "好软推荐") + request.query) else request
}

@Composable
internal fun MarketScreen(api: ContentApi, onBack: () -> Unit, onSearch: (String) -> Unit, onManagement: () -> Unit,
    onEntity: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit) {
    val tabs = listOf("精选" to "V10_MARKET_HOME", "应用" to "V8_MARKET_APP", "游戏" to "V8_MARKET_GAME", "应用集" to "V8_MARKET_ALBUM", "排行" to "V10_MARKET_RANK")
    val pager = rememberPagerState { tabs.size }; val scope = rememberCoroutineScope()
    val holder = rememberSaveableStateHolder()
    val states = remember(api) { mutableMapOf<String, ContentListState>() }
    var query by rememberSaveable { mutableStateOf("") }
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.let { it.red + it.green + it.blue < 1.5f }
    com.green.note.ui.OfficialHomeTheme {
        val panel = if(dark)Color(0xff1e1e1e) else scheme.surface
        Column(Modifier.fillMaxSize().background(if(dark)Color(0xff101010) else scheme.background)) {
            ContentToolbarRow(Modifier.fillMaxWidth().height(44.dp).background(panel),verticalAlignment=Alignment.CenterVertically) {
                ContentIcon("arrow_back","返回",onBack,Modifier.width(56.dp))
                Row(Modifier.weight(1f).height(36.dp).clip(RoundedCornerShape(9.dp)).background(if(dark)Color(0xff2b2b2b) else scheme.surfaceContainerHighest),verticalAlignment=Alignment.CenterVertically) {
                    Box(Modifier.width(48.dp),contentAlignment=Alignment.Center){MaterialGlyph("search",size=22.dp)}
                    BasicTextField(query,{if(it.length<=1024)query=it},Modifier.weight(1f),singleLine=true,textStyle=TextStyle(localeList=com.green.note.ui.ReviewTextLocales,fontSize=16.sp,color=MaterialTheme.colorScheme.onSurface),
                        keyboardOptions=KeyboardOptions(imeAction=ImeAction.Search),keyboardActions=KeyboardActions(onSearch={query.trim().takeIf(String::isNotEmpty)?.let(onSearch)}),
                        decorationBox={field->Box{if(query.isEmpty())Text("搜索",fontSize=16.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);field()}})
                }
                ContentIcon("install_mobile_outlined","应用管理",onManagement)
            }
            Row(Modifier.fillMaxWidth().height(40.dp).background(panel)) { tabs.forEachIndexed { index, tab ->
                Box(Modifier.weight(1f).fillMaxHeight().clickable { scope.launch{pager.animateScrollToPage(index)} },contentAlignment=Alignment.Center) {
                    Text(tab.first,fontSize=17.sp,fontWeight=if(pager.currentPage==index)FontWeight.Medium else FontWeight.Normal,color=if(pager.currentPage==index)Color(0xff009688) else MaterialTheme.colorScheme.onSurface)
                    if(pager.currentPage==index)Box(Modifier.align(Alignment.BottomCenter).size(12.dp,2.dp).background(Color(0xff009688),RoundedCornerShape(2.dp)))
                }
            } }
            HorizontalPager(pager,Modifier.weight(1f)){index->holder.SaveableStateProvider(index){MarketListScreen(api,tabs[index].second,onEntity,onUser,onLink,onGallery,onLike,onMore,states)}}
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun MarketListScreen(api: ContentApi, route: String, onEntity: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit,
    onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit,
    states: MutableMap<String, ContentListState> = remember(api) { mutableMapOf() }) {
    var selected by rememberSaveable(route) { mutableStateOf("") }
    var rootSelected by rememberSaveable(route) { mutableStateOf("") }
    var selectors by rememberSaveable(route) { mutableStateOf("") }
    val source = selected.ifEmpty { route }
    val repository = remember(api) { ContentRepository(api) }
    val state = states.getOrPut(source) { ContentListState { page, first, last ->
        val result=repository.page(marketRequest(source),page,first,last)
        result.copy(rows=result.rows.filter{it.text("entityTemplate") !in setOf("configCard","noMoreDataCard")}.map { JSONObject(it.toString()).put("_composeCardContext","market") })
    } }
    @Composable fun Selector(rows: List<JSONObject>, header: Boolean = false) {
        FlowRow(Modifier.fillMaxWidth().padding(horizontal=8.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            rows.forEachIndexed { index, row -> val url=row.text("url");val current=if(header)rootSelected else selected
                com.green.note.ui.ReviewChoiceChip(selected=current==url || current.isEmpty()&&index==0,onClick={if(url.isNotEmpty()){if(selectors.isEmpty()||header){selectors=org.json.JSONArray(rows).toString();rootSelected=url};selected=url}},label={Text(row.text("title"))})
            }
        }
    }
    key(source) { ContentList(api,state,onEntity,onUser,onLink,onGallery,onLike,onMore,itemContent={row->
        if(row.text("entityTemplate")=="selectorLinkCard")Selector(row.optJSONArray("entities").objects())
        else MarketCard(api,row,onEntity,onUser,onLink,onGallery,onLike,onMore)
    },header=if(selectors.isEmpty())null else { { Selector(runCatching{org.json.JSONArray(selectors).objects()}.getOrDefault(emptyList()),true) } }) }
}
