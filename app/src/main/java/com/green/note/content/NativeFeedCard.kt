package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

private val feedCardMargin = 8.dp
private val feedCardInset = 12.dp
internal val feedCardAvatarStart = feedCardMargin + feedCardInset

@Composable
internal fun NativeFeedCard(api:ContentApi,row:JSONObject,detail:Boolean,onOpen:(JSONObject)->Unit,onUser:(String)->Unit,
    onLink:(String)->Unit,onGallery:(List<String>,Int,JSONObject?)->Unit,onLike:(JSONObject)->Unit,onMore:(JSONObject)->Unit,body:(@Composable ()->Unit)?,
    profileCard: Boolean = false, profileAvatarFrame: String = "") {
    val scheme=MaterialTheme.colorScheme
    val user=row.optJSONObject("userInfo") ?: row.optJSONObject("user_info") ?: row
    val username=row.text("username").ifEmpty{user.text("username","title")}.ifEmpty{"酷安用户"}
    val uid=row.text("uid").ifEmpty{user.text("uid")};val avatar=row.text("userAvatar","avatar").ifEmpty{user.text("userAvatar","avatar")}
    val parts=remember(row,detail){if(detail&&(row.optBoolean("_composeArticleHeaderOnly")||row.optBoolean("_composeArticleTailOnly")))listOf(ArticlePart("text"))else if(detail&&!row.optBoolean("_composeArticlePartsExternal"))articleParts(row)else emptyList()}
    val price=remember(row){feedPrice(row)};val article=feedIsArticle(row,detail,parts.isNotEmpty())
    val official=row.optBoolean("_composeOfficialLayout");val headline=row.optBoolean("_composeHeadline")
    val compact=official||row.optBoolean("_composeArticleLayout")||article
    val owner=api.imageCacheScope();val session=LocalContentSession.current;val login=LocalContentLogin.current
    var liked by remember(row,owner){mutableStateOf((row.optJSONObject("userAction")?.opt("like") ?: row.opt("isLike") ?: row.opt("is_like"))?.toString() in setOf("1","true"))}
    var likes by remember(row,owner){mutableIntStateOf(row.optInt("likenum"))};var working by remember(owner){mutableStateOf(false)}
    val scope=rememberCoroutineScope();val toast=remember{AppToastState()}
    val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    val color=if(dark){if(profileCard)darkProfilePanel else if(compact||price!=null)Color(0xFF1E1E1E)else if(LocalAppPreferences.current.pureBlackDark)Color(0xFF121212)else Color(0xFF1B1C20)}else scheme.surfaceContainerLowest
    val profileOnDark = profileCard && dark
    val authorColor = if (profileOnDark) Color(0xFFD2D2D2) else LocalContentColor.current
    val metadataColor = if (profileOnDark) Color(0xFF8E8E8E) else scheme.onSurfaceVariant
    val shape=RoundedCornerShape(if(profileCard)12.dp else if(compact||price!=null)14.dp else 20.dp)
    val open=rememberHapticClick{onOpen(row)}
    val outer=if(detail)Modifier else Modifier.padding(horizontal=feedCardMargin,vertical=4.dp).shadow(if(profileCard||compact||price!=null)0.dp else 1.dp,shape,clip=false).background(color,shape).clickable(onClick=open)
    val pinned = profileCard && row.text("is_top", "istop", "isTop") in setOf("1", "true")
    Column(outer.fillMaxWidth()) {
    if (pinned) {
        val pinColor = Color(0xFFDC5342)
        Row(Modifier.fillMaxWidth().height(32.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(16.dp), contentAlignment = Alignment.BottomCenter) {
                Box(Modifier.align(Alignment.TopCenter).size(9.dp, 1.5.dp).background(pinColor, RoundedCornerShape(50)))
                MaterialGlyph("arrow_upward_rounded", size = 14.dp, color = pinColor)
            }
            Spacer(Modifier.width(4.dp))
            Text("置顶", color = pinColor, fontSize = 12.sp, lineHeight = 16.sp)
        }
        HorizontalDivider(color = scheme.outlineVariant.copy(alpha = .18f))
    }
    Column(Modifier.fillMaxWidth().padding(start=if(detail)14.dp else feedCardInset,end=if(detail)14.dp else feedCardInset,
        top=if(detail)if(row.optBoolean("_composeArticleTailOnly"))0.dp else 6.dp else if(profileCard)12.dp else 10.dp,
        bottom=if(detail)if(row.optBoolean("_composeArticleHeaderOnly"))0.dp else 6.dp else 8.dp)) {
        if(!detail) {
            val discoverySource = row.optJSONObject("_composeDiscoveryArticleSource")
            if (discoverySource != null) DiscoveryArticleAuthor(api, row, discoverySource, onLink) else Row(verticalAlignment=Alignment.CenterVertically) {
                val openAuthor = { if(uid.isNotEmpty()) onUser(uid) }
                if (profileCard) {
                    val frame = user.text("avatarFrame", "avatar_frame", "userAvatarFrame", "user_avatar_frame").ifEmpty { profileAvatarFrame }
                    ProfileAvatar(api, avatar, frame, username, 34.dp, 42.dp, openAuthor)
                } else ContentAvatar(api,avatar,username,if(article||row.optBoolean("_composeArticleLayout"))38.dp else 36.dp, openAuthor)
                Spacer(Modifier.width(if(profileCard)8.dp else 10.dp))
                Column(Modifier.weight(1f)) {
                    Row(Modifier.clickable{if(uid.isNotEmpty())onUser(uid)},verticalAlignment=Alignment.CenterVertically) {
                        FeedHeaderText(username,Modifier.weight(1f,false),LocalTextStyle.current.copy(fontSize=if(profileCard)15.sp else if(price!=null)15.5.sp else 14.5.sp,fontWeight=if(profileCard)FontWeight.Normal else adjustedWeight(600),color=authorColor),!profileCard,maxLines=1,overflow=TextOverflow.Ellipsis)
                        val level=row.text("user_level").ifEmpty{user.text("level")}.ifEmpty{row.text("level")}
                        if(!profileCard && level.isNotEmpty()) {Spacer(Modifier.width(6.dp));Text(if(level.startsWith("Lv.",true))level else "Lv.$level",Modifier.background(scheme.primary.copy(alpha=.12f),RoundedCornerShape(4.dp)).padding(horizontal=4.dp,vertical=1.dp),color=scheme.primary,fontSize=10.sp,fontWeight=FontWeight.SemiBold,lineHeight=11.sp)}
                    }
                    Spacer(Modifier.height(2.dp))
                    Row(verticalAlignment=Alignment.CenterVertically) {
                        FeedHeaderText(relativeTime(row.text("dateline")),style=LocalTextStyle.current.copy(fontSize=11.5.sp,color=metadataColor),correctMetrics=!profileCard)
                        val device=row.text("device_title","device_name")
                        if(device.isNotEmpty())Row(Modifier.padding(start=6.dp).weight(1f,false).clickable{scope.launch{try{val id=FeedDeviceResolver.resolve(api,device);if(id!=null)onLink("/product/$id")else toast.showSnackbar("暂时无法找到“$device”的机型讨论区")}catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){toast.showSnackbar(error.message?:"暂时无法找到“$device”的机型讨论区")}}},verticalAlignment=Alignment.CenterVertically) {
                            MaterialGlyph("smartphone_rounded",size=12.dp,color=metadataColor.copy(alpha=.8f));Spacer(Modifier.width(2.dp));FeedHeaderText(device,style=LocalTextStyle.current.copy(fontSize=11.5.sp,color=metadataColor),correctMetrics=!profileCard,maxLines=1,overflow=TextOverflow.Ellipsis)
                        }
                    }
                }
                val rank=row.optInt("_composeRankNumber")
                if(rank>0){val rankColor=if(rank<=3)Color(0xFFFF5252)else scheme.onSurfaceVariant;Spacer(Modifier.width(8.dp));Row(Modifier.background(if(rank<=3)rankColor.copy(alpha=.15f)else scheme.surfaceContainerHighest.copy(alpha=.6f),RoundedCornerShape(6.dp)).padding(horizontal=7.dp,vertical=3.dp),verticalAlignment=Alignment.CenterVertically){MaterialGlyph("trending_up",size=15.dp,color=rankColor);Spacer(Modifier.width(3.dp));Text(rank.toString().padStart(2,'0'),fontSize=13.sp,fontWeight=FontWeight.Black,fontStyle=FontStyle.Italic,color=rankColor)}}
                Spacer(Modifier.width(4.dp));Box(Modifier.clickable{onMore(row)}.padding(4.dp)){MaterialGlyph("keyboard_arrow_down_rounded",size=20.dp,color=scheme.onSurfaceVariant.copy(alpha=.7f),contentDescription="更多操作")}
            }
            Spacer(Modifier.height(8.dp))
        }
        if(body!=null)body() else FeedCardBody(api,row,username,detail,article,compact,official,headline,price,parts,onOpen,onLink,onGallery, profileCard)
        if(headline&&!detail)FeedQuickReply(api,row,username)
        if(detail&&!row.optBoolean("_composeArticleHeaderOnly")) {
            val ip=row.text("ip_location");val time=relativeTime(row.text("last_change_time","last_change_date"))
            val views=row.text("view_num","viewnum").takeIf{session.authenticated&&uid==session.uid}.orEmpty()
            val info=listOf(time.takeIf{it.isNotEmpty()}?.let{"编辑于 $it"}.orEmpty(),if(ip.isEmpty()||ip.startsWith("发布于"))ip else "发布于$ip",if(views.isEmpty())"" else "${views}浏览").filter(String::isNotEmpty).joinToString(" · ")
            if(info.isNotEmpty()){Spacer(Modifier.height(8.dp));Text(info,fontSize=12.sp,color=scheme.onSurfaceVariant.copy(alpha=.75f))}
        } else if(!detail&&!(official&&row.optJSONObject("vote")!=null)) {
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceAround) {
                FeedCardAction(if(liked)"thumb_up_rounded"else"thumb_up_outlined",likes,if(liked)"取消赞"else"赞",if(liked)scheme.primary else scheme.onSurfaceVariant,!working) {
                    if(session.anonymous)toast.showSnackbar(session.loginRequiredMessage) else {
                        working=true;scope.launch {
                            try {
                                check(owner==api.imageCacheScope()){"登录账号已改变"}
                                api.request(if(liked)"/v6/feed/unlike"else"/v6/feed/like","POST",query=mapOf("id" to row.text("id")))
                                check(owner==api.imageCacheScope()){"登录账号已改变"};likes=(likes+if(liked)-1 else 1).coerceAtLeast(0);liked=!liked
                            }catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){toast.showSnackbar(error.message?:"操作失败")}finally{working=false}
                        }
                    }
                }
                FeedCardAction("chat_bubble_outline_rounded",row.optInt("replynum"),"评论",scheme.onSurfaceVariant,!working){onOpen(row)}
                FeedCardAction("share_outlined",row.optInt("forwardnum")+if(compact)row.optInt("share_num")else 0,"分享",scheme.onSurfaceVariant,!working){onMore(row)}
            }
        }
    }
    }
}

@Composable
private fun FeedHeaderText(value:String,modifier:Modifier=Modifier,style:TextStyle,correctMetrics:Boolean,
    maxLines:Int=Int.MAX_VALUE,overflow:TextOverflow=TextOverflow.Clip) {
    if(correctMetrics) {
        // These are static labels; author/device click handling belongs to their existing parent Row.
        val metrics=rememberFlutterArticleStyle(AnnotatedString(value),style,plainTitle=true)
        Text(value,modifier.then(metrics.modifier),style=metrics.style,onTextLayout=metrics.onTextLayout,maxLines=maxLines,overflow=overflow)
    } else Text(value,modifier,style=style,maxLines=maxLines,overflow=overflow)
}

@Composable
private fun FeedCardAction(icon:String,count:Int,label:String,color:Color,enabled:Boolean,onClick:()->Unit) {
    Row(Modifier.clickable(enabled=enabled,onClick=onClick).padding(horizontal=10.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically) {
        MaterialGlyph(icon,size=18.dp,color=color,contentDescription=label)
        val value=feedCount(count);if(value.isNotEmpty()){Spacer(Modifier.width(4.dp));Text(value,fontSize=12.sp,fontWeight=FontWeight.Medium,color=color)}
    }
}
