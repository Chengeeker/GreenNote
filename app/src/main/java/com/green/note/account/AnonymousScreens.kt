package com.green.note.account

import com.green.note.ui.ReviewText as Text

import com.green.note.content.communityTextLimit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import com.green.note.ui.reviewCardSurface
import com.green.note.ui.reviewCardBorder
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.em
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.PreferenceRow
import com.green.note.ui.ReviewPage
import com.green.note.ui.SectionCard
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.io.ByteArrayOutputStream

internal fun accountUidInput(value: String): String = value.filter { it in '0'..'9' }.take(30)

internal suspend fun publicIdentity(uid: String, requestPublic: suspend (String, Map<String, String>) -> JSONObject): JSONObject? {
    if (uid.isBlank()) return null
    require(Regex("^[0-9]{1,30}$").matches(uid)) { "UID 只能填写 1–30 位数字" }
    return coroutineScope {
        val profile = async { try { requestPublic("/v6/user/profile", mapOf("uid" to uid)) }
            catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { JSONObject() } }
        val space = requestPublic("/v6/user/space", mapOf("uid" to uid))
        val profileRoot = profile.await()
        val merged = JSONObject()
        val spaceData = space.optJSONObject("data")
        val profileData = profileRoot.optJSONObject("data")
        listOf(spaceData?.optJSONObject("userInfo") ?: spaceData?.optJSONObject("user_info"),
            profileData?.optJSONObject("userInfo") ?: profileData?.optJSONObject("user_info"), spaceData, profileData, space).forEach { value ->
            value?.keys()?.forEach { key -> merged.put(key, value.get(key)) }
        }
        val name = listOf("username", "userName", "name").firstNotNullOfOrNull { merged.optString(it).takeIf(String::isNotBlank) }
            ?: error("没有读取到该 UID 的公开主页资料")
        JSONObject().put("uid", uid).put("username", name).put("userAvatar",
            listOf("userAvatar", "avatar", "user_avatar").firstNotNullOfOrNull { merged.optString(it).takeIf(String::isNotBlank) }.orEmpty())
    }
}

/** Creating an account is allowed offline; editing an existing public identity remains strict. */
internal suspend fun optionalPublicIdentity(uid: String, requestPublic: suspend (String, Map<String, String>) -> JSONObject): JSONObject? =
    try { publicIdentity(uid, requestPublic) }
    catch (cancelled: CancellationException) { throw cancelled }
    catch (_: Exception) { null }

internal suspend fun readAvatar(context: Context, uri: Uri): String = withContext(Dispatchers.IO) {
    val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) { val read = input.read(buffer); if (read < 0) break; require(output.size() + read <= 16 * 1024 * 1024) { "头像图片超过 16 MB" }; output.write(buffer, 0, read) }
        output.toByteArray()
    } ?: error("无法读取头像")
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    require(bounds.outWidth > 0 && bounds.outHeight > 0) { "无法解码头像" }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1024) sample *= 2
    val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: error("无法解码头像")
    val orientation = runCatching { bytes.inputStream().use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) } }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
    val matrix = Matrix().apply { when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
        ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
        ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
        ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
    } }
    val decoded = if (matrix.isIdentity) source else Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true).also { if (it !== source) source.recycle() }
    val size = minOf(decoded.width, decoded.height)
    val crop = Bitmap.createBitmap(decoded, (decoded.width - size) / 2, (decoded.height - size) / 2, size, size)
    val result = Bitmap.createScaledBitmap(crop, 192, 192, true)
    try { ByteArrayOutputStream().use { output -> check(result.compress(Bitmap.CompressFormat.PNG, 100, output)); output.toByteArray().toByteString().base64() } }
    finally { if (result !== crop) result.recycle(); if (crop !== decoded) crop.recycle(); decoded.recycle() }
}

