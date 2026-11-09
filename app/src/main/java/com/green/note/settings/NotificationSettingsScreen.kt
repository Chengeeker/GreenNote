package com.green.note.settings

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.dp
import com.green.note.ui.*

data class ReplyReminderSettings(val enabled: Boolean = false, val resident: Boolean = false, val intervalMinutes: Int = 1, val showPreview: Boolean = false)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationSettingsScreen(settings: ReplyReminderSettings, official: Boolean, permission: Boolean, residentRunning: Boolean,
    status: String, runtimeError: String?, working: Boolean, onSave: (ReplyReminderSettings) -> Unit,
    onCheck: () -> Unit, onSystemSettings: () -> Unit, onReplies: () -> Unit, onBack: () -> Unit,
) {
    var modeMenu by remember { mutableStateOf(false) }
    var intervalMenu by remember { mutableStateOf(false) }
    var modeAnchor by remember{mutableStateOf(IntRect.Zero)}
    var intervalAnchor by remember{mutableStateOf(IntRect.Zero)}
    val anchorFeedback = rememberHapticClick {}
    ReviewPage("回复提醒设置", onBack, topPadding = 16.dp, bottomPadding = 16.dp) {
        Text(if (official) "酷安官方 Cookie 账号的评论与回复提醒" else "请先使用酷安账号登录；匿名账户与 UID 绑定不支持私有回复提醒。")
        Spacer(Modifier.height(16.dp))
        SectionCard {
            SwitchRow("自动检查新回复", settings.enabled, { onSave(settings.copy(enabled = it)) }, "首次开启或切换 Cookie 后不提醒已有消息", enabled = !working && (official || settings.enabled),titleSize=13f,subtitleSize=12f,horizontalPadding=14.dp,verticalPadding=0.dp,disabledTextColor=LocalMaterialGlyphColor.current.copy(alpha=.38f))
            Column(Modifier.padding(16.dp)) {
                ExposedDropdownMenuBox(modeMenu, { if(!working) { anchorFeedback(); modeMenu=it } }) {
                    ReminderDropdownField("后台检查方式",if(settings.resident)"常驻后台检查" else "省电后台检查",!working,modeMenu,true,
                        Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable).onGloballyPositioned{val p=it.positionInWindow();modeAnchor=IntRect(IntOffset(p.x.roundToInt(),p.y.roundToInt()),it.size)})
                    ReviewDropdownMenu(modeMenu,{modeMenu=false},listOf("省电后台检查","常驻后台检查"),if(settings.resident)1 else 0,modeAnchor){modeMenu=false;onSave(settings.copy(resident=it==1))}
                }
                Spacer(Modifier.height(12.dp))
                Text(if (!settings.resident) "后台至少每 15 分钟检查一次，由 Android 调度，省电或断网时可能延迟。" else "显示持续通知并增加耗电。Android 15 及以上限制 dataSync 后台服务累计时长（约 6 小时/24 小时）；停止后转为省电检查，打开应用后重试。")
                Spacer(Modifier.height(16.dp))
                ExposedDropdownMenuBox(intervalMenu, { if(!working) { anchorFeedback(); intervalMenu=it } }) {
                    ReminderDropdownField("检查间隔","${settings.intervalMinutes} 分钟",!working,intervalMenu,false,
                        Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable).onGloballyPositioned{val p=it.positionInWindow();intervalAnchor=IntRect(IntOffset(p.x.roundToInt(),p.y.roundToInt()),it.size)})
                    val intervals=listOf(1,5,15,30,60)
                    ReviewDropdownMenu(intervalMenu,{intervalMenu=false},intervals.map{"$it 分钟"},intervals.indexOf(settings.intervalMinutes).coerceAtLeast(0),intervalAnchor){intervalMenu=false;onSave(settings.copy(intervalMinutes=intervals[it]))}
                }
                Spacer(Modifier.height(8.dp)); Text("应用可见及常驻模式使用所选间隔；省电后台最短 15 分钟。")
            }
            SwitchRow("显示回复内容预览", settings.showPreview, { onSave(settings.copy(showPreview = it)) }, "默认关闭；开启后通知可能显示回复内容", enabled = !working,titleSize=13f,subtitleSize=12f,horizontalPadding=14.dp,verticalPadding=0.dp,disabledTextColor=LocalMaterialGlyphColor.current.copy(alpha=.38f))
        }
        Spacer(Modifier.height(16.dp))
        SectionCard {
            PreferenceRow("系统通知权限", if (permission) "已允许" else "未允许", onClick = onSystemSettings)
            PreferenceRow("运行状态", runtimeError ?: when {
                !settings.enabled -> "已关闭"; !official -> "等待酷安账号登录"; !permission -> "等待通知权限"
                residentRunning -> "常驻服务运行中，省电检查作为后备"; else -> "省电调度已安排；实际执行时间由系统决定"
            }, trailing = {})
            PreferenceRow("检查记录", status, trailing = {})
            PreferenceRow(if (working) "正在处理…" else "立即检查", enabled = official && settings.enabled && !working, onClick = onCheck)
            PreferenceRow("查看评论与回复", enabled = official, onClick = onReplies)
        }
        Spacer(Modifier.height(16.dp)); Text("仅在本机检查回复；不上传 Cookie 或通知内容。强行停止应用后需重新打开，后台及时性取决于系统限制。")
    }
}

/** Flutter's unfilled underline InputDecorator and dense DropdownButton. */
@Composable
private fun ReminderDropdownField(label:String,value:String,enabled:Boolean,focused:Boolean,expanded:Boolean,modifier:Modifier) {
    val scheme=MaterialTheme.colorScheme
    val muted=if(enabled)scheme.onSurfaceVariant else scheme.onSurface.copy(alpha=.38f)
    val labelColor=if(enabled&&focused)scheme.primary else muted
    val dark=scheme.surface.let{it.red+it.green+it.blue<1.5f}
    val iconColor=if(enabled)if(dark)Color.White.copy(alpha=.7f)else Color(0xFF616161)else if(dark)Color.White.copy(alpha=.1f)else Color(0xFFBDBDBD)
    val density=LocalDensity.current
    val buttonHeight=with(density){24.sp.toDp()}.coerceAtLeast(24.dp)
    val labelHeight=with(density){16.sp.toDp()}
    val borderColor=if(!enabled)scheme.onSurface.copy(alpha=.38f)else if(focused)scheme.primary else scheme.onSurfaceVariant
    Column(modifier.drawBehind{val stroke=(if(focused)2.dp else 1.dp).toPx();drawLine(borderColor,Offset(0f,size.height-stroke/2),Offset(size.width,size.height-stroke/2),stroke)}) {
        Column(Modifier.padding(vertical=8.dp)) {
            Box(Modifier.height(labelHeight)){Text(label,fontSize=12.sp,lineHeight=1.5.em,color=labelColor)}
            Row(Modifier.height(buttonHeight),verticalAlignment=Alignment.CenterVertically) {
                Text(value,if(expanded)Modifier.weight(1f)else Modifier,style=MaterialTheme.typography.titleMedium,color=if(enabled)scheme.onSurface else scheme.onSurface.copy(alpha=.38f))
                MaterialGlyph("arrow_drop_down",size=24.dp,color=iconColor)
            }
        }
    }
}

