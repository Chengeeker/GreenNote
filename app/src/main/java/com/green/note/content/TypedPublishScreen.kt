package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.ReviewOutlinedTextField as OutlinedTextField

import com.green.note.ui.rememberReviewScrollState
import android.content.Context
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
internal fun TypedPublishScreen(api: ContentApi, type: String, onDone: () -> Unit, initialProductId: String = "", initialTag: String = "", onLink: (String) -> Unit = {}) {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f
    val foreground = if (type == "feed") scheme.onSurface else if (dark) Color(0xFFCCCCCC) else Color(0xFF333333)
    MaterialTheme(colorScheme = scheme.copy(onSurface = foreground)) {
        CompositionLocalProvider(
            LocalContentColor provides foreground,
            com.green.note.ui.LocalMaterialGlyphColor provides if (type == "feed") com.green.note.ui.LocalMaterialGlyphColor.current else foreground,
            com.green.note.ui.LocalIconButtonColor provides if (type == "feed") com.green.note.ui.LocalIconButtonColor.current else foreground,
        ) {
            Box(Modifier.fillMaxSize().background(if (dark) if (type == "feed") Color(0xFF141416) else Color(0xFF1E1E1E) else Color.White).navigationBarsPadding()) {
                TypedPublishContent(api, type, onDone, initialProductId, initialTag, onLink)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun TypedPublishContent(api: ContentApi, type: String, onDone: () -> Unit, initialProductId: String, initialTag: String, onLink: (String) -> Unit) {
    val context = LocalContext.current
    val surface = MaterialTheme.colorScheme.surface
    val dark = surface.red + surface.green + surface.blue < 1.5f
    val scope = rememberCoroutineScope()
    val session = LocalContentSession.current
    var editor by remember(type) { mutableStateOf(TextFieldValue("")) }
    val message = editor.text
    var title by rememberSaveable(type) { mutableStateOf("") }
    var pictures by rememberSaveable(type) { mutableStateOf(arrayListOf<String>()) }
    var uploaded by remember { mutableStateOf(mapOf<String, String>()) }
    var category by rememberSaveable(type) { mutableStateOf("") }
    var price by rememberSaveable(type) { mutableStateOf("") }
    var link by rememberSaveable(type) { mutableStateOf("") }
    var business by rememberSaveable(type) { mutableStateOf(false) }
    var multi by rememberSaveable(type) { mutableStateOf(false) }
    var options by rememberSaveable(type) { mutableStateOf(arrayListOf("", "", "", "")) }
    var days by rememberSaveable(type) { mutableStateOf("7") }
    var limit by rememberSaveable(type) { mutableStateOf("1") }
    var topic by rememberSaveable(type) { mutableStateOf(initialTag) }
    var productId by rememberSaveable(type) { mutableStateOf(initialProductId) }
    var productName by rememberSaveable(type) { mutableStateOf("") }
    var productPicker by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val toast = remember { com.green.note.ui.AppToastState() }
    LaunchedEffect(error) { error?.let { toast.showSnackbar(it); error = null } }
    var discard by remember { mutableStateOf(false) }
    var coverMode by rememberSaveable { mutableStateOf(type != "picture") }
    var cover by rememberSaveable { mutableStateOf("") }
    var location by rememberSaveable { mutableStateOf("") }
    var extraTitle by rememberSaveable { mutableStateOf("") }
    var voteId by rememberSaveable { mutableStateOf("") }
    var visibility by rememberSaveable { mutableStateOf("公开") }
    var sheet by remember { mutableStateOf("") }
    var editField by remember { mutableStateOf("") }; var editValue by remember { mutableStateOf("") }
    var emoji by remember { mutableStateOf(false) }
    var imported by remember { mutableStateOf<String?>(null) }
    val focus = remember { FocusRequester() }; val keyboard = LocalSoftwareKeyboardController.current
    val form = PublishForm(type, message, title, pictures, category, price, link, business, multi, if (multi) options else options.take(2), days.toIntOrNull() ?: 0, limit.toIntOrNull() ?: 0, cover = cover, topic = topic, productId = productId, location = location, extraTitle = extraTitle, voteId = voteId)
    val hasDraft = message.isNotEmpty() || title.isNotEmpty() || pictures.isNotEmpty() || options.any(String::isNotEmpty) || price.isNotEmpty() || cover.isNotEmpty() || location.isNotEmpty() || link.isNotEmpty() || productName.isNotEmpty() || category.isNotEmpty()
    fun insert(text: String, cursorOffset: Int = text.length) { val start = editor.selection.min.coerceIn(0, message.length); val end = editor.selection.max.coerceIn(start, message.length); editor = TextFieldValue(message.replaceRange(start, end, text), TextRange(start + cursorOffset)) }
    fun field(name: String, value: String) { editField = name; editValue = value }
    fun close() { if (!busy && !picking) { if (hasDraft) discard = true else onDone() } }
    BackHandler(hasDraft || busy || picking) { close() }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        if (uris.isNotEmpty()) {
            picking = true
            scope.launch {
                val saved = mutableListOf<String>(); var committed = false
                try {
                    val available = ((if (type == "feed" && coverMode) 1 else 9) - pictures.size).coerceAtLeast(0)
                    withContext(Dispatchers.IO) { uris.take(available).forEach { saved += cacheDraftImage(context, it) } }
                    pictures = ArrayList(pictures + saved)
                    committed = true
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (failure: Exception) { error = failure.message }
                finally { if (!committed) withContext(kotlinx.coroutines.NonCancellable + Dispatchers.IO) { saved.forEach { File(it).delete() } }; picking = false }
            }
        }
    }
    val coverPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null) scope.launch {
        picking = true
        var saved = ""; var committed = false
        try { withContext(Dispatchers.IO) { saved = cacheDraftImage(context, uri) }; val old = cover; cover = saved; committed = true; if (old.isNotEmpty()) withContext(Dispatchers.IO) { File(old).delete() } }
        catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message }
        finally { if (!committed && saved.isNotEmpty()) withContext(kotlinx.coroutines.NonCancellable + Dispatchers.IO) { File(saved).delete() }; picking = false }
    } }
    val documentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) scope.launch {
        try { val text = withContext(Dispatchers.IO) {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytesLimited(2 * 1024 * 1024) } ?: error("无法读取文档")
            java.nio.charset.StandardCharsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF")
        }; if (message.isEmpty()) editor = TextFieldValue(text, TextRange(text.length)) else imported = text }
        catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = "请选择 UTF-8 纯文本文档（可从金山文档导出）" }
    } }
    val label = when (type) { "article" -> "发布图文"; "picture" -> "发布酷图"; "ershou" -> "发布二手信息"; "vote" -> "发起投票"; else -> "发布动态" }
    Box(Modifier.fillMaxSize()) {
    com.green.note.ui.ActivePage(!productPicker) {
    Column(Modifier.fillMaxSize().pointerInput(busy) {
        if (busy) awaitPointerEventScope { while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() } }
    }) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = if (type == "feed") 8.dp else 0.dp), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("close", "关闭", ::close, size = if (type == "feed") 24.dp else 26.dp)
            if (type == "feed") Row(Modifier.weight(1f), horizontalArrangement = Arrangement.Center) {
                Row(Modifier.height(34.dp).clip(RoundedCornerShape(17.dp)).background(if (dark) Color(0xFF222225) else Color(0xFFEAEAEA)).padding(2.dp)) {
                    listOf("大封面" to true, "九宫格" to false).forEach { (text, value) -> Text(text, Modifier.clip(RoundedCornerShape(15.dp)).background(if (coverMode == value) if (dark) Color(0xFF1B382B) else Color(0xFFE8F5E9) else Color.Transparent).clickable(enabled = !busy) { coverMode = value }.padding(horizontal = 14.dp, vertical = 5.dp), fontSize = 13.5.sp, fontWeight = if (coverMode == value) FontWeight.Bold else FontWeight.Normal, color = if (coverMode == value) if (dark) Color(0xFF34D399) else Color(0xFF2E7D32) else if (dark) Color(0xFF8E8E93) else Color(0xFF666666)) }
                }
            } else Text(label, Modifier.weight(1f), fontSize = 20.sp)
            com.green.note.ui.ReviewOutlinedButton(onClick = {
                if (!session.authenticated) { error = session.loginRequiredMessage; return@ReviewOutlinedButton }
                if (visibility != "公开") { error = "当前发布接口尚不支持此可见范围，请改为公开后发布"; return@ReviewOutlinedButton }
                busy = true; error = null
                val scopeAtStart = api.imageCacheScope()
                scope.launch {
                    try {
                        val urls = mutableListOf<String>()
                        for (path in pictures) {
                            val url = uploaded[path] ?: api.uploadFeedImage(withContext(Dispatchers.IO) {
                                val file = File(path)
                                check(file.isFile && file.length() in 1..16L * 1024 * 1024) { "图片缓存已失效，请重新选择" }
                                prepareUploadPng(file)
                            }).also { uploaded = uploaded + (path to it) }
                            urls.add(url)
                        }
                        check(api.imageCacheScope() == scopeAtStart) { "账号已切换，请重新进入发布页" }
                        val coverUrl = if (cover.isEmpty()) "" else uploaded[cover] ?: api.uploadFeedImage(withContext(Dispatchers.IO) { prepareUploadPng(File(cover)) }).also { uploaded = uploaded + (cover to it) }
                        check(api.imageCacheScope() == scopeAtStart) { "账号已切换，请重新进入发布页" }
                        val body = form.copy(pictures = urls, cover = coverUrl).body(System.currentTimeMillis() / 1000)
                        api.request("/v6/feed/createFeed", "POST", body = body)
                        withContext(Dispatchers.IO) { (pictures + cover).filter(String::isNotEmpty).forEach { File(it).delete() } }
                        onDone()
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (failure: Exception) { error = failure.message }
                    finally { busy = false }
                }
            }, enabled = form.validationError() == null && !busy && !picking, shape = RoundedCornerShape(if (type == "feed") 6.dp else 2.dp), border = androidx.compose.foundation.BorderStroke(if (type == "feed") .8.dp else 1.dp, if (form.validationError() == null) if (type == "feed" && dark) Color(0xFF34D399) else if (type == "feed") MaterialTheme.colorScheme.primary else Color(0xFF009688) else if (type == "feed") if (dark) Color(0xFF48484C) else Color(0xFFCCCCCC) else Color(0xFF808080)), contentPadding = PaddingValues(horizontal = 14.dp), modifier = Modifier.padding(end = if (type == "feed") 8.dp else 16.dp).height(if (type == "feed") 30.dp else 32.dp)) {
                if (busy && type == "feed") com.green.note.ui.ReviewCircularProgress(Modifier.size(14.dp), strokeWidth = 2.dp)
                else Text(if (busy) "发布中" else "发布", fontSize = if (type == "feed") 13.5.sp else 15.sp, fontWeight = FontWeight.Normal, color = if (type == "feed") if (form.validationError() == null) if (dark) Color(0xFF34D399) else MaterialTheme.colorScheme.primary else if (dark) Color(0xFFC0C0C4) else Color(0xFF999999) else Color.Unspecified)
            }
        }
        @Composable fun BodyField(hint: String, min: Int = 4, height: androidx.compose.ui.unit.Dp? = null) {
            com.green.note.ui.ReviewBasicTextField(editor, { editor = it }, Modifier.fillMaxWidth().then(if (height != null) Modifier.height(height) else Modifier).padding(horizontal = 16.dp, vertical = if (type == "feed") 6.dp else 10.dp).focusRequester(focus).composerKeyboardReveal(), readOnly = busy, minLines = if (height != null) 1 else min, maxLines = if (type == "feed") 15 else Int.MAX_VALUE,
                textStyle = LocalTextStyle.current.copy(fontSize = if (type == "feed") 15.5.sp else 15.sp, lineHeight = if (type == "feed") 22.475.sp else 22.5.sp, color = MaterialTheme.colorScheme.onSurface), cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { field -> Box { if (editor.text.isEmpty()) Text(hint, fontSize = 15.sp, color = if (type == "feed") if (dark) Color(0xFF5A5A60) else Color(0xFF999999) else Color(0xFF808080)); field() } })
        }
        @Composable fun TopicRow() {
            val feed = type == "feed"
            val green = if (feed) if (dark) Color(0xFF34D399) else Color(0xFF2E7D32) else Color(0xFF009688)
            val secondary = if (feed && dark) Color(0xFF7C7C82) else Color(0xFF888888)
            Column(Modifier.fillMaxWidth().clickable(enabled = !busy) { sheet = "topic" }.padding(horizontal = 16.dp)) {
                Row(if (feed) Modifier.padding(vertical = 12.dp) else Modifier.height(60.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(if (feed) 24.dp else 32.dp).clip(RoundedCornerShape(6.dp)).background(if (feed) if (dark) Color(0xFF163324) else Color(0xFFE8F5E9) else green.copy(alpha = .12f)), contentAlignment = Alignment.Center) { MaterialGlyph(if (feed) "add_rounded" else "add", size = if (feed) 16.dp else 28.dp, color = green) }
                    Spacer(Modifier.width(if (feed) 8.dp else 10.dp)); Text("发布到", fontSize = if (feed) 15.5.sp else 16.sp, fontWeight = if (feed) FontWeight.Bold else FontWeight.Normal)
                    if (feed && topic.isNotEmpty()) { Spacer(Modifier.width(8.dp)); Text("# $topic", Modifier.widthIn(max = 130.dp).clip(RoundedCornerShape(12.dp)).background(if (dark) Color(0xFF1B382B) else Color(0xFFE8F5E9)).padding(horizontal = 8.dp, vertical = 2.dp), fontSize = 12.sp, color = green, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }
                    Spacer(Modifier.width(if (feed) 2.dp else 12.dp))
                    Text(if (feed) if (topic.isEmpty()) "选择合适的板块会有更多的赞" else "更换板块" else topic.ifEmpty { if (type == "vote") "观点的节点会同步关联" else "选择合适的板块会有更多的赞" }, Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.End, fontSize = if (feed) 13.sp else 12.sp, color = secondary, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                    Spacer(Modifier.width(2.dp)); MaterialGlyph(if (feed) "chevron_right_rounded" else "chevron_right", size = if (feed) 16.dp else 24.dp, color = secondary)
                }
                if (!feed) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .18f))
            }
        }
        @Composable fun Media() {
            ComposerMedia(type, pictures, if (type == "feed" && coverMode) 1 else 9, !busy && !picking,
                { picker.launch("image/*") }, { path -> pictures = ArrayList(pictures - path); uploaded = uploaded - path; scope.launch(Dispatchers.IO) { File(path).delete() } }, { pictures = ArrayList(it) })
        }
        @Composable fun Stripe() { HorizontalDivider(thickness = 8.dp, color = if (dark) Color(0xFF111111) else Color(0xFFF5F5F5)) }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
        val bodyHeight = (maxHeight - 400.dp).coerceIn(110.dp, 300.dp)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberReviewScrollState())) {
            if (type in setOf("feed", "article", "vote")) TopicRow()
            when (type) {
                "feed" -> { Media(); BodyField("分享你此刻的想法…", 5); HorizontalDivider(thickness = .5.dp); ComposerRow("visibility_outlined", "谁可以看", visibility) { sheet = "visibility" } }
                "article" -> {
                    Box(Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp).fillMaxWidth().height(80.dp).clip(RoundedCornerShape(8.dp)).background(if (dark) Color(0xFF2B2B2D) else Color(0xFFF0F0F0)).clickable(enabled = !busy) { coverPicker.launch("image/*") }, contentAlignment = Alignment.Center) {
                        if (cover.isNotEmpty()) AsyncImage(cover, "题图", Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                        else Column(horizontalAlignment = Alignment.CenterHorizontally) { Text("＋添加题图", fontSize = 20.sp, color = Color(0xFF999999)); Spacer(Modifier.height(8.dp)); Text("(无关题图会导致无法获得推荐)", fontSize = 12.sp, color = Color(0xFF999999)) }
                    }
                    ComposerField(title, { title = it.take(100) }, "标题", !busy, oneLine = true); HorizontalDivider(thickness = .5.dp); BodyField("正文", height = bodyHeight); if (pictures.isNotEmpty()) Media(); Stripe()
                    ComposerRow("visibility_outlined", "谁可以看", visibility) { sheet = "visibility" }; HorizontalDivider(thickness = .5.dp)
                    ComposerRow("upload_file_outlined", "导入文档", "金山文档") { documentPicker.launch(arrayOf("text/plain", "text/markdown")) }
                }
                "picture" -> {
                    Media(); BodyField("以上传壁纸为主，发布广告、色情、手机截图和无关低质量图片将会被删除并对账号做禁言处理。", height = 150.dp); HorizontalDivider(thickness = .5.dp)
                    ComposerRow("menu", "选择分类", category) { field("选择分类", category) }; Stripe(); ComposerRow("visibility_outlined", "谁可以看", visibility) { sheet = "visibility" }
                }
                "ershou" -> {
                    ComposerRow("phone_android", productName.ifEmpty { "选择商品" }) { productPicker = true }; Stripe(); ComposerField(title, { title = it.take(100) }, "宝贝品牌型号", !busy, oneLine = true); HorizontalDivider(thickness = .5.dp)
                    BodyField("写写宝贝的转手原因，入手渠道等具体信息吧", height = 120.dp); Media(); HorizontalDivider(thickness = .5.dp); ComposerRow("location_on_outlined", location.ifEmpty { "选择位置" }) { field("所在城市", location) }; Stripe()
                    ComposerRow("currency_yen", "开个价", if (price.isEmpty()) "" else "¥$price") { field("开个价", price) }; HorizontalDivider(thickness = .5.dp)
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        MaterialGlyph("account_circle_outlined", size = 25.dp); Spacer(Modifier.width(14.dp)); Text("我的身份", Modifier.weight(1f), fontSize = 16.sp)
                        listOf("个人" to false, "商家" to true).forEach { (label, value) -> Text(label, Modifier.padding(start = 12.dp).clip(RoundedCornerShape(6.dp)).background(if (business == value) Color(0xFF009688).copy(alpha = .18f) else MaterialTheme.colorScheme.surfaceContainerHighest).clickable { business = value }.padding(horizontal = 12.dp, vertical = 6.dp), fontSize = 14.sp, color = if (business == value) Color(0xFF009688) else MaterialTheme.colorScheme.onSurface) }
                    }; HorizontalDivider(thickness = .5.dp); ComposerRow("link", "商品链接", link) { field("商品链接", link) }
                }
                "vote" -> {
                    ComposerField(title, { title = it.take(100) }, "投票标题", !busy, oneLine = true); HorizontalDivider(thickness = .5.dp); BodyField("投票说明", height = 165.dp); Stripe()
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        MaterialGlyph("poll_outlined", size = 25.dp); Spacer(Modifier.width(14.dp)); Text("模式选择", Modifier.weight(1f), fontSize = 16.sp)
                        listOf("PK模式" to false, "多选项模式" to true).forEach { (label, value) -> Text(label, Modifier.padding(start = 8.dp).clip(RoundedCornerShape(3.dp)).background(if (multi == value) Color(0xFF009688).copy(alpha = .12f) else MaterialTheme.colorScheme.surfaceContainerHighest).clickable { multi = value }.padding(horizontal = 10.dp, vertical = 8.dp), fontSize = 12.sp, color = if (multi == value) Color(0xFF009688) else Color(0xFF888888)) }
                    }; Stripe()
                    (if (multi) options else options.take(2)).forEachIndexed { index, value ->
                        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text((0x2460 + index).toChar().toString(), Modifier.width(36.dp), fontSize = 27.sp, color = Color(0xFF888888))
                            Text(if (multi) "选项${"一二三四五六七八九十"[index]}" else if (index == 0) "正方观点" else "反方观点", fontSize = 15.sp, color = Color(0xFF888888))
                            Box(Modifier.weight(1f)) { ComposerField(value, { next -> options = ArrayList(options.toMutableList().also { it[index] = next.take(100) }) }, "选项内容", !busy, true) }
                            if (multi && options.size > 2) ContentIcon("close", "删除选项${index + 1}", { options = ArrayList(options.toMutableList().also { it.removeAt(index) }); limit = (limit.toIntOrNull() ?: 1).coerceAtMost(options.size).toString() })
                        }; HorizontalDivider(Modifier.padding(horizontal = 16.dp), thickness = .5.dp)
                    }
                    if (multi && options.size < 10) ComposerRow("add_circle_outline", "添加选项") { options = ArrayList(options + "") }; Stripe(); ComposerRow("schedule", "截止时间", "${days}天") { sheet = "days" }
                    if (multi) { HorizontalDivider(thickness = .5.dp); ComposerRow("how_to_vote_outlined", "投票上限", if (limit == "1") "单项" else "最多${limit}项") { sheet = "limit" } }
                }
            }
            Spacer(Modifier.height(with(LocalDensity.current) { WindowInsets.ime.getBottom(this).toDp() }))
        }
        }
        if (type in setOf("feed", "picture")) Row(Modifier.fillMaxWidth().height(if (type == "feed") 36.dp else 46.dp).horizontalScroll(rememberScrollState()).padding(horizontal = if (type == "picture") 8.dp else 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            listOf("数码日常", "123云盘", "VibeCoding", "魅族PA", "今日份日常", "玩机日记", "手机摄影").take(if (type == "picture") 4 else 7).forEachIndexed { index, tag ->
                val featured = index == 0
                val color = if (featured) if (dark) Color(0xFF34D399) else Color(0xFF2E7D32) else if (dark) Color(0xFFCCCCCC) else Color(0xFF555555)
                Row(Modifier.clip(RoundedCornerShape(16.dp)).background(if (type == "picture") if (dark) Color(0xFF333333) else Color(0xFFF0F0F2) else if (featured) if (dark) Color(0xFF1B2A22) else Color(0xFFE8F5E9) else if (dark) Color(0xFF222225) else Color(0xFFF0F0F2)).clickable { insert("#$tag# "); if (topic.isEmpty()) topic = tag }.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (featured) { MaterialGlyph("campaign_rounded", size = 15.dp, color = color); Spacer(Modifier.width(5.dp)) }
                    Text("# $tag", fontSize = 12.5.sp, fontWeight = if (type != "picture" && featured) FontWeight.SemiBold else FontWeight.Normal, color = color)
                }
            }
        }
        HorizontalDivider(thickness = .5.dp)
        @Composable fun ToolbarIcon(name: String, description: String, onClick: () -> Unit) {
            com.green.note.ui.ReviewIconButton(onClick = onClick) { MaterialGlyph(name, size = if (type == "feed") 24.dp else 25.dp,
                color = if (type == "feed" && description == "表情" && emoji) if (dark) Color(0xFF34D399) else Color(0xFF2E7D32) else LocalContentColor.current,
                contentDescription = description) }
        }
        com.green.note.ui.ReviewToolbarIcons(if (type == "feed") if (dark) Color(0xFF8E8E93) else Color(0xFF666666) else LocalContentColor.current) {
        Row(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = if (type == "feed") 12.dp else 0.dp), horizontalArrangement = Arrangement.SpaceAround, verticalAlignment = Alignment.CenterVertically) {
            ToolbarIcon("sentiment_satisfied_alt_outlined", "表情", { emoji = !emoji; if (emoji) keyboard?.hide() else { focus.requestFocus(); keyboard?.show() } })
            if (type != "vote") ToolbarIcon("image_outlined", "添加图片", { if (!busy && !picking) picker.launch("image/*") })
            ToolbarIcon(if (type == "feed") "alternate_email_rounded" else "alternate_email", "提及用户", { insert("@"); emoji = false; focus.requestFocus(); keyboard?.show() })
            if (type != "ershou") ToolbarIcon(if (type == "feed") "tag_rounded" else "tag", "话题", { insert("##", 1); emoji = false; focus.requestFocus(); keyboard?.show() })
            if (type == "article") ToolbarIcon("shopping_bag_outlined", "关联商品", { productPicker = true })
            if (type in setOf("feed", "article")) ToolbarIcon(if (type == "feed") "add_circle_outline_rounded" else "add_circle_outline", "更多", { sheet = if (type == "article") "article_more" else "extended" })
            if (type == "feed") ToolbarIcon("language_rounded", "谁可以看", { sheet = "visibility" })
            if (type in setOf("picture", "vote")) ToolbarIcon("grid_view_outlined", "选择板块", { sheet = "topic" })
            if (type != "feed") com.green.note.ui.ReviewIconButton(onClick = { emoji = false; focus.requestFocus(); keyboard?.show() }) {
                Box(Modifier.size(24.dp).border(1.8.dp, LocalContentColor.current, androidx.compose.foundation.shape.CircleShape), contentAlignment = Alignment.Center) { MaterialGlyph("dialpad_rounded", size = 16.dp) }
            }
        }
        }
        if (emoji) {
            val emojiScroll = androidx.compose.foundation.lazy.grid.rememberLazyGridState()
            com.green.note.ui.ReviewScrollActivity(emojiScroll)
            LazyVerticalGrid(GridCells.Fixed(8), Modifier.fillMaxWidth().height(220.dp).background(if (dark) Color(0xFF1B1B1E) else Color(0xFFF6F6F8)).padding(horizontal = 12.dp, vertical = 8.dp), state = emojiScroll, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(listOf("滑稽", "doge", "笑哭", "捂脸", "点赞", "妙啊", "机智", "吃瓜", "微笑", "思考", "流泪", "白眼", "发怒", "疑问", "酷", "偷笑", "爱心", "OK", "强", "抱拳", "握手", "胜利", "二哈", "黑线", "委屈", "再见", "可怜", "亲亲", "坏笑", "阴险", "傲慢", "害羞")) { name -> Box(Modifier.aspectRatio(1f).clip(RoundedCornerShape(8.dp)).clickable { insert("[$name]") }, contentAlignment = Alignment.Center) { Text("[$name]", fontSize = 11.sp, color = if (dark) Color(0xFF34D399) else Color(0xFF2E7D32), textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) } }
            }
        }
    }
    if (sheet.isNotEmpty()) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { sheet = "" }, containerColor = if (sheet in setOf("topic", "visibility", "extended")) Color.Transparent else MaterialTheme.colorScheme.surface) {
        Surface(color = if (sheet in setOf("topic", "visibility", "extended")) if (dark) Color(0xFF222226) else Color.White else MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)) { Column {
        when (sheet) {
            "visibility" -> Column(Modifier.fillMaxWidth().padding(start = 16.dp, top = 20.dp, end = 16.dp, bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("谁可以看", fontSize = 16.5.sp, fontWeight = FontWeight.Bold, color = if (dark) Color.White else Color.Black.copy(alpha = .87f)); Spacer(Modifier.height(16.dp))
                listOf(Triple("公开", "所有人可见（默认）", "public_rounded"), Triple("仅自己可见", "私密动态，仅本人可查阅", "lock_outline_rounded"), Triple("好友圈", "仅互相关注的酷友好友可见", "people_outline_rounded")).forEach { (value, summary, icon) -> com.green.note.ui.ReviewTileLayout(modifier = Modifier.clickable { visibility = value; sheet = "" }, leading = { MaterialGlyph(icon) }, trailing = if (visibility == value) ({ MaterialGlyph("check_rounded", color = Color(0xFF34D399)) }) else null, subtitle = { Text(summary, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp), color = MaterialTheme.colorScheme.onSurfaceVariant) }) { Text(value) } }
            }
            "days", "limit" -> (if (sheet == "days") listOf(1, 3, 7, 15, 30) else (1..options.size).toList()).forEach { value -> ContentListTile(headlineContent = { Text(if (sheet == "days") "${value}天" else if (value == 1) "单项" else "最多${value}项") }, modifier = Modifier.clickable { if (sheet == "days") days = "$value" else limit = "$value"; sheet = "" }) }
            "topic" -> {
                var query by remember { mutableStateOf("") }
                val topics = listOf("数码日常", "玩机技巧", "酷安日常", "今日份日常", "好物推荐", "手机摄影", "电脑讨论", "搞机日记", "开箱体验", "每日打卡", "123云盘", "VibeCoding", "魅族PA").filter { it.contains(query, true) }
                Column(Modifier.height(with(LocalDensity.current) { (LocalWindowInfo.current.containerSize.height * .65f).toDp() }).padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 8.dp)) {
                    Box(Modifier.align(Alignment.CenterHorizontally).size(36.dp, 4.dp).clip(RoundedCornerShape(2.dp)).background(if (dark) Color.White.copy(alpha = .24f) else Color.Black.copy(alpha = .12f))); Spacer(Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) { Text("选择发布的板块 / 话题", Modifier.weight(1f), fontSize = 16.5.sp, fontWeight = FontWeight.Bold); ContentIcon("close_rounded", "关闭", { sheet = "" }) }
                    Spacer(Modifier.height(8.dp))
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(if (dark) Color(0xFF2A2A2E) else Color(0xFFF0F0F2)), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.width(48.dp), contentAlignment = Alignment.Center) { MaterialGlyph("search_rounded") }
                        com.green.note.ui.ReviewBasicTextField(query, { query = it }, Modifier.weight(1f).padding(top = 10.dp, end = 14.dp, bottom = 10.dp), singleLine = true,
                            textStyle = LocalTextStyle.current.copy(fontSize = 16.sp, color = LocalContentColor.current), cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
                            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { if (query.isNotBlank()) { topic = query.trim(); sheet = "" } }), keyboardOptions = KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                            decorationBox = { field -> Box { if (query.isEmpty()) Text("搜索或输入自定义话题…", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp); field() } })
                    }
                    Spacer(Modifier.height(12.dp))
                    LazyColumn(Modifier.weight(1f), state = com.green.note.ui.rememberReviewLazyListState()) { items(topics) { tag ->
                        com.green.note.ui.ReviewTileLayout(modifier = Modifier.clickable { topic = tag; sheet = "" }, leading = { MaterialGlyph("tag_rounded", color = if (topic == tag) Color(0xFF34D399) else if (dark) Color.White.copy(alpha = .54f) else Color.Black.copy(alpha = .54f)) }, trailing = if (topic == tag) ({ MaterialGlyph("check_rounded", color = Color(0xFF34D399)) }) else null) { Text(tag, color = if (topic == tag) Color(0xFF34D399) else if (dark) Color.White else Color.Black.copy(alpha = .87f), fontWeight = if (topic == tag) FontWeight.Bold else FontWeight.Normal) }
                        if (tag != topics.lastOrNull() || query.isNotBlank() && query.trim() !in topics) HorizontalDivider(thickness = .5.dp, color = if (dark) Color.White.copy(alpha = .12f) else Color.Black.copy(alpha = .12f))
                    }
                        if (query.isNotBlank() && query.trim() !in topics) item { com.green.note.ui.ReviewTileLayout(modifier = Modifier.clickable { topic = query.trim(); sheet = "" }, leading = { MaterialGlyph("add_rounded", color = Color(0xFF34D399)) }) { Text("使用自定义话题 \"#${query.trim()}#\"") } }
                    }
                }
            }
            "article_more" -> {
                com.green.note.ui.ReviewTileLayout(modifier = Modifier.clickable { sheet = ""; picker.launch("image/*") }, leading = { MaterialGlyph("image_outlined") }) { Text("插入图片") }
                com.green.note.ui.ReviewTileLayout(modifier = Modifier.clickable { sheet = ""; productPicker = true }, leading = { MaterialGlyph("devices") }) { Text("关联产品") }
                com.green.note.ui.ReviewTileLayout(modifier = Modifier.clickable { sheet = ""; documentPicker.launch(arrayOf("text/plain", "text/markdown")) }, leading = { MaterialGlyph("upload_file_outlined") }) { Text("导入文档") }
            }
            "extended" -> {
                var extra by remember { mutableStateOf(extraTitle) }; var place by remember { mutableStateOf(location) }; var product by remember { mutableStateOf(productId) }; var vote by remember { mutableStateOf(voteId) }
                Column(Modifier.fillMaxWidth().imePadding().padding(start = 20.dp, top = 20.dp, end = 20.dp, bottom = 24.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Text("扩展信息与设置", Modifier.weight(1f), fontSize = 16.5.sp, fontWeight = FontWeight.Bold); ContentIcon("close_rounded", "关闭", { sheet = "" }) }; Spacer(Modifier.height(12.dp))
                    OutlinedTextField(extra, { extra = it }, Modifier.fillMaxWidth(), textStyle = MaterialTheme.typography.bodyLarge, label = { Text("文章标题（可选）") }); Spacer(Modifier.height(10.dp)); OutlinedTextField(place, { place = it }, Modifier.fillMaxWidth(), textStyle = MaterialTheme.typography.bodyLarge, label = { Text("发布位置（可选）") }); Spacer(Modifier.height(10.dp)); OutlinedTextField(product, { product = it }, Modifier.fillMaxWidth(), textStyle = MaterialTheme.typography.bodyLarge, label = { Text("关联产品 ID（可选）") }); Spacer(Modifier.height(10.dp)); OutlinedTextField(vote, { vote = it }, Modifier.fillMaxWidth(), textStyle = MaterialTheme.typography.bodyLarge, label = { Text("关联投票 ID（可选）") })
                    Spacer(Modifier.height(16.dp))
                    com.green.note.ui.ReviewButton(onClick = { extraTitle = extra.trim(); location = place.trim(); productId = product.trim(); voteId = vote.trim(); sheet = "" }, Modifier.fillMaxWidth().height(44.dp)) { Text("保存设置") }
                }
            }
        }
    }
    } }
    if (editField.isNotEmpty()) com.green.note.ui.ReviewAlertDialog(onDismissRequest = { editField = "" }, title = { Text(editField) }, text = { CommunityFormField(editValue, { editValue = it }, "", hint = editField, autofocus = true, keyboardType = if (editField == "开个价") KeyboardType.Decimal else KeyboardType.Text) }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { editField = "" }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewTextButton(onClick = {
        val value = editValue.trim()
        when (editField) { "选择分类" -> category = value; "所在城市" -> location = value; "开个价" -> if (value.toDoubleOrNull()?.let { it.isFinite() && it > 0 } == true) price = value else { error = "请输入有效价格"; return@ReviewTextButton }; "商品链接" -> if (value.isEmpty() || validWebUrl(value)) link = value else { error = "请输入有效的商品链接"; return@ReviewTextButton } }; editField = ""
    }) { Text("确定") } })
    imported?.let { text -> com.green.note.ui.ReviewAlertDialog(onDismissRequest = { imported = null }, title = { Text("替换当前正文？") }, text = { Text("导入的文档将替换当前正文。") }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { imported = null }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewTextButton(onClick = { editor = TextFieldValue(text, TextRange(text.length)); imported = null }) { Text("替换") } }) }
    if (discard) com.green.note.ui.ReviewAlertDialog(onDismissRequest = { discard = false }, title = { Text("确定放弃编辑吗？") }, text = { Text("退出后已输入的内容将不会被保存。") },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { discard = false }) { Text("继续编辑") } }, confirmButton = { com.green.note.ui.ReviewTextButton(onClick = { scope.launch { withContext(Dispatchers.IO) { (pictures + cover).filter(String::isNotEmpty).forEach { File(it).delete() } }; onDone() } }) { Text("放弃", color = Color(0xFFFF5252)) } })
    }
    com.green.note.ui.StackedRoutes(if (productPicker) listOf("rating_target") else emptyList(), { productPicker = false }) {
        RatingSquareScreen(api, { productPicker = false }, LocalContentSession.current,
            onMyRatings = { uid -> onLink("/v6/page/dataList?url=" + Uri.encode("#/feed/nodeRatingList") + "&uid=" + Uri.encode(uid) + "&targetType=all&parseRatingToFeed=1") },
            onSelected = { product -> productId = product.text("id", "entityId"); productName = product.text("title"); productPicker = false })
    }
    }
}

