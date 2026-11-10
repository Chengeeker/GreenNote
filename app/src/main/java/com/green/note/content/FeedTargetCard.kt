package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.net.Uri
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.AppToastState
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

internal fun feedTargetRoute(title:String,url:String,target:JSONObject?):String {
    val type=target?.text("targetType").orEmpty().lowercase();val id=target?.text("id").orEmpty()
    if(url.startsWith("/product/")||type=="product")return "/product/"+id.ifEmpty{url.substringAfter("/product/").substringBefore('?')}
    if(url.startsWith("/dyh/")||type.contains("dyh"))return "/dyh/"+id.ifEmpty{url.substringAfter("/dyh/").substringBefore('?')}
    val path=url.substringAfter("/t/","").substringBefore('?').substringBefore('/')
    val decoded=runCatching{Uri.decode(path).replace("#","").trim()}.getOrDefault("")
    val tag=decoded.takeIf{it.isNotEmpty()&&it.toLongOrNull()==null} ?: title.replace("#","").trim()
    return "/t/${Uri.encode(tag)}"
}

@Composable
internal fun FeedTargetOrTags(api:ContentApi,row:JSONObject,detail:Boolean,onLink:(String)->Unit) {
    val target=row.optJSONObject("targetRow");val title=target?.text("title").orEmpty().ifEmpty{row.text("ttitle")}
    val logo=target?.text("logo").orEmpty().ifEmpty{row.text("tpic")};val url=target?.text("url").orEmpty().ifEmpty{row.text("turl")}
    val product=target?.text("targetType")=="product"||url.contains("/product/")
    val productDiscussion = !detail && row.optBoolean("_composeProductDiscussion")
    if(title.isNotEmpty()) {
        if(detail)FeedDetailTarget(api,row,target,title,logo,url,onLink)
        else FeedTargetPill(api,title,logo,if(product)"devices_rounded"else"tag_rounded",productDiscussion){onLink(feedTargetRoute(title,url,target))}
        return
    }
    val relation=row.optJSONArray("relationRows").objects().firstOrNull{it.text("title").isNotEmpty()}
    if(relation!=null){FeedTargetPill(api,relation.text("title"),relation.text("logo"),"",productDiscussion){onLink(feedTargetRoute(relation.text("title"),relation.text("url"),null))};return}
    if(!detail) {val device=row.text("device_title","device_name");if(device.isNotEmpty() && !productDiscussion)FeedTargetPill(api,device,"","smartphone_rounded",onClick=null);return}
    val tags=linkedSetOf<String>();val raw=row.opt("tags")
    val entries=when(raw){is String->raw.split(',');is JSONArray->(0 until raw.length()).map{raw.optString(it)};else->emptyList()}
    (entries+row.optJSONArray("tagRows").objects().map{it.text("title")}).forEach{val tag=it.replace("#","").trim();if(tag.isNotEmpty()&&!tag.startsWith("http"))tags.add(tag)}
    if(tags.isNotEmpty())FlowRow(Modifier.padding(top=8.dp),horizontalArrangement=Arrangement.spacedBy(6.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
        tags.forEach{tag->Row(Modifier.background(MaterialTheme.colorScheme.primary.copy(alpha=.08f),RoundedCornerShape(12.dp)).clickable{onLink("/t/${Uri.encode(tag)}")}.padding(horizontal=8.dp,vertical=3.dp),verticalAlignment=Alignment.CenterVertically){MaterialGlyph("tag_rounded",size=13.dp,color=MaterialTheme.colorScheme.primary);Spacer(Modifier.width(2.dp));Text(tag,fontSize=12.sp,fontWeight=FontWeight.Medium,color=MaterialTheme.colorScheme.primary)}}
    }
}

@Composable
private fun FeedTargetPill(api:ContentApi,title:String,logo:String,icon:String,productDiscussion:Boolean=false,onClick:(()->Unit)?) {
    val scheme=MaterialTheme.colorScheme
    val accent = if (scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f) Color(0xff53d3c9) else Color(0xff00796b)
    val background = if (productDiscussion) accent.copy(alpha = .18f) else scheme.surfaceContainerHighest.copy(alpha=.5f)
    Row(Modifier.padding(top=if(productDiscussion)12.dp else 8.dp)
        .background(background,RoundedCornerShape(if(productDiscussion)3.dp else 12.dp))
        .then(if(onClick==null)Modifier else Modifier.clickable(onClick=onClick))
        .padding(horizontal=if(productDiscussion)4.dp else 8.dp,vertical=4.dp),verticalAlignment=Alignment.CenterVertically) {
        if(logo.isNotEmpty()){ContentImage(api,logo,null,Modifier.size(16.dp).clip(RoundedCornerShape(4.dp)),heroCornerRadius=4.dp);Spacer(Modifier.width(4.dp))}
        else if(icon.isNotEmpty()){MaterialGlyph(icon,size=13.dp,color=scheme.primary);Spacer(Modifier.width(4.dp))}
        Text(title,fontSize=12.sp,fontWeight=if(productDiscussion)FontWeight.Normal else FontWeight.Medium,color=if(productDiscussion)accent else scheme.onSurfaceVariant)
    }
}

@Composable
private fun FeedDetailTarget(api:ContentApi,row:JSONObject,target:JSONObject?,title:String,logo:String,url:String,onLink:(String)->Unit) {
    val scheme=MaterialTheme.colorScheme;val session=LocalContentSession.current;val login=LocalContentLogin.current;val scope=rememberCoroutineScope();val toast=remember{AppToastState()}
    val preparedTopics=LocalTopicPreparation.current
    val score=(target?.text("star_average_score","score").orEmpty().ifEmpty{row.text("star_average_score","score")}).toDoubleOrNull()?.takeIf{it.isFinite()} ?: 0.0
    val kind=target?.text("productTypeName").orEmpty();val product=target?.text("targetType")=="product"||url.contains("/product/")||score>0||kind.isNotEmpty()
    val productId=target?.text("id").orEmpty().ifEmpty{row.text("product_id")}.ifEmpty{if(url.startsWith("/product/"))url.removePrefix("/product/").substringBefore('?')else""}
    val owner=api.imageCacheScope();val productData=remember(productId,title){JSONObject().put("id",productId).put("title",title)}
    var following by remember(row,owner){mutableStateOf(if(session.anonymous&&product)api.isProductFollowed(productData)else target?.text("isFollow","is_follow")=="1")}
    var busy by remember(owner){mutableStateOf(false)}
    Column(Modifier.padding(top=10.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.surfaceContainerHighest.copy(alpha=.35f)).clickable{onLink(feedTargetRoute(title,url,target))}.padding(12.dp)) {
        Row(verticalAlignment=Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).background(scheme.primaryContainer),contentAlignment=Alignment.Center) {
                if(logo.isNotEmpty())ContentImage(api,logo,null,Modifier.fillMaxSize(),heroCornerRadius=10.dp)
                else MaterialGlyph(if(product)"devices_rounded"else"tag_rounded",size=22.dp,color=scheme.onPrimaryContainer)
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment=Alignment.CenterVertically){Text(if(product)kind.ifEmpty{"数码"}else"话题",Modifier.background(scheme.primary.copy(alpha=.12f),RoundedCornerShape(4.dp)).padding(horizontal=4.dp,vertical=1.5.dp),fontSize=10.sp,fontWeight=FontWeight.Bold,color=scheme.primary);Spacer(Modifier.width(6.dp));Text(title,fontSize=15.sp,fontWeight=FontWeight.Bold,maxLines=1,overflow=TextOverflow.Ellipsis)}
                val sub=target?.text("subTitle").orEmpty();if(sub.isNotEmpty()){Spacer(Modifier.height(3.dp));Text(if(sub.startsWith("🔥"))sub else "🔥 $sub",fontSize=11.5.sp,color=scheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}
            }
            if(product&&score>0){Spacer(Modifier.width(8.dp));Column(horizontalAlignment=Alignment.End){Text(String.format(Locale.ROOT,"%.1f",score),fontSize=19.sp,fontWeight=FontWeight.Bold,lineHeight=20.9.sp,color=scheme.primary);Spacer(Modifier.height(2.dp));Row{repeat(5){i->MaterialGlyph("star_rounded",size=11.dp,color=scheme.primary.copy(alpha=if(score/2>=i+1)1f else if(score/2>i).6f else .25f))}}}}
            else if(!product){Spacer(Modifier.width(8.dp));MaterialGlyph("chevron_right_rounded",size=22.dp,color=scheme.onSurfaceVariant.copy(alpha=.6f))}
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement=Arrangement.spacedBy(10.dp)) {
            TargetActionPill(if(following)"check_rounded"else"add_rounded",if(following)"已关注"else"关注",if(following)scheme.onSurfaceVariant else scheme.primary,if(following)scheme.surfaceContainerHighest.copy(alpha=.3f)else scheme.primary.copy(alpha=.1f),Modifier.weight(1f),enabled=!busy) {
                if(!(session.authenticated||(product&&session.anonymous)))toast.showSnackbar(session.loginRequiredMessage) else {
                    busy=true;scope.launch{try{check(owner==api.imageCacheScope()){"登录账号已改变"};if(product&&productId.isNotEmpty())api.followProduct(productData,following)else api.request(if(following)"/v6/feed/unFollowTag"else"/v6/feed/followTag",query=mapOf("tag" to title.replace("#","").trim()));check(owner==api.imageCacheScope()){"登录账号已改变"};following=!following;if(!product)preparedTopics?.following(title.replace("#","").trim(),following);toast.showSnackbar(if(following)"已关注"else"已取消关注")}catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){toast.showSnackbar(error.message?:"操作失败")}finally{busy=false}}
                }
            }
            TargetActionPill("edit_note_rounded","我也发一条",scheme.onSurface,scheme.surfaceContainerHighest.copy(alpha=.5f),Modifier.weight(1f),iconSize=18) {
                if(!session.authenticated)toast.showSnackbar(session.loginRequiredMessage)else onLink("/feed/writer?tag=${Uri.encode(title.replace("#","").trim())}&productId=${Uri.encode(if(product)productId else "")}")
            }
        }
    }
}

@Composable
private fun TargetActionPill(icon:String,title:String,color:Color,background:Color,modifier:Modifier,enabled:Boolean=true,iconSize:Int=16,onClick:()->Unit) {
    Row(modifier.height(36.dp).background(background,RoundedCornerShape(20.dp)).clickable(enabled=enabled,onClick=onClick).padding(horizontal=12.dp),horizontalArrangement=Arrangement.Center,verticalAlignment=Alignment.CenterVertically) {
        MaterialGlyph(icon,size=iconSize.dp,color=color);Spacer(Modifier.width(4.dp));Text(title,fontSize=13.sp,fontWeight=FontWeight.SemiBold,color=color)
    }
}
