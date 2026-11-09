package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.text.Html
import androidx.compose.foundation.*
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.rememberHapticClick
import org.json.JSONObject
import java.util.Locale

@Composable
internal fun DigitalFollowCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val items=cardChildren(row).take(2)
    DigitalReviewCard(home=true) { Column(Modifier.padding(start=12.dp,top=8.dp,end=12.dp,bottom=10.dp)) {
        CardHeading(JSONObject(row.toString()).put("title","我的关注").put("url",row.text("url").ifEmpty{"#/product/followProductList"}),onOpen,true,titleStyle=MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        if(items.isEmpty())Text(row.text("_followError","_emptyText").ifEmpty{if(LocalContentSession.current.authenticated||LocalContentSession.current.anonymous)"还没有关注的机型" else "登录后查看关注的机型"},Modifier.clickable(enabled=row.text("_followError").isNotEmpty(),onClick=rememberHapticClick{onOpen(JSONObject(row.toString()).put("_composeFollowRetry",true))}),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        else Row {items.forEach{item->Row(Modifier.weight(1f).clickable(onClick=rememberHapticClick{onOpen(item)}).padding(vertical=2.dp),verticalAlignment=Alignment.CenterVertically) {
            CardPicture(api,item,Modifier.size(20.dp),radius=6.dp,fallbackSize=20.dp,errorFallback=true);Spacer(Modifier.width(8.dp));Text(cardTitle(item),Modifier.weight(1f,fill=false),fontSize=13.sp,fontWeight=FontWeight.Medium,maxLines=1,overflow=TextOverflow.Ellipsis)
        }}}
    } }
}

@Composable
internal fun DigitalCategoryCard(api:ContentApi,items:List<JSONObject>,onOpen:(JSONObject)->Unit) {
    if(items.isEmpty())return
    DigitalReviewCard(home=true) { Column(Modifier.padding(horizontal=6.dp,vertical=10.dp)) { GridRows(items.take(10),5,gap=8.dp){item,_->
        Column(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(item)}).padding(vertical=4.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            Box(Modifier.size(38.dp).background(MaterialTheme.colorScheme.primaryContainer.copy(alpha=.18f),CircleShape),contentAlignment=Alignment.Center){CardImage(api,listOf("pic","logo","iconUrl").firstNotNullOfOrNull{key->item.opt(key)?.takeUnless{it===JSONObject.NULL}?.toString()}.orEmpty(),Modifier.fillMaxSize(),ContentScale.Fit,100.dp){MaterialGlyph("devices_rounded",size=22.dp,color=MaterialTheme.colorScheme.primary)}}
            Spacer(Modifier.height(4.dp));Text(cardTitle(item),fontSize=12.sp,fontWeight=FontWeight.Medium,maxLines=1,overflow=TextOverflow.Ellipsis)
        }
    };if(items.size<=5)Spacer(Modifier.height(8.dp)) } }
}

@Composable
internal fun DigitalRankCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,home:Boolean) {
    val items=cardChildren(row).take(8);if(items.isEmpty())return
    val ranked=if(home)cardExtra(row).text("withRanking").ifEmpty{row.text("withRanking")}=="1" else true
    val h=if(home)12.dp else 14.dp
    DigitalReviewCard(home) { Column(Modifier.padding(start=h,top=if(home)8.dp else 12.dp,end=h,bottom=if(home)10.dp else 14.dp)) {
        val header=if(!home && row.text("url","moreUrl").isEmpty())JSONObject(row.toString()).put("url","#/product/hotProductList?hotType=day&category_id[]=1001&withConfigCard=1&configCardExtraData=%7B%22withRanking%22%3A1%7D&title=今日热门") else row
        CardHeading(header,onOpen,home,titleStyle=if(home)MaterialTheme.typography.titleMedium else LocalTextStyle.current);Spacer(Modifier.height(if(home)8.dp else 12.dp))
        GridRows(items,4,gap=if(home)8.dp else 12.dp) {item,index->
            val topic=item.text("entityType")=="topic";val scale=LocalDensity.current.fontScale
            Column(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(item)}).padding(horizontal=if(home)4.dp else 2.dp,vertical=2.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                Box(Modifier.fillMaxWidth().height(if(home)50.dp else 60.dp),contentAlignment=Alignment.Center) {
                    CardPicture(api,item,Modifier.size(if(home)48.dp else 50.dp,if(home)48.dp else 54.dp),radius=if(home&&topic)6.dp else 0.dp,fallback=if(home)"smartphone_rounded" else "tablet_android_rounded",fallbackSize=if(home)34.dp else 36.dp,errorFallback=true)
                    if(ranked)Box(Modifier.align(Alignment.TopStart)){RankRibbon(index+1,if(home)(10*scale).dp else 16.dp,if(home)(14*scale).dp else 20.dp)}
                }
                Spacer(Modifier.height(if(home)4.dp else 6.dp))
                Text(cardTitle(item),Modifier.height((if(home)if(topic)16f else 32f else 32f).let{if(home)it*scale else it}.dp),fontSize=12.sp,lineHeight=15.sp,fontWeight=if(home)FontWeight.Medium else FontWeight.Bold,maxLines=if(home&&topic)1 else 2,textAlign=TextAlign.Center,overflow=TextOverflow.Ellipsis)
                Spacer(Modifier.height(if(home)2.dp else 3.dp))
                val hot=digitalHot(item.text("hot_num_txt","hot_num","hotNum","subTitle")).replace("热度","")
                if(hot.isNotEmpty() || !home)Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.Center) {
                    val color=if(home)MaterialTheme.colorScheme.onSurfaceVariant else Color(0xFFFF6D00)
                    MaterialGlyph(if(home)"local_fire_department_rounded" else "local_fire_department",size=if(home)11.dp else 13.dp,color=color)
                    Spacer(Modifier.width(2.dp));Text(hot,fontSize=if(home)10.sp else 11.sp,fontWeight=if(home)FontWeight.Normal else FontWeight.Bold,color=color,maxLines=1,overflow=TextOverflow.Ellipsis)
                } else Spacer(Modifier.height(14.dp))
            }
        }
    } }
}

