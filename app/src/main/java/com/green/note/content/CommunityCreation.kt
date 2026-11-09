package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.border
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

internal data class AlbumItem(val id: String = "", val name: String, val description: String = "", val logo: String = "", val level: Int = 1)

internal fun albumForm(title: String, description: String, items: List<AlbumItem>, ranked: Boolean, target: JSONObject?): Map<String, String> {
    require(title.isNotBlank() && title.length <= 100 && description.length <= 1000 && items.isNotEmpty() && items.size <= 100 &&
        items.all { it.name.isNotBlank() && it.name.length <= 100 && it.description.length <= 1000 && (!ranked || it.level in 1..5) }) { "清单内容无效" }
    return buildMap {
        put("title", title.trim()); put("description", description.trim()); put("album_type", if (ranked) "1" else "0")
        put("targetType", if (target == null) "" else if (target.text("entityType") == "product") "product_phone" else "tag")
        put("targetId", target?.text("id").orEmpty())
        items.forEachIndexed { index, item ->
            mapOf("item_id" to item.id, "item_name" to item.name, "item_description" to item.description, "item_logo" to item.logo,
                "item_images" to "", "id" to "", "level" to if (ranked) "${item.level}" else "1", "display_order" to "$index").forEach { (key, value) -> put("productItems[$index][$key]", value) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AlbumCreateScreen(api: ContentApi, initialRank: Boolean, session: ContentSession = ContentSession(), onMyRatings: (String) -> Unit = {}, onCreated: (() -> Unit)? = null, onDone: () -> Unit) {
    var ranked by rememberSaveable { mutableStateOf(initialRank) }; var title by rememberSaveable { mutableStateOf("") }; var description by rememberSaveable { mutableStateOf("") }
    var entries by remember { mutableStateOf<List<AlbumItem>>(emptyList()) }; var target by remember { mutableStateOf<JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }; var discard by remember { mutableStateOf(false) }; var confirm by remember { mutableStateOf(false) }
    var sourceLevel by remember { mutableStateOf<Int?>(null) }; var pickerLevel by remember { mutableStateOf<Int?>(null) }; var chooseTarget by remember { mutableStateOf(false) }
    var editIndex by remember { mutableStateOf<Int?>(null) }; var customLevel by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope(); val owner = remember { api.imageCacheScope() }; val toast = remember { com.green.note.ui.AppToastState() }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f; val background = if (dark) Color(0xff1e1e1e) else Color.White
    val scheme = if (dark) MaterialTheme.colorScheme.copy(primary = Color(0xff009688), onSurface = Color(0xffcccccc), onSurfaceVariant = Color(0xff999999)) else MaterialTheme.colorScheme
    val drafted = title.isNotEmpty() || description.isNotEmpty() || entries.isNotEmpty() || target != null
    fun close() { if (!busy) { if (drafted) discard = true else onDone() } }
    BackHandler(drafted || busy || chooseTarget || pickerLevel != null) { if (chooseTarget || pickerLevel != null) { chooseTarget = false; pickerLevel = null } else close() }
    com.green.note.ui.OfficialHomeTheme {
        if (chooseTarget || pickerLevel != null) RatingSquareScreen(api, onBack = { chooseTarget = false; pickerLevel = null }, session = session, onMyRatings = onMyRatings, onSelected = { selected ->
            if (chooseTarget) target = JSONObject(selected.toString()) else if (entries.size < 100) entries = entries + AlbumItem(selected.text("id"), selected.text("title"), logo = selected.text("logo"), level = pickerLevel ?: 1)
            chooseTarget = false; pickerLevel = null
        }) else Column(Modifier.fillMaxSize().background(background).navigationBarsPadding()) {
            val divider = scheme.onSurface.copy(alpha = .12f)
            Row(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
                com.green.note.ui.ReviewIconButton(onClick = ::close, enabled = !busy) { MaterialGlyph("close", size = 26.dp, contentDescription = "关闭") }; Spacer(Modifier.weight(1f))
                Row(Modifier.height(32.dp).background(if (dark) Color(0xff333335) else Color(0xffececec), RoundedCornerShape(18.dp)).padding(2.dp)) {
                    listOf(false to "清单", true to "天梯榜").forEach { (value, label) -> Box(Modifier.width(74.dp).fillMaxHeight().background(if (ranked == value) background else Color.Transparent, RoundedCornerShape(16.dp)).clickable(enabled = !busy) { ranked = value }, contentAlignment = Alignment.Center) { Text(label, fontSize = 15.sp, color = if (ranked == value) Color(0xff009688) else scheme.onSurface) } }
                }; Spacer(Modifier.weight(1f))
                com.green.note.ui.ReviewOutlinedButton(onClick = { if (!session.authenticated || session.anonymous) toast.showSnackbar("请使用官方账号登录并填写标题") else confirm = true }, enabled = !busy && title.isNotBlank() && entries.isNotEmpty(), shape = RoundedCornerShape(3.dp), modifier = Modifier.padding(end = 16.dp).height(30.dp).widthIn(min = 56.dp), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp)) { Text(if (busy) "创建中" else "创建", fontWeight = FontWeight.Normal) }
            }; HorizontalDivider(color = divider)
            val scroll = rememberScrollState(); com.green.note.ui.ReviewScrollActivity(scroll)
            Column(Modifier.weight(1f).verticalScroll(scroll)) {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    Row(Modifier.fillMaxWidth().height(56.dp).clickable(enabled = !busy) { chooseTarget = true }, verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(32.dp).background(Color(0xff009688).copy(alpha = .1f), RoundedCornerShape(6.dp)), contentAlignment = Alignment.Center) { MaterialGlyph("add", color = Color(0xff009688), size = 28.dp) }
                        Spacer(Modifier.width(10.dp)); Text("发布到", fontSize = 16.sp); Spacer(Modifier.width(12.dp))
                        Text(target?.text("title") ?: "选择合适的板块会有更多的赞", Modifier.weight(1f), fontSize = 12.sp, color = Color(0xff888888), maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.End); MaterialGlyph("chevron_right", size = 24.dp)
                    }; HorizontalDivider(color = divider); Spacer(Modifier.height(14.dp))
                    AlbumTextField(title, { title = it.take(100) }, (if (ranked) "天梯榜" else "清单") + "标题", !busy, 18, FontWeight.SemiBold, 1, Modifier.fillMaxWidth().padding(vertical = 14.dp))
                    HorizontalDivider(color = divider)
                    AlbumTextField(description, { description = it.take(200) }, "介绍下你的" + (if (ranked) "天梯榜" else "清单") + "，最多200字", !busy, 15, FontWeight.Normal, 4, Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 14.dp))
                }
                fun edit(index: Int) { editIndex = index; customLevel = entries[index].level }
                fun remove(index: Int) { entries = entries.filterIndexed { i, _ -> i != index } }
                fun move(index: Int) { entries = albumMoveUp(entries, index) }
                if (!ranked) {
                    entries.forEachIndexed { index, entry -> AlbumItemRow(entry, index, !busy, { edit(index) }, { move(index) }, { remove(index) }) }
                    AlbumAddCard(dark, !busy && entries.size < 100, onClick = { sourceLevel = 1 })
                } else listOf(Triple(5, "夯", Color(0xffff5257)), Triple(4, "顶\n级", Color(0xffff9800)), Triple(3, "人\n上\n人", Color(0xffffc107)), Triple(2, "N\nP\nC", Color(0xff8bc34a)), Triple(1, "拉", Color(0xff9e9e9e))).forEach { (level, label, color) ->
                    entries.forEachIndexed { index, entry -> if (entry.level == level) AlbumItemRow(entry, index, !busy, { edit(index) }, { move(index) }, { remove(index) }) }
                    AlbumAddCard(dark, !busy && entries.size < 100, label, color) { sourceLevel = level }
                }
                Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.ime))
            }
            if (!ranked) com.green.note.ui.ReviewButton(iconPadding = true, onClick = { sourceLevel = 1 }, enabled = !busy && entries.size < 100, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 12.dp, bottom = 38.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xff009f91), contentColor = Color.White), contentPadding = PaddingValues(horizontal = 24.dp, vertical = 10.dp)) { MaterialGlyph("add_box_outlined", size = 20.dp); com.green.note.ui.ReviewButtonIconGap(); Text("添加产品", fontSize = 18.sp, fontWeight = FontWeight.Normal) }
        }
        sourceLevel?.let { level -> com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { sourceLevel = null }) {
            listOf("devices" to "从数码库选择产品", "edit_outlined" to "自定义产品").forEachIndexed { index, (icon, label) -> Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable { sourceLevel = null; if (index == 0) pickerLevel = level else { editIndex = null; customLevel = level } }.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) { MaterialGlyph(icon); Spacer(Modifier.width(16.dp)); Text(label, fontSize = 16.sp) } }
        } }
        customLevel?.let { level -> key(editIndex, level) {
            var name by remember { mutableStateOf(editIndex?.let { entries[it].name }.orEmpty()) }; var detail by remember { mutableStateOf(editIndex?.let { entries[it].description }.orEmpty()) }; var invalid by remember { mutableStateOf(false) }
            val scroll = rememberScrollState(); com.green.note.ui.ReviewScrollActivity(scroll)
            com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { customLevel = null }, title = { Text("清单商品") }, text = { Column(Modifier.verticalScroll(scroll)) {
                CommunityFormField(name, { name = it; invalid = false }, "名称", Modifier.padding(bottom = 12.dp), limit = 100, error = if (invalid) "请填写名称" else null)
                CommunityFormField(detail, { detail = it }, "说明", Modifier.padding(bottom = 12.dp), lines = 5)
            } }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { customLevel = null }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
                if (name.isBlank()) invalid = true else { val old = editIndex?.let { entries[it] }; val item = (old ?: AlbumItem(name = "", level = level)).copy(name = name.trim(), description = detail.trim())
                    entries = if (editIndex == null) entries + item else entries.mapIndexed { index, value -> if (index == editIndex) item else value }; customLevel = null
                }
            }) { Text("确认") } })
        } }
        if (discard) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { discard = false }, title = { Text("放弃编辑？") }, text = { Text("退出后已输入的内容将不会被保存。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { discard = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = onDone) { Text("确认") } })
        if (confirm) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { confirm = false }, title = { Text("发布清单？") }, text = { Text("清单将发布到你的酷安账号。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { confirm = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
            confirm = false; busy = true; scope.launch {
                try { check(session.authenticated && !session.anonymous && api.imageCacheScope() == owner) { "账号已切换，请重新进入发布页" }; api.submitMultipart("/v6/productAlbum/create", albumForm(title, description, entries, ranked, target)); check(api.imageCacheScope() == owner); (onCreated ?: onDone)() }
                catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { toast.showSnackbar("发布失败，已保留填写内容") } finally { busy = false }
            }
        }) { Text("确认") } })
    }
}
internal fun albumMoveUp(entries: List<AlbumItem>, index: Int): List<AlbumItem> = if (index in 1 until entries.size) entries.toMutableList().apply { add(index - 1, removeAt(index)) } else entries
@Composable
private fun AlbumTextField(value: String, onValueChange: (String) -> Unit, hint: String, enabled: Boolean, size: Int, weight: FontWeight, maxLines: Int, modifier: Modifier) {
    BasicTextField(value, onValueChange, modifier, enabled = enabled, singleLine = maxLines == 1, maxLines = maxLines, textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface, fontSize = size.sp, fontWeight = weight), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary), decorationBox = { field -> Box { if (value.isEmpty()) Text(hint, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = size.sp, fontWeight = weight); field() } })
}
@Composable
private fun AlbumItemRow(entry: AlbumItem, index: Int, enabled: Boolean, onEdit: () -> Unit, onUp: () -> Unit, onRemove: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 72.dp).clickable(enabled = enabled, onClick = onEdit).padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(vertical = 8.dp)) { Text(entry.name, fontSize = 16.sp); Text(entry.description, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if (index > 0) com.green.note.ui.ReviewIconButton(onClick = onUp, enabled = enabled) { MaterialGlyph("arrow_upward", contentDescription = "上移") }
        com.green.note.ui.ReviewIconButton(onClick = onRemove, enabled = enabled) { MaterialGlyph("close", contentDescription = "移除商品") }
    }
}
@Composable
private fun AlbumAddCard(dark: Boolean, enabled: Boolean, label: String = "", color: Color? = null, onClick: () -> Unit) {
    Row(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp).fillMaxWidth().height(IntrinsicSize.Min).border(1.dp, color ?: MaterialTheme.colorScheme.onSurface.copy(alpha = .15f), RoundedCornerShape(8.dp)).clickable(enabled = enabled, onClick = onClick)) {
        if (color != null) Box(Modifier.width(16.dp).fillMaxHeight().background(color, RoundedCornerShape(topStart = 7.dp, bottomStart = 7.dp)), contentAlignment = Alignment.Center) { Text(label, fontSize = 12.sp, lineHeight = 16.8.sp, color = Color.White, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center) }
        Row(Modifier.weight(1f).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp).background(if (dark) Color(0xff2b2b2d) else Color(0xfff0f0f0), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) { MaterialGlyph("add", size = 30.dp, color = Color(0xff888888)) }
            Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { Text("添加产品", fontSize = 16.sp); Spacer(Modifier.height(4.dp)); Text("支持从数码库选择产品或自定义产品", fontSize = 12.sp, maxLines = 2) }
        }
    }
}
