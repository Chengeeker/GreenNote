package com.green.note.content

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.DisableSelection
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.ReviewText as Text

/** The app increments revision only after a local device import has finished successfully. */
data class CommentDeviceRecovery(
    val imported: Boolean,
    val onImport: () -> Unit,
    val revision: Long = 0,
    val importing: Boolean = false,
    val preserveOwner: Boolean = false,
)

val LocalCommentDeviceRecovery = staticCompositionLocalOf<CommentDeviceRecovery?> { null }

/** Keep readable rows during this recovery flow; unrelated account changes still replace them. */
internal class CommentListOwner(private var owner: String, private var revision: Long) {
    private var lists = List(4) { ContentListState() }

    fun listsFor(owner: String, revision: Long, importing: Boolean, preserveOwner: Boolean): List<ContentListState> {
        if (!importing || !preserveOwner) {
            val completedImport = preserveOwner && revision > this.revision
            if (this.owner != owner && !completedImport) lists = List(4) { ContentListState() }
            this.owner = owner
            this.revision = revision
        }
        return lists
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CommentRecoveryNotice(
    state: ContentListState,
    hasRows: Boolean,
    onRetry: () -> Unit,
    onVerify: () -> Unit,
    message: String = if (hasRows) "已保留已加载的评论，剩余评论暂不可用" else "暂时无法加载评论",
) {
    val recovery = LocalCommentDeviceRecovery.current
    val captcha = state.captchaRequired
    val canVerify = state.verificationChallenge != null
    val canImport = captcha && recovery != null
    val enabled = !state.busy && recovery?.importing != true
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    DisableSelection {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(message, color = muted, fontSize = 13.sp)
            if (state.pendingReplyCount > 0) Text("还有 ${state.pendingReplyCount} 条评论等待补全",
                color = muted, fontSize = 12.sp)
            if (captcha) {
                if (!canVerify) Text("服务器要求人机验证，但暂未提供可用的验证参数。", color = muted, fontSize = 12.sp)
                if (recovery != null) Text(
                    if (recovery.imported) "已导入本机官方设备标识，也可尝试更新；仍可能需要完成验证。"
                    else "可尝试导入本机官方设备标识，帮助恢复评论读取；仍可能需要完成验证。",
                    color = muted, fontSize = 12.sp,
                )
            }
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (canImport && recovery != null) com.green.note.ui.ReviewOutlinedButton(enabled = enabled, onClick = recovery.onImport) {
                    Text(if (recovery.imported) "更新本机设备标识" else "导入本机设备标识")
                }
                if (canVerify) com.green.note.ui.ReviewTextButton(enabled = enabled, onClick = onVerify) {
                    Text(if (state.verifying) "正在验证" else "完成验证并重试")
                }
                // A challenge has one or two useful recovery actions, not an additional blind retry.
                if (!captcha || !canImport && !canVerify) com.green.note.ui.ReviewTextButton(enabled = enabled, onClick = onRetry) {
                    Text("重试")
                }
            }
        }
    }
}