@Composable
private fun ComposerField(value: String, onChange: (String) -> Unit, hint: String, enabled: Boolean, oneLine: Boolean = false,
    minimumLines: Int = 1, keyboardType: KeyboardType = KeyboardType.Text) {
    val title = hint in setOf("标题", "宝贝品牌型号", "投票标题")
    com.green.note.ui.ReviewBasicTextField(value, onChange, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = if (title) 14.dp else 10.dp).composerKeyboardReveal(), readOnly = !enabled,
        minLines = minimumLines, maxLines = if (title) 2 else if (oneLine) 1 else Int.MAX_VALUE, keyboardOptions = KeyboardOptions(keyboardType = keyboardType), cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
        textStyle = LocalTextStyle.current.copy(fontSize = if (title) 18.sp else 15.sp, lineHeight = if (title) 27.sp else 22.5.sp, fontWeight = if (title) FontWeight.SemiBold else FontWeight.Normal, color = MaterialTheme.colorScheme.onSurface),
        decorationBox = { field -> Box { if (value.isEmpty()) Text(hint, fontSize = if (title) 18.sp else 15.sp, color = Color(0xFF808080)); field() } })
}

@Composable
private fun ComposerRow(icon: String, title: String, value: String = "", onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        MaterialGlyph(icon, size = 25.dp); Spacer(Modifier.width(14.dp)); Text(title, Modifier.weight(1f), fontSize = 16.sp)
        if (value.isNotEmpty()) Text(value, Modifier.widthIn(max = with(LocalDensity.current) { (LocalWindowInfo.current.containerSize.width * .45f).toDp() }), fontSize = 14.sp, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
        MaterialGlyph("chevron_right", size = 25.dp)
    }
}

private fun java.io.InputStream.readBytesLimited(limit: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
    while (true) { val size = read(buffer); if (size < 0) break; check(output.size() + size <= limit) { "文档过大" }; output.write(buffer, 0, size) }
    return output.toByteArray()
}

internal fun cacheDraftImage(context: Context, uri: Uri): String {
    val directory = File(context.cacheDir, "compose/media/drafts").apply { mkdirs() }
    val destination = File(directory, UUID.randomUUID().toString())
    try {
        context.contentResolver.openInputStream(uri)?.use { input -> destination.outputStream().use { output ->
            val buffer = ByteArray(8192)
            var total = 0L
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                check(total <= 16L * 1024 * 1024) { "图片不能超过16 MB" }
                output.write(buffer, 0, count)
            }
            check(total > 0) { "图片内容为空" }
        } } ?: error("无法读取图片")
        return destination.absolutePath
    } catch (failure: Exception) { destination.delete(); throw failure }
}
