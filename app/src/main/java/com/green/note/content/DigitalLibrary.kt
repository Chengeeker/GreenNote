package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import com.green.note.ui.tapCombinedClickable as combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.ReviewButtonIconGap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

internal fun digitalCategoryUrl(category: JSONObject, sort: String): String {
    val base = category.text("url").ifEmpty { "/page?url=%2Fproduct%2FcategoryDetailList%3Ftype%3Dcategory%26id%3D${category.text("id").ifEmpty { "1000" }}%26showMode%3D0" }
    if (sort == "热度") return base
    val field = if (sort == "评分") "owner_star_average_score" else "release_time"
    return if (base.contains("sortField")) base.replace(Regex("sortField%3D[^%&]+", RegexOption.IGNORE_CASE), "sortField%3D$field")
    else "$base%26sortField%3D$field${if (sort == "评分") "%26limitField%3Downer_star_total_count-80" else ""}"
}
internal fun digitalChildren(category: JSONObject): List<JSONObject> = (category.optJSONArray("secondCategoryRows") ?: category.optJSONArray("subCategories") ?: category.optJSONArray("children")).objects()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DigitalLibraryScreen(api: ContentApi, initialCategory: String = "1000", showRail: Boolean = true,tabletPresentation:Boolean=false,
    onProduct: (JSONObject) -> Unit, onBrand: (String, String) -> Unit, onLogin: () -> Unit) {
    var categories by remember { mutableStateOf(JSONArray(digitalFallbackCategories).objects()) }
    var selected by rememberSaveable(initialCategory) { mutableStateOf(initialCategory) }
    var expanded by remember { mutableStateOf(setOf<String>()) }
    var sort by rememberSaveable { mutableStateOf("热度") }
    var selectedBrand by rememberSaveable(selected) { mutableStateOf<String?>(null) }
    val brandAssets = DigitalBrandAssets.get(LocalContext.current)
    var brands by remember(selected) { mutableStateOf(brandAssets.rows(selected)) }
    var sortUrls by remember(selected) { mutableStateOf(mapOf<String, String>()) }
    var specs by remember { mutableStateOf<JSONObject?>(null) }
    var tabletBrandError by remember{mutableStateOf<String?>(null)}
    var brandRevision by remember{mutableIntStateOf(0)}
    val scope = rememberCoroutineScope()
    LaunchedEffect(api,tabletPresentation,selected,brandRevision) {
        if(tabletPresentation && brands.isEmpty())try {
            val root=api.request("/v6/product/brandList");val values=root.optJSONArray("data").objects().flatMap{if(it.text("entityType").equals("card",true))cardChildren(it)else listOf(it)}.map{digitalTabletBrand(it)}.filter{it.text("title","name").isNotEmpty()&&it.text("url").isNotEmpty()}
            if(brands.isEmpty()&&values.isNotEmpty()){brands=values;tabletBrandError=null}
        }catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){if(brands.isEmpty())tabletBrandError=error.message}
    }
    LaunchedEffect(initialCategory) {
        val parent=categories.firstOrNull{it.text("id")==initialCategory||digitalChildren(it).any{child->child.text("id")==initialCategory}}
        if(parent!=null&&digitalChildren(parent).isNotEmpty()){expanded=expanded+parent.text("id");if(parent.text("id")==initialCategory)selected=digitalChildren(parent).first().text("id")}
    }
    LaunchedEffect(api) {
        try { api.request("/v6/product/categoryList").optJSONArray("data").objects().takeIf(List<JSONObject>::isNotEmpty)?.let { categories = it } }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { /* Keep the original bundled category fallbacks. */ }
    }
    val category = (categories + categories.flatMap(::digitalChildren)).firstOrNull { it.text("id") == selected } ?: categories.first()
    val route = sortUrls[sort].orEmpty().ifEmpty { digitalCategoryUrl(category, sort) }
    val state = remember(api, selected) { ContentListState() }
    LaunchedEffect(state, route) { state.bind(route) { page, _, _ ->
        val root = api.request("/v6/page/dataList", query = mapOf("url" to route, "page" to "$page"))
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        val entities = root.optJSONArray("data").objects()
        val products = mutableListOf<JSONObject>()
        for (item in entities) {
            when {
                item.text("entityType") == "card" && (item.text("entityTemplate") == "brandList" || item.text("title") == "品牌") -> item.optJSONArray("entities").objects().takeIf(List<JSONObject>::isNotEmpty)?.let { brands = if(tabletPresentation)it.map(::digitalTabletBrand)else it;tabletBrandError=null }
                item.text("entityType") == "card" && (item.text("entityTemplate") == "sortSelectCard" || item.text("title") == "排序规则") -> sortUrls = item.optJSONArray("entities").objects().associate { it.text("title") to it.text("url") }
                item.text("entityType") == "product" || item.has("id") && item.has("title") && item.text("entityType") != "card" -> products += item
            }
        }
        ContentPage(products, page, "", "", products.size >= 10)
    } }
    val scroll = rememberLazyGridState()
    LaunchedEffect(state, scroll) { snapshotFlow { scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect { if (state.rows.isNotEmpty() && it >= state.rows.size - 3 && !state.busy && state.error == null) state.load() } }
    if(tabletPresentation)DigitalTabletLibrary(api,state,brands,tabletBrandError,{brandRevision++},sort,{sort=it},onProduct,onBrand)
    else Row(Modifier.fillMaxSize()) {
        com.green.note.ui.ReviewScrollActivity(scroll)
        if(showRail){DigitalCategoryRail(categories,selected,expanded,{expanded=it}){selected=it;sort="热度"};VerticalDivider(Modifier.width(1.dp),thickness=.5.dp)}
        com.green.note.ui.ReviewRefreshBox(state.refreshing, { scope.launch { state.load(true) } }, Modifier.weight(1f)) {
            LazyVerticalGrid(GridCells.Fixed(3), state = scroll, modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(start = 8.dp, top = 10.dp, end = 12.dp, bottom = 24.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding())) {
                if (selected != "0") {
                    item(span = { GridItemSpan(3) }) { Column {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            DigitalLibraryStaticText("品牌", MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Bold), Modifier.weight(1f))
                            if (selectedBrand != null) Text("重置品牌", Modifier.clickable { selectedBrand = null }, fontSize = 12.sp, color = Color(0xFF00B074))
                        }
                        Spacer(Modifier.height(10.dp))
                        LazyRow(Modifier.height(116.dp), contentPadding = PaddingValues(horizontal = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            items(brands.chunked(2)) { group -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                group.forEach { brand -> DigitalLibraryBrand(api,brand, selected = selectedBrand == brand.text("title", "name")) {
                                    val id=brand.text("id","entityId")
                                    val url=brand.text("url").ifEmpty{"/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D$id%26category_id%3D$selected%26showMode%3D0"}
                                    val name = brand.text("title", "name")
                                    if (name.isNotEmpty() && url.isNotEmpty()) { selectedBrand = name; onBrand(name, url) }
                                } }

                            } }
                        }
                        Spacer(Modifier.height(10.dp))
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            DigitalLibraryStaticText("排序规则", MaterialTheme.typography.titleSmall.copy(fontSize = 13.sp, fontWeight = FontWeight.Bold), Modifier.weight(1f))
                            listOf("热度", "评分", "最新").forEachIndexed { index,label -> if(index>0)Spacer(Modifier.width(6.dp));DigitalSortChip(label,sort==label){sort=label} }
                        }
                        // LazyVerticalGrid supplies the original 8dp gap before the first product row.
                    } }
                }
                items(state.rows, key = ::entityKey) { product -> DigitalLibraryProduct(api, product, sort, { onProduct(product) }, { specs = product }, onLogin) }
                if (state.rows.isEmpty()) item(span = { GridItemSpan(3) }) {
                    if (state.rows.isEmpty() && state.busy) Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
                    else if (state.rows.isEmpty()) Column(Modifier.fillMaxWidth().height(200.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        MaterialGlyph("devices_other_rounded", size = 48.dp, color = MaterialTheme.colorScheme.outline)
                        Spacer(Modifier.height(8.dp))
                        Text(state.error?.let { "加载失败: $it" } ?: "暂无产品数据", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(12.dp))
                        com.green.note.ui.ReviewFilledTonalButton(onClick = { scope.launch { state.load(true) } }) { Text("重新加载") }
                    }
                }
            }
        }
    }
    specs?.let { product -> com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { specs = null }, shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)) {
        Column(Modifier.padding(start = 20.dp, top = 16.dp, end = 20.dp, bottom = 24.dp).navigationBarsPadding()) {
            Box(Modifier.align(Alignment.CenterHorizontally).size(36.dp, 4.dp).clip(RoundedCornerShape(2.dp)).background(MaterialTheme.colorScheme.outlineVariant)); Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                val image = product.text("logo", "pic", "cover")
                if (image.isNotEmpty()) ContentImage(api, image, null, Modifier.size(50.dp), ContentScale.Fit)
                Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) {
                    Text(product.text("title", "name").ifEmpty { "数码机型" }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp)); Text("热度: ${product.text("hot_num_txt", "hot").ifEmpty { "未知" }} · 评分: ${product.text("star_average_score", "score").ifEmpty { "暂无" }}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(16.dp)); Text("参数规格", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold); Spacer(Modifier.height(10.dp))
            val array = product.optJSONArray("tagArr"); val tags = (0 until (array?.length() ?: 0)).map { array!!.optString(it).trim() }.filter(String::isNotEmpty)
            if (tags.isEmpty()) Text("暂无详细参数", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            else FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { tags.forEach { Text(it, Modifier.clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest).padding(horizontal = 10.dp, vertical = 5.dp), fontSize = 12.sp) } }
            Spacer(Modifier.height(20.dp)); com.green.note.ui.ReviewButton(onClick = { specs = null; onProduct(product) }, Modifier.fillMaxWidth(),iconPadding=true) { MaterialGlyph("arrow_forward_rounded", size = 18.dp); ReviewButtonIconGap(); Text("查看机主评价与动态") }
        }
    } }
}