@Composable
internal fun DigitalTimelineCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val items=cardChildren(row);if(items.isEmpty())return
    DigitalReviewCard(home=true) { Column(Modifier.padding(10.dp)) {
        CardHeading(row,onOpen,true,titleStyle=MaterialTheme.typography.titleMedium);Spacer(Modifier.height(6.dp))
        items.forEach{item->
            val release=item.text("release_time","releaseTime");val date=Regex("^(\\d{4})年(\\d{1,2})月(?:(\\d{1,2})日)?").find(release)?.groupValues
            val label=if(date==null)release else if(date[3].isEmpty())"${date[2]}月" else "${date[2].padStart(2,'0')}.${date[3].padStart(2,'0')}"
            val hot=if(item.text("entityTemplate")=="productTimeline")"" else digitalHot(item.text("hot_num_txt","hot_num"))
            Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(item)}).padding(vertical=6.dp),verticalAlignment=Alignment.CenterVertically) {
                if(release.isNotEmpty()) {
                    Column(Modifier.width(42.dp),horizontalAlignment=Alignment.CenterHorizontally){Text(label,fontSize=12.sp);if(date!=null)Text(date[1],fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                    Box(Modifier.size(10.dp,40.dp),contentAlignment=Alignment.Center){Box(Modifier.width(1.dp).fillMaxHeight().background(MaterialTheme.colorScheme.outlineVariant.copy(alpha=.3f)));Box(Modifier.size(4.dp).background(MaterialTheme.colorScheme.onSurfaceVariant,CircleShape))}
                }
                Spacer(Modifier.width(8.dp));if(cardImage(item).isNotEmpty())CardPicture(api,item,Modifier.size(36.dp),radius=6.dp)
                Spacer(Modifier.width(10.dp));Text(cardTitle(item),Modifier.weight(1f),fontSize=13.sp,fontWeight=FontWeight.Medium,maxLines=1,overflow=TextOverflow.Ellipsis)
                if(hot.isNotEmpty()){Spacer(Modifier.width(6.dp));MaterialGlyph("local_fire_department_rounded",size=13.dp,color=MaterialTheme.colorScheme.onSurfaceVariant);Text(hot,fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            }
        }
    } }
}

@Composable
internal fun DigitalStars(score:Float,size:Dp=14.dp,boxed:Boolean=true,rounded:Boolean=false) {
    val value=(if(rounded)kotlin.math.round(score) else score)/2
    Row { repeat(5){index->
        val icon=if(value>=index+1)"star_rounded" else if(value>index)"star_half_rounded" else "star_outline_rounded"
        if(boxed)Box(Modifier.padding(end=3.dp).size(size).background(if(index<value)Color(0xFFDCA400) else Color(0xFF616161),RoundedCornerShape(2.dp)),contentAlignment=Alignment.Center){MaterialGlyph(if(index>=value)"star_rounded" else icon,size=size,color=Color.White)}
        else MaterialGlyph(icon,size=size,color=Color(0xFFFFB300))
    } }
}

@Composable
internal fun DigitalScore(row:JSONObject) {
    val score=row.text("star_average_score","score").toFloatOrNull() ?: return
    if(!score.isFinite() || score<=0)return
    Column(horizontalAlignment=Alignment.CenterHorizontally){Text(String.format(Locale.ROOT,"%.1f",score),fontSize=24.sp,fontWeight=FontWeight.Bold);DigitalStars(score,10.dp)}
}

