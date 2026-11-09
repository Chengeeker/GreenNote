package com.green.note.settings

import com.green.note.ui.ReviewText as Text

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.em
import com.green.note.R
import com.green.note.ui.*
import kotlin.math.abs
import kotlin.math.roundToInt

enum class SettingsDestination { ACCOUNT, BLACKLIST, PERSONALIZATION, NOTIFICATIONS, STORAGE, CACHE, WEBDAV }

@Composable
fun SettingsScreen(onBack: () -> Unit, loginLabel: String, hasCookie: Boolean, hasAccount: Boolean, anonymous: Boolean,
    onNavigate: (SettingsDestination) -> Unit, onLogout: () -> Unit, working: Boolean = false,
) {
    var about by remember { mutableStateOf(false) }
    var logout by remember { mutableStateOf(false) }
    ReviewPage("设置", onBack, topPadding = 20.dp, bottomPadding = 16.dp) {
        SectionHeading("账号")
        Spacer(Modifier.height(12.dp))
        SectionCard {
            PreferenceRow("登录方式与账号管理", "当前登录方式：$loginLabel", "manage_accounts_outlined", onClick = { onNavigate(SettingsDestination.ACCOUNT) })
            PreferenceRow("屏蔽与黑名单", icon = "block", enabled = hasCookie, onClick = { onNavigate(SettingsDestination.BLACKLIST) })
            if (hasAccount) PreferenceRow("退出登录", icon = "logout_rounded", enabled = !working, onClick = { logout = true },
                trailing = if (working) { { com.green.note.ui.ReviewCircularProgress(Modifier.size(20.dp), strokeWidth = 2.dp) } } else null)
        }
        Spacer(Modifier.height(32.dp)); SectionHeading("偏好与功能"); Spacer(Modifier.height(12.dp))
        SectionCard {
            PreferenceRow("个性化", icon = "palette_outlined", onClick = { onNavigate(SettingsDestination.PERSONALIZATION) })
            PreferenceRow("回复提醒设置", icon = "notifications_active_outlined", onClick = { onNavigate(SettingsDestination.NOTIFICATIONS) })
        }
        Spacer(Modifier.height(32.dp)); SectionHeading("存储与备份"); Spacer(Modifier.height(12.dp))
        SectionCard {
            PreferenceRow("存储设置", icon = "folder_outlined", onClick = { onNavigate(SettingsDestination.STORAGE) })
            PreferenceRow("缓存管理", icon = "cleaning_services_outlined", onClick = { onNavigate(SettingsDestination.CACHE) })
            PreferenceRow("WebDAV备份", icon = "cloud_sync_outlined", onClick = { onNavigate(SettingsDestination.WEBDAV) })
        }
        Spacer(Modifier.height(32.dp)); SectionHeading("关于与支持"); Spacer(Modifier.height(12.dp))
        SectionCard { PreferenceRow("关于 GreenNote", icon = "info_outline_rounded", onClick = { about = true }) }
        Spacer(Modifier.height(4.dp))
    }
    if (about) AboutDialog { about = false }
    if (logout) com.green.note.ui.ReviewAlertDialog(appDialog=true,onDismissRequest = { logout = false }, title = { Text("退出酷安？") },
        text = { Text(if (anonymous) "将退出匿名模式并进入游客状态，本地资料、关注和收藏保留。" else "将清除本机保存的登录凭据。") },
        confirmButton = { com.green.note.ui.ReviewButton(onClick = { logout = false; onLogout() }) { Text("退出") } },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { logout = false }) { Text("取消") } })
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PersonalizationScreen(preferences: AppPreferences, onChange: ((AppPreferences) -> AppPreferences) -> Unit, onBack: () -> Unit, enabled: Boolean = true) {
    ReviewPage("个性化", onBack) {
        AppearanceModes(preferences.themeMode, { value -> onChange { it.copy(themeMode = value) } },
            preferences.pureBlackDark, { value -> onChange { it.copy(pureBlackDark = value) } }, enabled)
        Spacer(Modifier.height(16.dp))
        AppearancePalette(preferences.dynamicColor, { value -> onChange { it.copy(dynamicColor = value) } },
            AppPreferences.themeSeeds.indexOf(preferences.themeSeedArgb), { index -> onChange { it.copy(themeSeedArgb = AppPreferences.themeSeeds[index]) } },
            AppPreferences.themeSeeds, AppPreferences.themeNames, enabled)
        Spacer(Modifier.height(16.dp))
        FontWeightSetting(preferences.useCustomFontWeight, preferences.customFontWeightDelta, "GreenNote", enabled = enabled,
            hapticsEnabled = preferences.haptics, onReset = { onChange { it.copy(useCustomFontWeight = false) } },
            onCommit = { value -> onChange { it.copy(useCustomFontWeight = true, customFontWeightDelta = value) } })
        Spacer(Modifier.height(16.dp))
        FontSizeSetting(preferences.fontScale, enabled = enabled) { value -> onChange { it.copy(fontScale = value) } }

        Spacer(Modifier.height(16.dp))
        AppearanceSection("底部导航") {
            SwitchRow("使用悬浮底栏", preferences.floatingNavBar, { value -> onChange { it.copy(floatingNavBar = value) } }, "居中显示悬浮式导航栏", "dock_rounded", enabled)
        }
        Spacer(Modifier.height(16.dp))
        AppearanceSection("显示效果") {
            SwitchRow("使用液态玻璃效果", preferences.liquidGlassNavBar, { value -> onChange { it.copy(liquidGlassNavBar = value) } },
                "为底栏、悬浮按钮及操作条启用液态玻璃质感", "blur_on_rounded", enabled)
            if (enabled && preferences.liquidGlassNavBar && preferences.floatingNavBar) com.green.note.ui.NavigationGlassChoice(preferences.translucentNavigationGlass, hapticsEnabled = preferences.haptics) { value -> onChange { it.copy(translucentNavigationGlass = value) } }
        }
        Spacer(Modifier.height(16.dp))
        AppearanceSection("触感与震动") {
            SwitchRow("触感与震动反馈", preferences.haptics, { value -> onChange { it.copy(haptics = value) } },
                "按键、卡片点击、手势滑动与底栏切换的触感反馈", "vibration_rounded", enabled)
        }
        Spacer(Modifier.height(24.dp))
    }
}

