package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.ReviewTextField as TextField

import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.json.JSONArray
import androidx.activity.compose.BackHandler
import com.green.note.ui.tapToggleable as toggleable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import com.green.note.nativebridge.DeviceProfile
import com.green.note.ui.ReviewRefreshBox
import com.green.note.ui.ReviewScrollActivity
import kotlinx.coroutines.coroutineScope
import java.util.Locale

internal fun ratingCount(row: JSONObject): Int = row.text("owner_star_total_count").toIntOrNull()?.takeIf { it > 0 }
    ?: row.text("star_total_count", "rating_total_num").toIntOrNull() ?: 0

internal fun ratingScore(row: JSONObject): Double = (if ((row.text("owner_star_total_count").toIntOrNull() ?: 0) > 0)
    row.text("owner_star_average_score", "rating_average_score", "star_average_score") else row.text("rating_average_score", "star_average_score")).toDoubleOrNull() ?: 0.0

private fun ratingCountLabel(row: JSONObject) = "${ratingCount(row)}${if ((row.text("owner_star_total_count").toIntOrNull() ?: 0) > 0) "机主" else "人"}点评"
internal fun ratingCards(rows: List<JSONObject>): List<JSONObject> {
    val cards = mutableListOf<JSONObject>(); var group: JSONObject? = null
    rows.forEach { row ->
        if (row.text("entityTemplate") == "configCard") return@forEach
        if (row.text("entityTemplate") == "titleCard" && row.has("title")) {
            group = JSONObject(row.toString()).put("entities", JSONArray(row.optJSONArray("entities")?.toString() ?: "[]")); cards += group!!
        } else if (group != null && row.text("entityType") in setOf("product", "topic")) group!!.getJSONArray("entities").put(row)
        else { group = null; cards += row }
    }; return cards
}
internal fun ratingDeviceKey(value: String, system: Boolean): String = value.lowercase(Locale.ROOT).replace(Regex("\\s+"), "").let { if (system) it.replace(Regex("(\\.0)+$"), "") else it }
private val ratingRoutes = listOf("V16_RATINGSHOP_RECOMMEND", "V16_RATINGSHOP_SHUMA", "V16_RATINGSHOP_GAME", "V16_RATINGSHOP_LIFE")
@Stable private class RatingPageState {
    var rows by mutableStateOf<List<JSONObject>>(emptyList()); var busy by mutableStateOf(true); var loaded by mutableStateOf(false)
    var refreshing by mutableStateOf(false); var error by mutableStateOf<String?>(null)
    suspend fun load(api: ContentApi, route: String, keyword: String = "", searchType: String = "product") {
        busy = true; error = null
        try { rows = ratingCards(extractEntities(api.request(if (keyword.isEmpty()) "/v6/page/dataList" else "/v6/search", query = if (keyword.isEmpty()) mapOf("url" to route, "page" to "1") else mapOf("searchValue" to keyword, "type" to searchType, "page" to "1")))); loaded = true }
        catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "加载失败" }
        finally { busy = false }
    }
}