@Composable
internal fun DigitalHomeListCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,onUser:(String)->Unit,onLink:(String)->Unit,onGallery:(List<String>,Int,JSONObject?)->Unit,onLike:(JSONObject)->Unit,onMore:(JSONObject)->Unit) {
    val items=cardChildren(row);if(items.isEmpty())return
    DigitalReviewCard(home=true) {
        Box(Modifier.padding(start=12.dp,top=8.dp,end=12.dp,bottom=6.dp)){CardHeading(row,onOpen,true)}
        items.forEach{item->when {
            item.text("feedType")=="rating" -> FeedRow(api,item,onOpen=onOpen,onUser=onUser,onLink=onLink,onGallery=onGallery,onLike=onLike,onMore=onMore,body={DigitalRatingBody(api,item,onOpen,onLink)})
            item.text("entityType")=="feed" -> Row(Modifier.clickable(onClick=rememberHapticClick{onOpen(item)}).padding(horizontal=12.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    val title=Html.fromHtml(item.text("message_title").ifEmpty{item.text("message")},Html.FROM_HTML_MODE_LEGACY).toString().trim().lineSequence().firstOrNull().orEmpty().ifEmpty{cardTitle(item)}
                    Text(title,fontSize=16.sp,lineHeight=22.4.sp,maxLines=2,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(12.dp))
                    Text("${item.text("username")} ${item.text("replynum").ifEmpty{"0"}}评论 ${relativeTime(item.text("dateline"))}",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)
                }
                Spacer(Modifier.width(12.dp));CardImage(api,digitalHomeImage(item),Modifier.size(100.dp,74.dp),ContentScale.Crop,6.dp)
            }
            else -> Row(Modifier.clickable(onClick=rememberHapticClick{onOpen(item)}).padding(12.dp),verticalAlignment=Alignment.CenterVertically) {
                CardImage(api,digitalHomeImage(item),Modifier.size(48.dp),ContentScale.Fit,6.dp);Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)){Text(cardTitle(item),fontSize=14.sp,maxLines=1,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(4.dp));Text("${digitalHot(item.text("hot_num_txt","hot_num"))}热度  ${digitalHot(item.text("feed_comment_num"))}讨论",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}
                Spacer(Modifier.width(6.dp));DigitalScore(item)
            }
        }}
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun DigitalRatingBody(api:ContentApi,item:JSONObject,onOpen:(JSONObject)->Unit,onLink:(String)->Unit) {
    val score=item.text("rating_score").toFloatOrNull()?.takeIf{it.isFinite()}
    val raw=item.opt("v4_rating_message")
    val fields=if(raw is JSONObject)raw else if(raw is String)runCatching{JSONObject(raw)}.getOrDefault(JSONObject()) else JSONObject()
    if(fields.length()==0)listOf("优点" to "comment_good","缺点" to "comment_bad","总结" to "comment_general").forEach{(label,key)->item.text(key).takeIf{it.isNotEmpty()}?.let{fields.put(label,it)}}
    Column {
        if(score!=null)FlowRow(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
            Text("评分",Modifier.align(Alignment.CenterVertically).background(Color(0xFFDCA400)).padding(horizontal=5.dp,vertical=1.dp),fontSize=11.sp,color=Color.White)
            Box(Modifier.align(Alignment.CenterVertically)){DigitalStars(score)};Text(if(score>=9)"😍非常好" else if(score>=7)"😊较好" else if(score>=5)"😐一般" else "较差",Modifier.align(Alignment.CenterVertically),fontSize=12.sp,color=Color(0xFFDCA400))
        }
        val dimensions=item.optJSONArray("rating_item_info").objects()
        if(dimensions.isNotEmpty())FlowRow(Modifier.padding(vertical=6.dp),horizontalArrangement=Arrangement.spacedBy(10.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){dimensions.forEach{d->Text("${d.text("name")} ${String.format(Locale.ROOT,"%.0f",(d.text("v4_score").toDoubleOrNull()?:0.0)/2)}☆",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
        fields.keys().asSequence().forEach{key->Spacer(Modifier.height(6.dp));Text(key,Modifier.background(Color(0xFF009688),RoundedCornerShape(2.dp)).padding(horizontal=6.dp,vertical=1.dp),fontSize=11.sp,color=Color.White);Box(Modifier.padding(vertical=6.dp)){ContentRichText(fields.optString(key).replace("<!--break-->","\n"),maxLines=6,onLink=onLink,lineHeight=22.4.sp)}}
        if(fields.length()==0)Text(item.text("message"),fontSize=16.sp)
        item.optJSONObject("targetRow")?.takeIf{it.length()>0}?.let{target->
            val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
            Row(Modifier.padding(top=8.dp).fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(if(dark)Color(0xFF2C2C2C) else scheme.surfaceContainerHighest).clickable(onClick=rememberHapticClick{onOpen(target)}).padding(12.dp),verticalAlignment=Alignment.CenterVertically) {
                CardImage(api,digitalHomeImage(target),Modifier.size(48.dp),ContentScale.Fit,6.dp);Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){Text(cardTitle(target),fontSize=16.sp);Text("${target.text("star_total_count")}人点评",fontSize=12.sp)};DigitalScore(target)
            }
        }
    }
}
