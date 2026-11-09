package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

internal val LocalContentSession = staticCompositionLocalOf { ContentSession() }
internal val LocalContentLogin = staticCompositionLocalOf<() -> Unit> { {} }
internal fun hasVoted(vote: JSONObject): Boolean = listOf("user_vote", "userVote", "is_vote", "isVote", "voted").any { key ->
    when (val value = vote.opt(key)) { is Boolean -> value; is Number -> value.toInt() == 1; is JSONArray -> value.length() > 0; is JSONObject -> value.length() > 0; else -> false }
}
internal fun voteForm(id: String, selected: List<String>, anonymous: Boolean): Map<String, String> {
    require(id.isNotBlank() && selected.isNotEmpty() && selected.all(String::isNotBlank)) { "请选择有效的投票选项" }
    return mapOf("id" to id, "anonymous_status" to if (anonymous) "1" else "0") + selected.mapIndexed { index, value -> "select_option[$index]" to value }
}

@Composable
internal fun FeedPoll(api: ContentApi, feedId: String, initial: JSONObject) {
    var vote by remember(feedId) { mutableStateOf(initial) }
    var selected by remember(feedId) { mutableStateOf(setOf<String>()) }
    var submitted by remember(feedId) { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val session = LocalContentSession.current
    val toast = remember { com.green.note.ui.AppToastState() }
    val scope = rememberCoroutineScope()
    val voted = submitted || hasVoted(vote)
    val end = vote.optLong("end_time")
    var clock by remember(end) { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(end) { if (end > clock) { delay(((end-clock).coerceAtMost(Long.MAX_VALUE/1000))*1000);clock=System.currentTimeMillis()/1000 } }
    val expired = end > 0 && clock >= end
    fun expiredNow() = end > 0 && System.currentTimeMillis() / 1000 >= end
    fun requireLogin(): Boolean { if(session.authenticated)return true;toast.showSnackbar(if(session.anonymous)"当前为匿名登录，无法使用此功能" else "请先登录");return false }
    val maximum = vote.optInt("max_select_num", 1).coerceAtLeast(1)
    fun submit() {
        if (busy || voted || expiredNow()) return
        if (!requireLogin()) return
        if (selected.size < vote.optInt("min_select_num", 1)) { toast.showSnackbar("请选择至少 ${vote.optInt("min_select_num", 1)} 项"); return }
        busy = true
        val owner = api.imageCacheScope()
        scope.launch {
            try {
                val result = api.request("/v6/vote/createUserVote", "POST", body = voteForm(feedId, selected.toList(), vote.optInt("anonymous_status") == 1)).optJSONObject("data")
                check(api.imageCacheScope() == owner) { "账号已变更" }
                val returned = result?.optJSONObject("vote") ?: result
                vote = JSONObject(vote.toString()).apply { returned?.keys()?.forEach { key -> put(key, returned.opt(key)) } }
                submitted = true
                toast.showSnackbar("投票成功")
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { toast.showSnackbar(error.message ?: "投票失败") }
            finally { busy = false }
        }
    }
    fun select(id: String) {
        if (voted || expiredNow() || busy || id.isEmpty()) return
        if (!requireLogin()) return
        selected = when { id in selected -> selected - id; maximum == 1 -> setOf(id); selected.size < maximum -> selected + id; else -> selected }
        if (maximum == 1) submit()
    }
    val options = vote.optJSONArray("options").objects()
    val versus = vote.optInt("type", 1) == 0 && options.size == 2
    @Composable fun Option(row: JSONObject, index: Int, modifier: Modifier = Modifier) {
        val color = if (versus) if (index == 0) Color(0xfff44336) else Color(0xff2196f3) else MaterialTheme.colorScheme.primary
        Row(modifier.heightIn(min = 38.dp).clip(RoundedCornerShape(if (versus) 24.dp else 6.dp))
            .then(if (versus) Modifier.background(color.copy(alpha = .12f)) else Modifier.border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(6.dp)))
            .clickable { select(row.text("id")) }.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            if (!versus) { MaterialGlyph(if (row.text("id") in selected) "check_box" else "check_box_outline_blank", size = 18.dp, color = color); Spacer(Modifier.width(8.dp)) }
            Text(row.text("title"), Modifier.weight(1f), fontSize = 16.sp, textAlign=if(versus)androidx.compose.ui.text.style.TextAlign.Center else androidx.compose.ui.text.style.TextAlign.Start, color = if (versus) color else MaterialTheme.colorScheme.onSurface)
            if ((voted || expired) && row.text("vote_num", "voteNum", "count").isNotEmpty()) Text("${row.text("vote_num", "voteNum", "count")}票", color = color, fontSize = 12.sp)
        }
    }
    Column(Modifier.padding(top = 12.dp)) {
        if (versus) Row(verticalAlignment = Alignment.CenterVertically) {
            Option(options[0], 0, Modifier.weight(1f)); Text("VS", Modifier.padding(horizontal = 12.dp), color = Color(0xff2196f3), fontSize = 24.sp, fontWeight = FontWeight.Black, fontStyle = FontStyle.Italic); Option(options[1], 1, Modifier.weight(1f))
        } else options.forEachIndexed { index, row -> Option(row, index, Modifier.fillMaxWidth().padding(bottom = 8.dp)) }
        if (!versus && !voted && !expired) com.green.note.ui.ReviewTextButton(onClick = ::submit, enabled = !busy, modifier = Modifier.align(Alignment.End)) { Text(if (busy) "正在提交" else "投票（最多 $maximum 项）") }
        Spacer(Modifier.height(12.dp)); Text("${vote.optInt("total_vote_num")}人投票 · ${vote.optInt("total_comment_num")}个观点${if (expired) " · 已结束" else if (voted) " · 已投票" else ""}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
    }
}