@Composable
internal fun RatingSquareScreen(api: ContentApi, onBack: () -> Unit, session: ContentSession = ContentSession(), onMyRatings: (String) -> Unit = {}, onSelected: ((JSONObject) -> Unit)? = null) {
    var selected by rememberSaveable { mutableIntStateOf(0) }; var keyword by rememberSaveable { mutableStateOf("") }; var submitted by rememberSaveable { mutableStateOf("") }
    var category by remember { mutableStateOf<Pair<String, String>?>(null) }; var rating by remember { mutableStateOf<JSONObject?>(null) }
    val pages = remember(api) { mutableMapOf<String, RatingPageState>() }; val positions = remember { mutableMapOf<String, androidx.compose.foundation.lazy.LazyListState>() }
    val focus = remember { FocusRequester() }; val context = LocalContext.current; val scope = rememberCoroutineScope()
    var personalProfile by remember { mutableStateOf<Map<String, String>>(emptyMap()) }; val personal = remember(api) { mutableStateMapOf<String, JSONObject>() }
    val route = category?.second ?: if (submitted.isEmpty()) ratingRoutes[selected] else ""; val searchType = if (selected >= 2) "feedTopic" else "product"
    val key = "$route:$submitted:$searchType"; val page = pages.getOrPut(key) { RatingPageState() }; val scroll = positions.getOrPut(key) { androidx.compose.foundation.lazy.LazyListState() }
    if (pages.size > 12) pages.keys.firstOrNull { old -> old != key && ratingRoutes.none { old.startsWith("$it:") } }?.let { old -> pages.remove(old); positions.remove(old) }
    val original = MaterialTheme.colorScheme; val dark = original.surface.luminance() < .5f
    val scheme = if (dark) original.copy(primary = Color(0xff009688), onSurface = Color(0xffcccccc), onSurfaceVariant = Color(0xff999999)) else original
    val recommend = route == ratingRoutes.first()
    fun back() { if (category != null) category = null else onBack() }; BackHandler { back() }
    fun open(row: JSONObject) { if (row.text("id").isEmpty()) return; if (onSelected != null) { onSelected(row); return }; if ((row.opt("allow_rating") ?: row.opt("allow_rate"))?.toString() in listOf("0", "false")) return; rating = row }
    LaunchedEffect(api, key) { if (!page.loaded) page.load(api, route, submitted, searchType) }
    LaunchedEffect(api) {
        personalProfile = DeviceProfile.read(context)
        coroutineScope { personalProfile.forEach { (title, value) -> if (value.isNotEmpty()) launch {
            try { val system = title == "我的系统"; val rows = extractEntities(api.request("/v6/search", query = mapOf("type" to if (system) "feedTopic" else "product", "searchValue" to if (system) value.replace(Regex("(\\.0)+$"), "") else value, "page" to "1")))
                (rows + rows.flatMap { it.optJSONArray("entities").objects() }).firstOrNull { it.text("id").isNotEmpty() && ratingDeviceKey(it.text("title"), system) == ratingDeviceKey(value, system) }?.let { personal[title] = it }
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { /* Optional match does not replace the page error. */ }
        } } }
    }
    com.green.note.ui.OfficialHomeTheme {
        Column(Modifier.fillMaxSize().background(if (dark) Color(0xff1e1e1e) else Color.White)) {
            if (category != null) com.green.note.ui.ReviewToolbarIcons() { Row(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) { com.green.note.ui.ReviewIconButton(onClick = ::back, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back", contentDescription = "返回") }; Spacer(Modifier.width(16.dp)); Text(category!!.first, fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700)) } }
            else {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Row(Modifier.weight(1f).height(40.dp).background(if (dark) Color(0xff2b2b2d) else Color(0xfff0f0f0), RoundedCornerShape(9.dp)), verticalAlignment = Alignment.CenterVertically) {
                        ContentIcon("arrow_back", "返回", ::back)
                        BasicTextField(keyword, { keyword = it }, Modifier.weight(1f).focusRequester(focus), singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = scheme.onSurface), cursorBrush = SolidColor(scheme.primary), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submitted = keyword.trim() }), decorationBox = { field -> Box { if (keyword.isEmpty()) Text("搜索点评对象", color = scheme.onSurfaceVariant); field() } })
                        com.green.note.ui.ReviewIconButton(onClick = { submitted = keyword.trim() }) { MaterialGlyph("search", size = 26.dp, contentDescription = "搜索点评对象") }
                    }; com.green.note.ui.ReviewIconButton(onClick = { onMyRatings(session.uid) }) { MaterialGlyph("person_outline", size = 28.dp, contentDescription = "我的点评") }
                }
                Row(Modifier.fillMaxWidth()) { listOf("推荐", "数码", "游戏", "生活").forEachIndexed { index, label ->
                    Column(Modifier.weight(1f).height(40.dp).clickable { selected = index; submitted = ""; keyword = "" }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Text(label, color = if (index == selected) Color(0xff009688) else scheme.onSurface, fontSize = 17.sp, fontWeight = if (index == selected) FontWeight.SemiBold else FontWeight.Normal); Spacer(Modifier.height(3.dp)); Box(Modifier.size(10.dp, 3.dp).background(if (index == selected) Color(0xff009688) else Color.Transparent, RoundedCornerShape(2.dp)))
                    }
                } }
            }
            ReviewScrollActivity(scroll)
            when {
                page.busy && !page.loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
                page.error != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(page.error.orEmpty()); com.green.note.ui.ReviewTextButton(onClick = { scope.launch { page.load(api, route, submitted, searchType) } }) { Text("重试") } } }
                else -> ReviewRefreshBox(page.refreshing, onRefresh = { scope.launch { page.refreshing = true; try { page.load(api, route, submitted, searchType) } finally { page.refreshing = false } } }, modifier = Modifier.fillMaxSize().background(if (dark) Color(0xff111111) else Color(0xfff5f5f5))) {
                    LazyColumn(Modifier.fillMaxSize(), state = scroll, contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp)) {
                        if (recommend) item { RatingPersonalTargets(api, personalProfile, personal, ::open) { focus.requestFocus() } }
                        if (page.rows.isEmpty()) item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { Text("暂无点评对象") } }
                        items(page.rows, key = ::entityKey) { card -> val children = card.optJSONArray("entities").objects()
                            when {
                                children.isEmpty() && card.text("entityType") in setOf("product", "topic") -> RatingSection(api, "", listOf(card), recommend, onSelected != null, ::open)
                                children.isEmpty() && card.text("title") == "我的装备" -> RatingSection(api, "我的装备", emptyList(), recommend, onSelected != null, ::open)
                                children.isNotEmpty() -> RatingSection(api, card.text("title"), children, recommend, onSelected != null, ::open, if (card.text("entityTemplate") == "ratingNodeHorizonList" && card.text("url").isNotEmpty()) ({ category = card.text("title") to card.text("url"); submitted = "" }) else null)
                            }
                        }
                    }
                }
            }
        }; rating?.let { row -> RatingEditorSheet(api, row, session) { rating = null } }
    }
}