fun fontWeightLabel(delta: Int): String = when (delta) { -100 -> "偏细"; 100 -> "中等"; 200 -> "偏粗"; 300 -> "加粗"; else -> "默认" }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StorageSettingsScreen(preferences: AppPreferences, nickname: String, onChange: ((AppPreferences) -> AppPreferences) -> Unit, onBack: () -> Unit) {
    var video by remember { mutableStateOf<Boolean?>(null) }
    val name = nickname.trim().ifEmpty { "MyProfile" }
    ReviewPage("存储设置", onBack) {
        SectionCard {
            PreferenceRow("图片存储路径", StoragePaths.summary(preferences.imageSavePathType, name, false), "image_outlined", onClick = { video = false }, titleSize = 16f, subtitleSize = 14f, primaryIcon = true,horizontalPadding=14.dp,minVerticalPadding=4.dp,titleFontWeight=FontWeight.SemiBold)
            PreferenceRow("视频存储路径", StoragePaths.summary(preferences.videoSavePathType, name, true), "video_library_outlined", onClick = { video = true }, titleSize = 16f, subtitleSize = 14f, primaryIcon = true,horizontalPadding=14.dp,minVerticalPadding=4.dp,titleFontWeight=FontWeight.SemiBold)
        }
        Spacer(Modifier.height(14.dp))
    }
    video?.let { isVideo -> com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { video = null }) {
        Column(Modifier.padding(16.dp).navigationBarsPadding()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (isVideo) "视频存储路径" else "图片存储路径", Modifier.weight(1f), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                com.green.note.ui.ReviewIconButton(onClick = { video = null }) { MaterialGlyph("close_rounded", contentDescription = "关闭") }
            }
            Spacer(Modifier.height(6.dp)); Text("保存${if (isVideo) "视频" else "图片"}时，文件将自动归类并存储至相册对应文件夹下。", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            listOf("默认路径", "按本人昵称前缀归类", "按博主昵称前缀归类").forEachIndexed { type, title ->
                ChoiceRow(title, (if (isVideo) preferences.videoSavePathType else preferences.imageSavePathType) == type,
                    { onChange { if (isVideo) it.copy(videoSavePathType = type) else it.copy(imageSavePathType = type) }; video = null }, StoragePaths.summary(type, name, isVideo),horizontalPadding=14.dp,verticalPadding=0.dp,controlSize=48.dp,allowReselect=true,titleFontWeight=FontWeight.SemiBold)
            }
            Spacer(Modifier.height(8.dp))
        }
    } }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AboutDialog(onDismiss: () -> Unit) {
    if(!reviewWindowVisible())return
    val context = LocalContext.current
    val paddingScale=reviewDialogPaddingScale(with(androidx.compose.ui.platform.LocalDensity.current){14.sp.toDp().value/14f})
    val version = remember { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty() }.getOrDefault("") }
    androidx.compose.ui.window.Dialog(onDismissRequest=onDismiss, properties=androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth=false)) {
      ReviewDialogWindow(true)
      Surface(Modifier.padding(horizontal=40.dp,vertical=24.dp).widthIn(min=280.dp),shape=RoundedCornerShape(20.dp),color=MaterialTheme.colorScheme.surfaceContainerHigh) {
       CompositionLocalProvider(LocalTextStyle provides androidx.compose.ui.text.TextStyle(localeList=com.green.note.ui.ReviewTextLocales,fontSize=14.sp,fontWeight=adjustedWeight(400),platformStyle=androidx.compose.ui.text.PlatformTextStyle(includeFontPadding=false)),LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant) {
       Column(Modifier.stopWindowScrollOnPress()) { Column(Modifier.weight(1f,fill=false).verticalScroll(rememberReviewScrollState()).padding(start=(20*paddingScale).dp,top=(24*paddingScale).dp,end=(20*paddingScale).dp,bottom=16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Image(ImageBitmap.imageResource(R.drawable.greennote_icon), null, Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)),
                contentScale = ContentScale.Crop, filterQuality = FilterQuality.Medium)
            Spacer(Modifier.height(14.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("GreenNote", Modifier.align(Alignment.CenterVertically), fontSize = 21.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, letterSpacing = .2.sp)
                Text(if (version.isEmpty()) "版本未知" else "v$version", Modifier.align(Alignment.CenterVertically).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.primaryContainer).padding(horizontal = 8.dp, vertical = 2.5.dp),
                    fontSize = 12.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimaryContainer)
            }
            Spacer(Modifier.height(6.dp)); Text("Material You 风格的简洁内容客户端", textAlign = TextAlign.Center, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(30.dp))
            listOf("palette_outlined" to "Compose 与 Material You 动态主题配色", "dynamic_feed_outlined" to "动态阅读、数码社区与应用管理", "photo_library_outlined" to "自适应九宫格、长图与高清画廊浏览").forEach { (icon, text) ->
                Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.Top) {
                    MaterialGlyph(icon, size = 16.dp, color = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(8.dp))
                    Text(text, Modifier.weight(1f), fontSize = 12.5.sp, lineHeight = 16.875.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(18.dp))
            Surface(onClick = com.green.note.ui.rememberHapticClick { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/Chengeeker/GreenNote"))) }.onFailure { AppToastState().showSnackbar("无法打开仓库地址") } },
                shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .5f), contentColor = LocalContentColor.current,
                border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .4f))) {
                // Flutter Container adds the decoration border's inset to its explicit 12/8 padding.
                Row(Modifier.padding(1.dp).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    MaterialGlyph("code_rounded", size = 20.dp, color = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) { Text("GitHub 开源地址", fontSize = 13.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold); Text("github.com/Chengeeker/GreenNote", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    MaterialGlyph("open_in_new_rounded", size = 16.dp, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        Box(Modifier.fillMaxWidth().padding(start=24.dp,end=24.dp,bottom=24.dp), contentAlignment=Alignment.Center) { com.green.note.ui.ReviewButton(onClick=onDismiss,shape=RoundedCornerShape(12.dp),contentPadding=PaddingValues(horizontal=24.dp,vertical=10.dp)) {Text("我知道了")} }
       }
       }
      }
    }
}