@Composable
private fun DigitalLibraryProduct(api: ContentApi, row: JSONObject, sort: String, onOpen: () -> Unit, onSpecs: () -> Unit, onLogin: () -> Unit) {
    var following by remember(row, api.imageCacheScope()) { mutableStateOf(api.isProductFollowed(row)) }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val owner=api.imageCacheScope();val session=LocalContentSession.current
    Column(Modifier.fillMaxWidth().aspectRatio(if(with(androidx.compose.ui.platform.LocalDensity.current){androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.width.toDp()}<360.dp).45f else .5f).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = .7f))
        .combinedClickable(onClick = onOpen, onLongClick = onSpecs).padding(horizontal = 6.dp, vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        CardImage(api,row.text("logo", "pic", "cover"),Modifier.fillMaxWidth().height(52.dp),ContentScale.Fit){MaterialGlyph("phone_android_rounded",size=40.dp,color=MaterialTheme.colorScheme.outline)}
        Spacer(Modifier.height(3.dp))
        Box(Modifier.height(32.dp), contentAlignment = Alignment.Center) { Text(row.text("title", "name"), fontSize = 11.5.sp, lineHeight = 14.375.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center) }
        Spacer(Modifier.height(1.dp))
        val score=row.text("star_average_score","score","recent_30_days_owner_star_average_score")
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.Center) {
            if(sort=="评分"&&score.isNotEmpty()){MaterialGlyph("star_rounded",size=13.dp,color=Color(0xFFFFC107));Spacer(Modifier.width(2.dp));Text(score,fontSize=10.5.sp,fontWeight=FontWeight.Bold,maxLines=1)}
            else{Text("🔥",fontSize=10.sp);Spacer(Modifier.width(2.dp));Text(digitalHot(row.text("hot_num_txt","hot","hot_num")).ifEmpty{"—"},fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1)}
        }
        Spacer(Modifier.weight(1f))
        Box(Modifier.fillMaxWidth().height(24.dp).clip(RoundedCornerShape(12.dp)).background(if (following) MaterialTheme.colorScheme.surfaceContainerHighest else Color(0xff00b074)).clickable(enabled = !busy) {
            if(!session.authenticated&&!session.anonymous){com.green.note.ui.AppToastState().showSnackbar("请先登录");return@clickable}
            val previous=following;following=!previous;busy = true
            scope.launch { try { check(owner==api.imageCacheScope()){ "登录账号已改变" };val result=api.followProduct(row, previous);check(owner==api.imageCacheScope()){ "登录账号已改变" };following=result;com.green.note.ui.AppToastState().showSnackbar("${if(result)"已关注"else"已取消关注"} ${row.text("title","name")}") }
                catch (cancelled: CancellationException) { if(owner==api.imageCacheScope())following=previous;throw cancelled } catch (error: Exception) { if(owner==api.imageCacheScope()){following=previous;failure="操作失败: ${error.message}"} } finally { busy = false } }
        }, contentAlignment = Alignment.Center) { Text(if (following) "已关注" else "关注", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (following) MaterialTheme.colorScheme.onSurfaceVariant else Color.White) }
    }
    LaunchedEffect(failure){failure?.let{com.green.note.ui.AppToastState().showSnackbar(it);failure=null}}
}