@Composable
private fun RatingPersonalTargets(api: ContentApi, profile: Map<String, String>, matches: Map<String, JSONObject>, open: (JSONObject) -> Unit, search: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(Triple("我的机型", "未关联机型", "phone_android"), Triple("我的系统", "未关联系统", "android")).forEach { (title, fallback, icon) -> val row = matches[title]; val scheme = MaterialTheme.colorScheme
            Column(Modifier.weight(1f).background(if (scheme.surface.luminance() < .5f) Color(0xff1e1e1e) else Color.White, RoundedCornerShape(10.dp)).padding(8.dp)) {
                Text(title, fontSize = 11.sp); Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(44.dp).clip(RoundedCornerShape(8.dp)).border(1.dp, scheme.outline.copy(alpha = .2f), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) { if (row?.text("logo").isNullOrEmpty()) MaterialGlyph(icon, size = 28.dp) else ContentImage(api, row!!.text("logo"), null, Modifier.fillMaxSize()) }
                    Spacer(Modifier.width(8.dp)); Column(Modifier.weight(1f)) { Text(profile[title]?.takeIf(String::isNotEmpty) ?: row?.text("title") ?: fallback, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis); if (row == null) Text("暂无评分", fontSize = 11.sp, color = Color(0xff999999)) else RatingStars(ratingScore(row)) }
                }
                Spacer(Modifier.height(10.dp)); HorizontalDivider(color = scheme.outlineVariant.copy(alpha = .2f))
                Row(Modifier.fillMaxWidth().clickable { if (row == null) search() else open(row) }.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) { Text(if (row == null) "搜索后去点评" else ratingCountLabel(row), Modifier.weight(1f), fontSize = 11.sp); if (row != null) Text("去点评", fontSize = 11.sp); MaterialGlyph("chevron_right", size = 18.dp) }
            }
        }
    }
}

