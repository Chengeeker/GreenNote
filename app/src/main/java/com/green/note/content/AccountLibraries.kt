package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import androidx.lifecycle.repeatOnLifecycle
import org.json.JSONObject

@Composable
internal fun LocalLibraryScreen(api: ContentApi, field: String, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit) {
    var rows by remember(field) { mutableStateOf<List<JSONObject>?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val identity = remember { api.imageCacheScope() }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    val toast = remember { com.green.note.ui.AppToastState() }
    LaunchedEffect(field, revision, lifecycle) { lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.RESUMED) {
        try { rows = api.localLibrary(field).reversed(); failure = null }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { failure = error.message }
        kotlinx.coroutines.awaitCancellation()
    } }
    when {
        failure != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewTextButton(onClick = { revision++ }) { Text(failure.orEmpty()) } }
        rows == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
        rows!!.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(when (field) { "follows" -> "在博主主页点击关注，即可加入这里"; "productFollows" -> "在数码详情点击关注，即可加入这里"; else -> "在动态详情点击收藏，即可加入这里" }) }
        else -> LazyColumn { items(rows!!, key = { if (field == "follows") it.text("uid", "id") else it.text("id", "feedid", "feedId", "productId") }) { row ->
            ContentListTile(
                headlineContent = { Text(row.text(if (field == "follows") "username" else if (field == "productFollows") "title" else "message"), maxLines = 3, overflow = TextOverflow.Ellipsis) },
                supportingContent = { Text(if (field == "follows") "UID ${row.text("uid", "id")}" else if (field == "productFollows") row.text("brand_title", "brand") else "${row.text("username")} · 已保存文字及图片地址") },
                leadingContent = { if (field == "productFollows") ContentImage(api, row.text("pic", "logo"), null, Modifier.size(40.dp), scale = ContentScale.Fit)
                    else ContentAvatar(api, row.text("userAvatar"), row.text("username"), 42.dp) },
                trailingContent = { ContentIcon("remove_circle_outline", if (field == "follows") "取消本地关注" else "移除", { scope.launch {
                    try {
                        check(identity == api.imageCacheScope()) { "账号已变化" }
                        when (field) { "follows" -> api.followUser(row, true); "productFollows" -> api.followProduct(row, true); else -> api.toggleLocalFavorite(row) }
                        revision++
                    } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { toast.showSnackbar(error.message ?: "操作失败") }
                } }) },
                modifier = Modifier.clickable { if (field == "follows") onUser(row.text("uid", "id")) else onOpen(JSONObject(row.toString()).put("entityType", if (field == "productFollows") "product" else "feed")) })
        } }
    }
}

internal fun accountCategory(row: JSONObject): String {
    val pathType = runCatching { java.net.URI(row.text("url").removePrefix("#")).path.orEmpty().split('/').firstOrNull(String::isNotEmpty).orEmpty() }.getOrDefault("")
    for (value in listOf(row.text("typeName", "entityTypeName", "type_name"), row.text("targetType", "target_type"), row.text("entityType", "entity_type"), pathType)) {
        val category = when (value.lowercase()) { "product", "数码" -> "数码"; "topic", "tag", "t", "话题" -> "话题"; "user", "u", "用户" -> "用户"; "apk", "app", "应用" -> "应用"; "feed", "动态" -> "动态"; "collection", "收藏单" -> "收藏单"; "dyh", "看看号" -> "看看号"; else -> "" }
        if (category.isNotEmpty()) return category
    }
    return row.text("typeName", "entityTypeName")
}

@Composable
internal fun CollectionLibraryScreen(api: ContentApi, uid: String, onBack: () -> Unit, onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, title: String = "我的收藏单", route: String = "") {
    val pageTitle = title
    var create by remember { mutableStateOf(false) }
    var title by remember { mutableStateOf("") }; var description by remember { mutableStateOf("") }; var public by remember { mutableStateOf(true) }
    val repo = remember(api) { ContentRepository(api) }
    val state = remember(uid, route) { ContentListState { page, first, last -> repo.page(if (route.isNotEmpty()) contentRequest(route) else ContentRequest("/v6/collection/list", mapOf("uid" to uid, "showDefault" to "1")), page, first, last) } }
    val scope = rememberCoroutineScope(); val identity = remember { api.imageCacheScope() }; val toast = remember { com.green.note.ui.AppToastState() }
    Column(Modifier.fillMaxSize()) {
        ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp)); Spacer(Modifier.width(16.dp))
            Text(pageTitle.ifEmpty { "我的收藏单" }, Modifier.weight(1f), fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
            ContentIcon("add_rounded", "新建收藏单", { title = ""; description = ""; public = true; create = true })
        }
        ContentList(api, state, onOpen, onUser, onLink, onGallery, {}, {}, contentPadding = PaddingValues(bottom = 24.dp), emptyHeightFraction = .55f, indexedItemContent = { index, row -> CollectionLibraryTile(row, index == 0, index == state.rows.lastIndex, onOpen) })
    }
    if (create) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { create = false }, title = { Text("新建收藏单") }, text = {
        Column {
            CommunityFormField(title, { title = it }, "名称", hint = "请输入收藏单名称", autofocus = true)
            Spacer(Modifier.height(12.dp))
            CommunityFormField(description, { description = it }, "说明（选填）", hint = "请输入收藏单说明")
            Spacer(Modifier.height(8.dp))
            com.green.note.ui.ReviewTileLayout(horizontalPadding = 0.dp, subtitle = { Text(if (public) "所有人可见" else "仅自己可见", fontSize = 12.sp) }, trailing = { com.green.note.ui.ReviewSwitch(public, { public = it }) }) { Text("公开收藏单") }
        }
    }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { create = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
        create = false
        if (title.isBlank()) return@ReviewButton
        val name = title.trim(); val note = description.trim(); val isOpen = public
        scope.launch { try {
            check(identity == api.imageCacheScope()) { "账号已变化" }
            api.submitMultipart("/v6/collection/create", mapOf("title" to name, "description" to note, "isOpen" to if (isOpen) "1" else "0", "pic" to "", "sourceId" to ""))
            toast.showSnackbar("创建收藏单成功"); state.load(true)
        } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { toast.showSnackbar("创建失败: ${error.message}") } }
    }) { Text("创建") } })
}
