package com.green.note

import com.green.note.ui.ReviewText as Text

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.green.note.content.contentToolbarBorder
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.content.ContentApi
import com.green.note.content.ContentAvatar
import com.green.note.ui.MaterialGlyph
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.google.zxing.qrcode.encoder.Encoder
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException

internal fun userQrMatrix(uid: String) = Encoder.encode(userProfileUrl(uid), ErrorCorrectionLevel.M).matrix
internal fun userProfileUrl(uid: String): String {
    require(uid.matches(Regex("[1-9][0-9]*"))) { "请先登录并加载个人资料" }
    return "https://www.coolapk.com/u/$uid"
}

@Composable
fun UserQrScreen(api: ContentApi, uid: String, name: String, avatar: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { com.green.note.ui.AppToastState() }
    val matrix = remember(uid) { runCatching { userQrMatrix(uid) }.getOrNull() }
    val scheme = MaterialTheme.colorScheme
    val scroll = rememberScrollState()
    com.green.note.ui.ReviewScrollActivity(scroll)
    Scaffold(containerColor = com.green.note.ui.LocalScaffoldColor.current, topBar = {
        Column(Modifier.statusBarsPadding()) {
        com.green.note.content.ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) {
            com.green.note.ui.ReviewIconButton(onClick = onBack, modifier = Modifier.width(56.dp)) { MaterialGlyph("arrow_back", contentDescription = "返回") }
            Spacer(Modifier.width(16.dp))
            Text("我的二维码名片", fontSize = 18.sp, fontWeight = com.green.note.ui.adjustedWeight(700))
        }
        }
    }) { padding ->
        Box(Modifier.padding(padding).padding(top = 4.dp).fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(Modifier.verticalScroll(scroll).padding(20.dp).widthIn(max = 360.dp)) {
                if (matrix == null) Text("请先登录并加载个人资料") else Card(shape = RoundedCornerShape(20.dp), elevation = CardDefaults.cardElevation(1.dp),
                    colors = CardDefaults.cardColors(containerColor = com.green.note.ui.reviewCardSurface()),
                    border = BorderStroke(.8.dp, com.green.note.ui.reviewCardBorder())) {
                    Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            ContentAvatar(api, avatar, name, 48.dp)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(name.ifBlank { "酷安用户" }, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
                                Spacer(Modifier.height(4.dp)); Text("UID $uid", style = MaterialTheme.typography.bodySmall)
                            }
                        }
                        Spacer(Modifier.height(24.dp))
                        Canvas(Modifier.widthIn(max = 240.dp).fillMaxWidth().aspectRatio(1f).background(Color.White)
                            .semantics { contentDescription = "个人主页二维码，UID $uid" }.padding(32.dp)) {
                            val cell = size.width / matrix.width
                            for (y in 0 until matrix.height) for (x in 0 until matrix.width) if (matrix.get(x,y).toInt() != 0) {
                                drawRect(Color.Black, Offset(x * cell,y * cell), Size(cell + .5f,cell + .5f))
                            }
                        }
                        Spacer(Modifier.height(16.dp))
                        Text("扫一扫二维码，查看我的个人主页", textAlign = TextAlign.Center)
                        Spacer(Modifier.height(12.dp))
                        com.green.note.ui.ReviewTextButton(iconPadding = true, onClick = {
                            scope.launch {
                                try { (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("主页链接", userProfileUrl(uid))); snackbar.showSnackbar("已复制主页链接") }
                                catch (cancelled: CancellationException) { throw cancelled }
                                catch (_: Exception) { snackbar.showSnackbar("复制失败，请重试") }
                            }
                        }) { MaterialGlyph("link_rounded"); com.green.note.ui.ReviewButtonIconGap(); Text("复制主页链接") }
                    }
                }
            }
        }
    }
}