@Composable
private fun RatingSection(api: ContentApi, title: String, rows: List<JSONObject>, recommend: Boolean, selectOnly: Boolean, open: (JSONObject) -> Unit, onCategory: (() -> Unit)? = null) {
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f; val rowHeight = (if (recommend) 78 else 74).dp * LocalDensity.current.fontScale.coerceAtLeast(1f)
    Column(Modifier.padding(start = 8.dp, end = 8.dp, bottom = 8.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (dark) Color(0xff1e1e1e) else Color.White)) {
        if (title.isNotEmpty()) Row(Modifier.fillMaxWidth().then(if (onCategory != null) Modifier.clickable(onClick = onCategory) else Modifier).padding(start = 12.dp, top = 12.dp, end = 12.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) { Text(title, Modifier.weight(1f), fontSize = 15.sp, fontWeight = if (title == "我的装备") FontWeight.SemiBold else FontWeight.Normal); if (onCategory != null) MaterialGlyph("chevron_right", size = 22.dp) }
        when {
            rows.isEmpty() -> Text("暂无装备，搜索对象即可去点评", Modifier.padding(20.dp), fontSize = 13.sp)
            recommend -> rows.forEach { row -> RatingSquareNode(api, row, true, selectOnly, Modifier.padding(start = 12.dp).height(rowHeight)) { open(row) } }
            else -> BoxWithConstraints(Modifier.fillMaxWidth().height(rowHeight * rows.size.coerceAtMost(3) + 10.dp)) { val width = maxWidth * .9f
                LazyRow(contentPadding = PaddingValues(start = 12.dp)) {
                    items(rows.chunked(3)) { group ->
                        Column(Modifier.width(width)) {
                            group.forEach { row -> RatingSquareNode(api, row, false, selectOnly, Modifier.height(rowHeight)) { open(row) } }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RatingStars(score: Double) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        repeat(5) { index -> Box(Modifier.padding(end = 2.dp).size(9.dp).clip(RoundedCornerShape(1.5.dp)).background(Color(0xff777777)), contentAlignment = Alignment.Center) {
            Box(Modifier.fillMaxHeight().fillMaxWidth((score / 2 - index).toFloat().coerceIn(0f, 1f)).align(Alignment.CenterStart).background(Color(0xffd99f18))); MaterialGlyph("star", size = 8.dp, color = Color.White)
        } }; Text(String.format(Locale.ROOT, "%.1f", score), fontSize = 11.sp, color = Color(0xffd99f18))
    }
}

@Composable
private fun RatingSquareNode(api: ContentApi, row: JSONObject, recommend: Boolean, selectOnly: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val allowed = (row.opt("allow_rating") ?: row.opt("allow_rate"))?.toString() !in listOf("0", "false"); val count = ratingCount(row); val score = ratingScore(row)
    Row(modifier.fillMaxWidth().padding(end = 18.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(60.dp).clip(RoundedCornerShape(8.dp)).background(if (row.text("logo").isEmpty()) MaterialTheme.colorScheme.surfaceContainerHighest else Color.Transparent), contentAlignment = Alignment.Center) { if (row.text("logo").isEmpty()) MaterialGlyph("devices_other", size = 30.dp) else ContentImage(api, row.text("logo"), null, Modifier.fillMaxSize()) }
        Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f).clickable(onClick = onClick), verticalArrangement = Arrangement.Center) {
            Text(row.text("title"), fontSize = 15.sp, lineHeight = 17.25.sp, maxLines = 2, overflow = TextOverflow.Ellipsis); Spacer(Modifier.height(3.dp))
            if (recommend) { RatingStars(score); Spacer(Modifier.height(3.dp)); Text(if (count == 0) "暂无人评分" else ratingCountLabel(row), fontSize = 11.5.sp) }
            else Text(buildAnnotatedString { if (count > 0) withStyle(SpanStyle(color = Color(0xffd99f18))) { append(String.format(Locale.ROOT, if (score == 10.0) "%.0f分  " else "%.1f分  ", score)) }; append(if (count == 0) "暂无人评分" else ratingCountLabel(row)) }, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(3.dp)); com.green.note.ui.ReviewButton(onClick = onClick, enabled = allowed, modifier = Modifier.size(60.dp, 30.dp), contentPadding = PaddingValues(0.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xff009f91), contentColor = Color.White)) { Text(if (selectOnly) "选择" else if (!allowed) "不可点评" else if (count == 0) "首评" else "去点评", fontSize = 13.sp, fontWeight = FontWeight.Normal) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RatingEditorSheet(api: ContentApi, row: JSONObject, session: ContentSession, onDismiss: () -> Unit) {
    var stars by remember { mutableIntStateOf(0) }; var message by remember { mutableStateOf("") }; var owner by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope(); val identity = remember { api.imageCacheScope() }; val scroll = rememberScrollState(); ReviewScrollActivity(scroll)
    com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().imePadding().verticalScroll(scroll).padding(start = 20.dp, top = 20.dp, end = 20.dp, bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("点评 ${row.text("title")}", fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            Row { (1..5).forEach { number -> com.green.note.ui.ReviewIconButton(onClick = { stars = number }, enabled = !busy) { MaterialGlyph(if (number <= stars) "star" else "star_border", color = Color(0xffd99f18), contentDescription = "${number}星") } } }
            TextField(message, { if (it.length <= 1000) message = it }, Modifier.fillMaxWidth(), textStyle = MaterialTheme.typography.bodyLarge, minLines = 3, maxLines = 6, colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent), placeholder = { Text("写下你的使用体验") }, supportingText = { Text("${message.length}/1000", Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.End) })
            if (row.text("entityType") == "product") com.green.note.ui.ReviewTileLayout(
                modifier=Modifier.toggleable(owner,enabled=!busy,role=androidx.compose.ui.semantics.Role.Checkbox,onValueChange={owner=it}),horizontalPadding=14.dp,
                trailing={com.green.note.ui.ReviewCheckbox(owner,null,enabled=!busy,shrinkWrap=true)},
                title={Text("我已购买 / 正在使用",fontSize=15.sp,lineHeight=20.25.sp,fontWeight=com.green.note.ui.adjustedWeight(600),color=if(busy)MaterialTheme.colorScheme.onSurface.copy(alpha=.38f)else MaterialTheme.colorScheme.onSurface)}
            )
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            com.green.note.ui.ReviewButton(enabled = !busy && stars > 0, onClick = { if (!session.authenticated) { error = if (session.anonymous) "当前为匿名登录，无法使用此功能" else "请先登录" } else scope.launch {
                busy = true; error = null
                try { check(api.imageCacheScope() == identity) { "账号已切换，请重新打开点评" }
                    api.submitMultipart("/v6/feed/createFeed", buildMap {
                        put("type", "rating"); put("message", message.trim()); put("targetType", if (row.text("entityType") == "product") "product_phone" else "tag"); put("targetId", row.text("id")); put("rating_score_1", "$stars"); if (row.text("entityType") == "product") put("buy_status", if (owner) "1" else "0")
                        listOf("comment_good", "comment_general", "comment_bad", "comment_good_pic", "comment_general_pic", "comment_bad_pic").forEach { put(it, "") }
                    }); onDismiss()
                } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message } finally { busy = false }
            } }) { Text(if (busy) "发布中…" else "发布点评") }
        }
    }
}

