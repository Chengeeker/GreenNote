package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.CubicBezierEasing
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalView
import com.green.note.ui.LocalAppPreferences
import com.green.note.ui.AppHaptics
import com.green.note.ui.ActivePage
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject

internal fun digitalTabs(root: JSONObject, brand: Boolean): Pair<List<JSONObject>, Int> {
    val result = mutableListOf<JSONObject>()
    var index = 0
    fun visit(value: Any?, depth: Int) {
        if (depth > 32) return
        when (value) {
            is JSONArray -> (0 until value.length()).forEach { visit(value.opt(it), depth + 1) }
            is JSONObject -> {
                val template = value.text("entityTemplate", "entity_template").lowercase()
                val match = if (brand) template == "icontablinkgridcard" else template.startsWith("sortselectcard") || template.startsWith("selectorlinkcard") || value.text("title").contains("排序规则")
                if (match) {
                    value.optJSONArray("entities").objects().filter { it.text("url", "target_url", "entityUrl", "page_name").isNotEmpty() }.forEach { item ->
                        if (result.none { it.text("url", "target_url", "entityUrl", "page_name") == item.text("url", "target_url", "entityUrl", "page_name") }) result += item
                    }
                    val extra = value.optJSONObject("extraData") ?: value.optJSONObject("extra_data") ?: runCatching { JSONObject(value.text("extraData", "extra_data")) }.getOrNull()
                    index = extra?.text("selectedTab")?.toIntOrNull() ?: value.text("selectedTab").toIntOrNull() ?: 0
                }
                listOf("data", "entities", "rows", "list", "items", "cardRows", "card_rows", "entityList", "entity_list").forEach { visit(value.opt(it), depth + 1) }
            }
        }
    }
    visit(root.opt("data") ?: root, 0)
    val marked = result.indexOfFirst { it.text("selected", "isSelected", "is_selected") in setOf("true", "1") }
    val phone=result.indexOfFirst{it.text("title")=="手机榜"}
    return result to if(!brand&&phone>=0)phone else if (marked >= 0) marked else if (index in result.indices) index else 0
}

@Composable
internal fun DigitalTabsScreen(api: ContentApi, route: String, brand: Boolean = false, render: @Composable (String, String) -> Unit) {
    var tabs by remember(route) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selected by remember(route) { mutableIntStateOf(0) }
    var busy by remember(route) { mutableStateOf(true) }
    var failure by remember(route) { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    LaunchedEffect(api, route, revision) {
        busy = true; failure = null
        try { digitalTabs(api.request("/v6/page/dataList", query = mapOf("url" to route, "page" to "1")), brand).let { tabs = it.first; selected = it.second } }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { failure = error.message ?: "加载失败" }
        finally { busy = false }
    }
    when {
        busy -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
        failure != null -> Column(Modifier.fillMaxWidth().padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally) { Text(failure.orEmpty()); com.green.note.ui.ReviewTextButton(onClick = { revision++ }) { Text("重新加载") } }
        tabs.isEmpty() -> if(brand)render("", route)else Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){Column(horizontalAlignment=Alignment.CenterHorizontally){Text("排行榜接口没有返回分类入口");Spacer(Modifier.height(8.dp));com.green.note.ui.ReviewTextButton(onClick={revision++}){Text("重新加载")}}}
        else -> {
            val pager=rememberPagerState(initialPage=selected){tabs.size};val scope=rememberCoroutineScope();val view=LocalView.current;val haptics=LocalAppPreferences.current.haptics
            LaunchedEffect(pager.currentPage){selected=pager.currentPage}
            val select:(Int)->Unit={index->AppHaptics.selection(view,haptics);scope.launch{pager.animateScrollToPage(index)}}
            Column {
                if(brand)DigitalBrandTabs(tabs,pager.currentPage,select)
                else LazyRow(Modifier.height(52.dp),contentPadding=PaddingValues(horizontal=14.dp,vertical=7.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    itemsIndexed(tabs){index,tab->Box(Modifier.fillMaxHeight().background(if(index==pager.currentPage)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh,RoundedCornerShape(14.dp)).clickable{select(index)}.padding(horizontal=16.dp),contentAlignment=Alignment.Center){Text(tab.text("title","name"),color=if(index==pager.currentPage)MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)}}
                }
                HorizontalPager(pager,Modifier.weight(1f)) {index->ActivePage(index==pager.currentPage){render(tabs[index].text("title","name"),tabs[index].text("url","target_url","entityUrl","page_name"))}}
            }
        }
    }
}

@Composable
private fun DigitalBrandTabs(tabs:List<JSONObject>,selected:Int,onSelected:(Int)->Unit) {
    val scroll=rememberScrollState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    val widths=remember(tabs){mutableStateMapOf<Int,Int>()}
    var viewport by remember{mutableIntStateOf(0)}
    val edge=with(androidx.compose.ui.platform.LocalDensity.current){4.dp.roundToPx()}
    LaunchedEffect(selected,viewport,widths.toMap()) {
        if(viewport>0 && (0..selected).all{widths.containsKey(it)}) {
            val center=edge+(0 until selected).sumOf{widths.getValue(it)}+widths.getValue(selected)/2
            scroll.animateScrollTo((center-viewport/2).coerceIn(0,scroll.maxValue),tween(300,easing=CubicBezierEasing(.25f,.1f,.25f,1f)))
        }
    }
    Row(Modifier.fillMaxWidth().onSizeChanged{viewport=it.width}.horizontalScroll(scroll).padding(horizontal=4.dp)) {
        tabs.forEachIndexed{index,tab->
            Column(Modifier.onSizeChanged{widths[index]=it.width}.semantics{this.selected=index==selected;role=Role.Tab}.clickable{onSelected(index)}.padding(horizontal=12.dp).width(IntrinsicSize.Max).height(49.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                Box(Modifier.weight(1f),contentAlignment=Alignment.Center) {
                    Text(tab.text("title","name"),style=MaterialTheme.typography.titleSmall,fontSize=16.sp,
                        fontWeight=if(index==selected)FontWeight.Bold else MaterialTheme.typography.titleSmall.fontWeight,
                        color=if(index==selected)Color(0xFF00B074)else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines=1,softWrap=false,overflow=TextOverflow.Clip)
                }
                Box(Modifier.fillMaxWidth().height(3.dp).background(if(index==selected)Color(0xFF00B074)else Color.Transparent,RoundedCornerShape(topStart=3.dp,topEnd=3.dp)))
            }
        }
    }
}
