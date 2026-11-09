package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.ReviewOutlinedTextField as OutlinedTextField

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.AppToastState
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FeedQuickReply(api:ContentApi,row:JSONObject,username:String) {
    val scheme=MaterialTheme.colorScheme;val session=LocalContentSession.current;val login=LocalContentLogin.current
    val owner=api.imageCacheScope();var editor by remember(row,owner){mutableStateOf(false)};var text by remember(row,owner){mutableStateOf("")};var sending by remember(owner){mutableStateOf(false)}
    val scope=rememberCoroutineScope();val toast=remember{AppToastState()}
    Row(Modifier.padding(top=4.dp,bottom=2.dp).fillMaxWidth().height(28.dp).background(scheme.surfaceContainerHighest.copy(alpha=.45f),RoundedCornerShape(14.dp)).clickable{if(!session.authenticated)toast.showSnackbar(session.loginRequiredMessage)else editor=true}.padding(horizontal=10.dp),verticalAlignment=Alignment.CenterVertically) {
        ContentAvatar(api,session.avatar,"",18.dp){if(!session.authenticated)toast.showSnackbar(session.loginRequiredMessage)else editor=true};Spacer(Modifier.width(8.dp));Text("说点儿什么吧",fontSize=11.5.sp,color=scheme.onSurfaceVariant.copy(alpha=.75f))
    }
    if(editor)com.green.note.ui.ReviewModalBottomSheet(onDismissRequest={if(!sending)editor=false},shape=RoundedCornerShape(topStart=20.dp,topEnd=20.dp),containerColor=scheme.surface) {
        val focus=remember{FocusRequester()};LaunchedEffect(Unit){focus.requestFocus()}
        Column(Modifier.fillMaxWidth().imePadding().padding(16.dp)) {
            Row(verticalAlignment=Alignment.CenterVertically){Text("回复 @$username",Modifier.weight(1f),fontSize=15.sp,fontWeight=FontWeight.Bold);com.green.note.ui.ReviewIconButton(onClick={editor=false},enabled=!sending){MaterialGlyph("close")}}
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(text,{text=it},Modifier.fillMaxWidth().focusRequester(focus),textStyle=MaterialTheme.typography.bodyLarge,placeholder={Text("说点儿什么吧…")},minLines=2,maxLines=4,shape=RoundedCornerShape(12.dp),colors=OutlinedTextFieldDefaults.colors(unfocusedContainerColor=scheme.surfaceContainerHighest.copy(alpha=.3f),focusedContainerColor=scheme.surfaceContainerHighest.copy(alpha=.3f)),enabled=!sending)
            Spacer(Modifier.height(12.dp))
            com.green.note.ui.ReviewButton(onClick={
                val message=text.trim();if(message.isNotEmpty()&&!sending){sending=true;scope.launch {
                    try{check(owner==api.imageCacheScope()){"登录账号已改变"};api.request("/v6/feed/reply","POST",body=mapOf("id" to row.text("id"),"type" to "feed","message" to message));check(owner==api.imageCacheScope()){"登录账号已改变"};text="";editor=false;toast.showSnackbar("回复发送成功")}
                    catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){toast.showSnackbar("回复失败: ${error.message}")}finally{sending=false}
                }}
            },Modifier.align(Alignment.End),enabled=!sending){MaterialGlyph("send",size=16.dp);Spacer(Modifier.width(8.dp));Text("发送")}
        }
    }
}
