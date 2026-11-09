package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

internal fun objectScalars(data: JSONObject): List<Pair<String, String>> = data.keys().asSequence().mapNotNull { key ->
    val value = data.opt(key)
    if (value is JSONObject || value is JSONArray) null else key to (value?.toString() ?: "null")
}.toList()

internal fun objectFieldLabel(key: String): String = key.replace(Regex("([a-z])([A-Z])"), "$1 $2")

@Composable
internal fun ApiObjectDetail(api: ContentApi, initial: JSONObject? = null, request: ContentRequest? = null) {
    val owner = remember(api) { api.imageCacheScope() }
    var data by remember(initial, request) { mutableStateOf(initial) }
    var loading by remember(request) { mutableStateOf(request != null) }
    var error by remember(request) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val scroll = rememberLazyListState()
    ReviewScrollActivity(scroll)
    suspend fun reload() {
        val target = request ?: return
        loading = true; error = null
        try {
            val response = api.request(target.path, query = target.query)
            check(owner == api.imageCacheScope()) { "账号已变更" }
            data = response.optJSONObject("data") ?: response
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: failure.toString() }
        finally { loading = false }
    }
    LaunchedEffect(request) { if (request != null) reload() }
    val value = data
    if (value == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        if (loading) com.green.note.ui.ReviewCircularProgress()
        else Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            val message = error.orEmpty()
            val restricted = listOf("captcha", "验证码", "受限", "限制", "403").any { message.contains(it, true) }
            Text(if (restricted) "暂无内容" else message, textAlign = TextAlign.Center)
            if (!restricted) { Spacer(Modifier.height(12.dp)); com.green.note.ui.ReviewFilledTonalButton(onClick = { scope.launch { reload() } }) { Text("重试") } }
        }
    } else {
        val fields = remember(value) { objectScalars(value) }
        val body: @Composable BoxScope.() -> Unit = {
            LazyColumn(state = scroll, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
                item {
                    ObjectHeader(api, value)
                    if (request != null) Spacer(Modifier.height(12.dp))
                }
                items(fields, key = { it.first }) { (key, text) ->
                    ReviewTileLayout(horizontalPadding = 14.dp,
                        isThreeLine = request != null && text.length > 60,
                        subtitle = {
                            if (request == null) SelectionContainer { Text(text, fontSize = 12.5.sp, lineHeight = 17.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            else Text(text, fontSize = 12.5.sp, lineHeight = 17.5.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }) {
                        Text(objectFieldLabel(key), fontSize = 15.sp, lineHeight = 20.25.sp, fontWeight = adjustedWeight(600))
                    }
                }
                if (error != null) item { com.green.note.ui.ReviewTextButton(onClick = { scope.launch { reload() } }) { Text("刷新失败：$error") } }
            }
        }
        if (request == null) Box(Modifier.fillMaxSize(), content = body)
        else ReviewRefreshBox(loading, { scope.launch { reload() } }, Modifier.fillMaxSize(), failed = error != null, content = body)
    }
}

@Composable
private fun ObjectHeader(api: ContentApi, data: JSONObject) {
    val scheme = MaterialTheme.colorScheme
    val title = data.text("title", "name", "username", "apkName")
    val description = data.text("description", "message", "brief")
    val icon = data.text("icon", "logo", "avatar", "pic")
    Surface(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 5.dp), shape = RoundedCornerShape(20.dp),
        color = scheme.surfaceContainerLow, shadowElevation = 1.dp, border = BorderStroke(.8.dp, scheme.outlineVariant.copy(alpha = .25f))) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.Top) {
            if (icon.isNotEmpty()) { ContentAvatar(api, icon, "", 64.dp); Spacer(Modifier.width(14.dp)) }
            Column(Modifier.weight(1f)) {
                if (title.isNotEmpty()) Text(title, style = MaterialTheme.typography.titleLarge)
                if (description.isNotEmpty()) { Spacer(Modifier.height(8.dp)); SelectionContainer { Text(description) } }
            }
        }
    }
}