@Composable
fun LocalAvatar(avatar: String, name: String, modifier: Modifier = Modifier) {
    val bitmap = remember(avatar) { avatar.decodeBase64()?.toByteArray()?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    Box(modifier.size(60.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
        val initial = remember(name) { if (name.isEmpty()) "匿" else android.icu.text.BreakIterator.getCharacterInstance().run { setText(name); name.substring(0, next().coerceAtLeast(1)) } }
        if (bitmap == null) CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale = 1f)) {
            // Flutter CircleAvatar uses titleMedium and MediaQuery.withNoTextScaling.
            Text(initial, color = MaterialTheme.colorScheme.onPrimaryContainer, style = MaterialTheme.typography.titleMedium)
        }
        else Image(bitmap, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
    }
}

@Composable
fun LocalProfileScreen(repository: AccountRepository, activate: Boolean, requestPublic: suspend (String, Map<String, String>) -> JSONObject,
                       onBack: () -> Unit, onManage: () -> Unit) {
    val state by repository.state.collectAsState()
    val local = remember(state.localJson) { JSONObject(state.localJson) }
    val activeId = local.getString("activeProfileId")
    var name by remember(activeId, local.getString("name")) { mutableStateOf(local.getString("name")) }
    // Flutter's controller edits rebuild only TextField. The avatar reads the draft
    // again when the parent rebuilds for pick/save/manage, not on each keystroke.
    var avatarName by remember(activeId, local.getString("name")) { mutableStateOf(local.getString("name")) }
    val savedUid = local.optJSONObject("publicIdentity")?.optString("uid").orEmpty()
    var uid by remember(activeId, savedUid) { mutableStateOf(savedUid) }
    var avatar by remember(activeId, local.getString("avatar")) { mutableStateOf(local.getString("avatar")) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            try { avatar = readAvatar(context, uri) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { com.green.note.ui.AppToastState().showSnackbar("无法读取头像，请选择其他图片") }
            finally { busy = false }
        }
    }
    ReviewPage("匿名账户资料", onBack, topPadding = 16.dp, contentHorizontalPadding = 20.dp, bottomPadding = 20.dp) {
        Text("用户名和头像仅在本机展示，不会创建酷安账号。可选填 UID 读取公开主页内容；这不会验证账号所有权，也不会开放云端写操作。")
        Spacer(Modifier.height(24.dp))
        LocalAvatar(avatar, avatarName, Modifier.align(Alignment.CenterHorizontally))
        com.green.note.ui.ReviewTextButton(onClick = { avatarName = name; picker.launch("image/*") }, enabled = !busy, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("从设备选择头像") }
        if (avatar.isNotEmpty()) com.green.note.ui.ReviewTextButton(onClick = { avatarName = name; avatar = "" }, enabled = !busy, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("使用默认头像") }
        AccountTextField(name, { name = communityTextLimit(it, 40).text }, Modifier.fillMaxWidth(), enabled = !busy, label = "用户名", singleLine = true,
            supportingText = { Text("${communityTextLimit(name, Int.MAX_VALUE).characters}/40", Modifier.fillMaxWidth(), textAlign = TextAlign.End) })
        Spacer(Modifier.height(16.dp))
        AccountTextField(uid, { uid = accountUidInput(it) }, Modifier.fillMaxWidth(), enabled = !busy,
            label = "用户 UID（选填）", supportingText = { Row(Modifier.fillMaxWidth()) { Text("保存时读取公开资料；清空后恢复匿名资料显示。", Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis); Spacer(Modifier.width(16.dp)); Text("${uid.length}/30") } },
            leadingIcon = { MaterialGlyph("cloud_outlined") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
        Spacer(Modifier.height(16.dp))
        com.green.note.ui.ReviewButton(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = { scope.launch {
            avatarName = name
            busy = true
            try {
                val expectedRevision = repository.state.value.revision
                val identity = publicIdentity(uid.trim(), requestPublic)
                repository.updateProfile(activeId, name, avatar, identity, activate = activate, expectedRevision = expectedRevision)
                onBack()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { com.green.note.ui.AppToastState().showSnackbar(failure.message ?: "无法保存匿名账户") }
            finally { busy = false }
        } }) { Text(if (busy) "正在保存…" else if (activate) "进入匿名账户" else "保存资料") }
        Spacer(Modifier.height(24.dp))
        PreferenceRow("管理已有匿名账户", "共 ${local.getJSONArray("profiles").length()} 个独立账户", "manage_accounts_outlined", !busy,
            { avatarName = name; onManage() }, titleSize = 13f, subtitleSize = 12f, horizontalPadding = 0.dp, minVerticalPadding = 4.dp,
            trailing = { MaterialGlyph("chevron_right", color = MaterialTheme.colorScheme.onSurfaceVariant) })
    }
}

@Composable
fun AnonymousAccountsScreen(repository: AccountRepository, requestPublic: suspend (String, Map<String, String>) -> JSONObject,
                            onBack: () -> Unit, onEdit: (String) -> Unit) {
    val state by repository.state.collectAsState()
    val root = remember(state.localJson) { JSONObject(state.localJson) }
    val array = root.getJSONArray("profiles")
    val profiles = (0 until array.length()).map { array.getJSONObject(it) }
    var create by remember { mutableStateOf(false) }
    var delete by remember { mutableStateOf<JSONObject?>(null) }
    var name by remember { mutableStateOf("") }
    var uid by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    fun run(operation: suspend () -> Unit) { scope.launch {
        busy = true; error = null
        try { operation() } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "操作失败，请重试" }
        finally { busy = false }
    } }
    ReviewPage("匿名账户管理", onBack, topPadding = 8.dp, bottomPadding = 24.dp, actions = {
            com.green.note.ui.ReviewIconButton(onClick = { name = "匿名账户${profiles.size + 1}"; uid = ""; create = true }, enabled = !busy) { MaterialGlyph("add_rounded", contentDescription = "新建匿名账户") }
    }) {
        Surface(Modifier.padding(horizontal = 10.dp, vertical = 5.dp), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .5f), border = BorderStroke(.8.dp, reviewCardBorder())) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            MaterialGlyph("info_outline_rounded", size = 20.dp, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(10.dp))
            Text("支持同时保留多个匿名账户，每个账户拥有独立的 UID 身份、关注列表、收藏列表及设备关注，互不影响；退出登录不会删除资料。", fontSize = 13.sp, lineHeight = 18.2.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        Spacer(Modifier.height(16.dp))
        Text("已有账户 (${profiles.size})", Modifier.padding(start = 14.dp), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        profiles.forEach { profile ->
            val current = state.anonymous && root.getString("activeProfileId") == profile.getString("id")
            var menu by remember(profile.getString("id")) { mutableStateOf(false) }
            Surface(shape = RoundedCornerShape(20.dp), shadowElevation = 1.dp, border = BorderStroke(.8.dp, reviewCardBorder()), color = if (current) MaterialTheme.colorScheme.primaryContainer.copy(alpha = .3f) else reviewCardSurface()) {
                com.green.note.ui.ReviewTileLayout(Modifier.clickable(enabled = !busy && !current) { run { repository.switchProfile(profile.getString("id")); com.green.note.ui.AppToastState().showSnackbar("已切换至 ${profile.getString("name")}") } },
                    horizontalPadding = 14.dp, verticalPadding = 4.dp,
                    leading = { LocalAvatar(profile.getString("avatar"), profile.getString("name"), Modifier.size(48.dp)) },
                    subtitle = { Column {
                        Spacer(Modifier.height(4.dp))
                        val identity = profile.optJSONObject("publicIdentity")
                        Text(if (identity == null) "纯本地匿名账户（未绑定公开主页）" else "绑定公开 UID: ${identity.optString("uid")} (${identity.optString("username")})", fontSize = 12.sp, lineHeight = 1.4.em, fontWeight = com.green.note.ui.adjustedWeight(400), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(2.dp))
                        Text("关注: ${profile.getJSONObject("follows").length()} · 收藏: ${profile.getJSONObject("favorites").length()} · 机型关注: ${profile.getJSONObject("productFollows").length()}", fontSize = 11.sp, lineHeight = 1.4.em, fontWeight = com.green.note.ui.adjustedWeight(400), color = MaterialTheme.colorScheme.primary)
                    } },
                    trailing = { Box {
                        com.green.note.ui.ReviewIconButton(onClick = { menu = true }, enabled = !busy) { MaterialGlyph("more_vert_rounded", contentDescription = "账户操作") }
                        com.green.note.ui.ReviewPopupMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            if (!current) com.green.note.ui.ReviewPopupMenuItem(text = { Text("切换登录此账户") }, leadingIcon = { MaterialGlyph("swap_horiz_rounded", size = 18.dp) }, onClick = { menu = false; run { repository.switchProfile(profile.getString("id")); com.green.note.ui.AppToastState().showSnackbar("已切换至 ${profile.getString("name")}") } })
                            com.green.note.ui.ReviewPopupMenuItem(text = { Text("编辑名称与主页UID") }, leadingIcon = { MaterialGlyph("edit_outlined", size = 18.dp) }, onClick = { menu = false; run { if (root.getString("activeProfileId") != profile.getString("id")) repository.switchProfile(profile.getString("id")); onEdit(profile.getString("id")) } })
                            com.green.note.ui.ReviewPopupMenuItem(text = { Text("删除此账户", color = androidx.compose.ui.graphics.Color(0xfff44336)) }, leadingIcon = { MaterialGlyph("delete_outline_rounded", size = 18.dp, color = androidx.compose.ui.graphics.Color(0xfff44336)) }, onClick = { menu = false; delete = profile })
                        }
                    } }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(profile.getString("name"), Modifier.weight(1f, fill = false), fontSize = 16.sp, lineHeight = 1.35.em, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (current) { Spacer(Modifier.width(8.dp)); Text("当前使用", Modifier.background(MaterialTheme.colorScheme.primary, RoundedCornerShape(10.dp)).padding(horizontal = 6.dp, vertical = 2.dp), color = MaterialTheme.colorScheme.onPrimary, fontSize = 10.sp, lineHeight = 1.35.em, fontWeight = FontWeight.Bold) }
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
        }
        Spacer(Modifier.height(12.dp))
        com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = { name = "匿名账户${profiles.size + 1}"; uid = ""; create = true }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { MaterialGlyph("add_rounded"); com.green.note.ui.ReviewButtonIconGap(); Text("新建匿名账户") }
    }
    if (create) com.green.note.ui.ReviewAlertDialog(onDismissRequest = { if (!busy) create = false }, title = { Text("新建匿名账户") }, text = {
        Column {
            AccountTextField(name, { name = communityTextLimit(it, 40).text }, enabled = !busy, label = "账户名称", placeholder = "例如：匿名账户1、刷机测试", supportingText = { Text("${communityTextLimit(name, Int.MAX_VALUE).characters}/40", Modifier.fillMaxWidth(), textAlign = TextAlign.End) })
            Spacer(Modifier.height(12.dp))
            AccountTextField(uid, { uid = accountUidInput(it) }, enabled = !busy, label = "用户 UID（选填）", placeholder = "可选填酷安数字 UID 绑定公开主页", supportingText = { Text("${uid.length}/30", Modifier.fillMaxWidth(), textAlign = TextAlign.End) },
                leadingIcon = { MaterialGlyph("cloud_outlined") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
        }
    }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { create = false }, enabled = !busy) { Text("取消") } }, confirmButton = {
        com.green.note.ui.ReviewButton(onClick = { run { val expected = repository.state.value.revision; repository.createProfile(name, publicIdentity = optionalPublicIdentity(uid.trim(), requestPublic), expectedRevision = expected); create = false; com.green.note.ui.AppToastState().showSnackbar("已创建并切换至 $name") } }, enabled = !busy) { Text("创建并进入") }
    })
    delete?.let { target -> com.green.note.ui.ReviewAlertDialog(onDismissRequest = { if (!busy) delete = null }, title = { Text("删除 ${target.getString("name")}？") },
        text = { Text(if (profiles.size == 1) "当前仅剩一个匿名账户，删除后将重置为全新的空账户。确定重置吗？" else "删除后，该匿名账户独立的关注、收藏与主页资料将无法恢复。确定删除吗？") },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { delete = null }, enabled = !busy) { Text("取消") } }, confirmButton = {
            com.green.note.ui.ReviewButton(onClick = { run { repository.deleteProfile(target.getString("id")); delete = null; com.green.note.ui.AppToastState().showSnackbar(if (profiles.size == 1) "已重置匿名账户" else "已删除账户 ${target.getString("name")}") } }, enabled = !busy,
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text(if (profiles.size == 1) "重置账户" else "删除账户") }
        }) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnonymousAccountPickerSheet(repository: AccountRepository, requestPublic: suspend (String, Map<String, String>) -> JSONObject,
                                onDismiss: () -> Unit, onManage: () -> Unit) {
    val pickerScroll = androidx.compose.foundation.lazy.rememberLazyListState()
    com.green.note.ui.ReviewScrollActivity(pickerScroll)
    val state by repository.state.collectAsState()
    val root = remember(state.localJson) { JSONObject(state.localJson) }
    val array = root.getJSONArray("profiles")
    val profiles = (0 until array.length()).map { array.getJSONObject(it) }
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var create by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var uid by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    if (!create) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }) {
        Column(Modifier.fillMaxWidth().padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("选择匿名账户", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = { onDismiss(); onManage() }, enabled = !busy) { MaterialGlyph("settings_outlined", size = 18.dp); com.green.note.ui.ReviewButtonIconGap(); Text("管理账户") }
            }
            Spacer(Modifier.height(4.dp)); Text("每个匿名账户拥有各自独立的 UID 身份、关注和收藏，互不干扰。", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            LazyColumn(Modifier.heightIn(max = with(androidx.compose.ui.platform.LocalDensity.current) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.height.toDp() * .45f }), state = pickerScroll, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(profiles, key = { it.getString("id") }) { profile ->
                    val current = state.anonymous && root.getString("activeProfileId") == profile.getString("id")
                    Surface(shape = RoundedCornerShape(20.dp), shadowElevation = 1.dp, border = BorderStroke(.8.dp, reviewCardBorder()), color = if (current) MaterialTheme.colorScheme.primaryContainer.copy(alpha = .35f) else reviewCardSurface()) {
                        com.green.note.ui.ReviewTileLayout(Modifier.clickable(enabled = !busy) { scope.launch {
                            busy = true
                            try { repository.switchProfile(profile.getString("id")); com.green.note.ui.AppToastState().showSnackbar("已切换至 ${profile.getString("name")}"); onDismiss() }
                            catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message }
                            finally { busy = false }
                        } }, horizontalPadding = 14.dp,
                            leading = { LocalAvatar(profile.getString("avatar"), profile.getString("name"), Modifier.size(40.dp)) },
                            subtitle = {
                                val identity = profile.optJSONObject("publicIdentity")
                                Text("${if (identity == null) "纯本地" else "UID: ${identity.optString("uid")}"} · 关注 ${profile.getJSONObject("follows").length()} · 收藏 ${profile.getJSONObject("favorites").length()}", fontSize = 12.sp, lineHeight = 1.4.em, fontWeight = com.green.note.ui.adjustedWeight(400), color = MaterialTheme.colorScheme.onSurfaceVariant)
                            },
                            trailing = { MaterialGlyph(if (current) "check_circle_rounded" else "arrow_forward_ios_rounded", size = if (current) 24.dp else 14.dp, color = if (current) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(profile.getString("name"), Modifier.weight(1f, false), fontSize = 13.sp, lineHeight = 1.35.em, fontWeight = if (current) FontWeight.Bold else FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    if (current) { Spacer(Modifier.width(8.dp)); Text("当前使用", Modifier.background(MaterialTheme.colorScheme.primary, RoundedCornerShape(10.dp)).padding(horizontal = 6.dp, vertical = 2.dp), fontSize = 10.sp, lineHeight = 1.35.em, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimary) }
                                }
                        }
                    }
                }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Spacer(Modifier.height(12.dp)); com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = { name = "匿名账户${profiles.size + 1}"; uid = ""; create = true }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { MaterialGlyph("add_rounded"); com.green.note.ui.ReviewButtonIconGap(); Text("新建匿名账户") }
        }
    }
    if (create) com.green.note.ui.ReviewAlertDialog(onDismissRequest = { if (!busy) onDismiss() }, title = { Text("新建匿名账户") }, text = {
        Column {
            AccountTextField(name, { name = communityTextLimit(it, 40).text }, enabled = !busy, label = "账户名称", placeholder = "例如：匿名账户1、刷机测试", supportingText = { Text("${communityTextLimit(name, Int.MAX_VALUE).characters}/40", Modifier.fillMaxWidth(), textAlign = TextAlign.End) })
            Spacer(Modifier.height(12.dp)); AccountTextField(uid, { uid = accountUidInput(it) }, enabled = !busy, label = "用户 UID（选填）", placeholder = "可选填酷安数字 UID 绑定公开主页", leadingIcon = { MaterialGlyph("cloud_outlined") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), supportingText = { Text("${uid.length}/30", Modifier.fillMaxWidth(), textAlign = TextAlign.End) })
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }, dismissButton = { com.green.note.ui.ReviewTextButton(onClick = onDismiss, enabled = !busy) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = { scope.launch {
        busy = true; error = null
        try { val expected = repository.state.value.revision; val identity = optionalPublicIdentity(uid.trim(), requestPublic); repository.createProfile(name, publicIdentity = identity, expectedRevision = expected); com.green.note.ui.AppToastState().showSnackbar("已创建并切换至 $name"); onDismiss() }
        catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message }
        finally { busy = false }
    } }, enabled = !busy) { Text("创建并进入") } })
}
