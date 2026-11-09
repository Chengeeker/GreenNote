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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.rememberHapticClick
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder

internal enum class TodayCardKind { NOTICE, TOPICS, FEATURES, GENERAL }
private fun todayFirst(row:JSONObject,vararg keys:String):String = keys.firstNotNullOfOrNull { key->row.opt(key)?.takeUnless{it===JSONObject.NULL}?.toString() }.orEmpty()
private fun todayPlain(value:String)=value.replace(Regex("<[^>]*>"),"").replace("&amp;","&")
internal fun todayCardTitle(row:JSONObject)=todayFirst(row,"title","subTitle").trim()
internal fun todayCardNotice(row:JSONObject)=todayPlain("${todayCardTitle(row)} ${todayFirst(row,"description","subTitle")}").trim()
internal fun todayFeatureImage(row:JSONObject)=todayFirst(row,"pic","image","cover","coverPic","img","goods_pic","feedPic","feed_pic","logo","icon")
internal fun todayCardKind(row:JSONObject):TodayCardKind {
    val children=cardChildren(row)
    if(todayCardNotice(row).contains("爆料信息不一定准确"))return TodayCardKind.NOTICE
    if(todayPlain(todayCardTitle(row)).contains("今日话题")&&children.isNotEmpty())return TodayCardKind.TOPICS
    val template=todayFirst(row,"entityTemplate","entity_template")
    val grid=template=="imageTextGridCard"||(template in setOf("iconGridCard","iconMiniGridCard","iconLinkGridCard")&&children.any{todayFeatureImage(it).trim().isNotEmpty()})
    return if(grid&&children.isNotEmpty())TodayCardKind.FEATURES else TodayCardKind.GENERAL
}
internal fun todayFeatureColor(row:JSONObject,index:Int):Long {
    val raw=listOf("bgColor","bg_color","backgroundColor","background_color","color").firstNotNullOfOrNull{row.opt(it)?.takeUnless{it===JSONObject.NULL}}
    if(raw is Number){val value=raw.toLong();return (if(value<=0xFFFFFF)value or 0xFF000000L else value) and 0xFFFFFFFFL}
    val value=raw?.toString()?.trim()?.replaceFirst("#","").orEmpty()
    if(value.length==6||value.length==8)value.toLongOrNull(16)?.let{return if(value.length==6)it or 0xFF000000L else it}
    return listOf(0xFF344768L,0xFF496236L,0xFF595959L,0xFF858585L)[index.mod(4)]
}
internal fun todayTopicTag(row:JSONObject):String {
    val url=row.text("url")
    if(url.contains("/t/")) {
        val raw=url.substringAfter("/t/").substringBefore('?').substringBefore('/')
        val tag=runCatching{URLDecoder.decode(raw.replace("+","%2B"),"UTF-8")}.getOrDefault(raw).replace("#","").trim()
        if(tag.isNotEmpty()&&tag.toLongOrNull()==null)return tag
    }
    val query=runCatching{URI(if(url.startsWith('/'))"https://coolapk.com$url" else url).rawQuery}.getOrNull().orEmpty()
    val raw=query.split('&').firstOrNull{it.substringBefore('=')=="tag"}?.substringAfter('=').orEmpty()
    val queryTag=runCatching{URLDecoder.decode(raw,"UTF-8")}.getOrDefault("").replace("#","").trim()
    if(queryTag.isNotEmpty())return queryTag
    return listOf("tag","tagName","title","name").firstNotNullOfOrNull{row.text(it).trim().takeIf{value->value.isNotEmpty()&&value.toLongOrNull()==null}?.replace("#","")?.trim()}.orEmpty()
}
internal fun todayHeadlineTarget(row:JSONObject):JSONObject {
    val copy=JSONObject(row.toString()).put("_composeHeadlineTarget",true)
    val url=row.text("url","href","goods_url","goods_buy_url").trim()
    val title=todayFirst(row,"title","entityTitle","tag","name","text","subTitle").trim()
    if(url.isNotEmpty())copy.put("url",url)
    else if(title.isNotEmpty())copy.put("entityType","topic").put("tag",title.replace("#","").trim()).put("title",title.replace("#","").trim())
    val route=url.removePrefix("#")
    if(row.text("entityType","entity_type").lowercase() in setOf("topic","tag")||row.text("targetType","target_type").lowercase()=="topic"||route.contains("/t/")||route.contains("/topic/")||route.contains("tag=")||route.contains("V9_NEWS_")) {
        val tag=todayTopicTag(JSONObject(row.toString()).put("url",route)).ifEmpty{title.replace("#","").trim()}
        if(tag.isNotEmpty()){copy.remove("url");copy.put("entityType","topic").put("title",tag).put("tag",tag)}
    }
    return copy
}

@Composable
internal fun TodayHeadlineCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,onUser:(String)->Unit,
    onLink:(String)->Unit,onGallery:(List<String>,Int,JSONObject?)->Unit,onLike:(JSONObject)->Unit,onMore:(JSONObject)->Unit) {
    when(todayCardKind(row)) {
        TodayCardKind.NOTICE->Box(Modifier.fillMaxWidth().padding(vertical=4.dp),contentAlignment=Alignment.Center) {
            Text(todayCardNotice(row),Modifier.background(MaterialTheme.colorScheme.surface,RoundedCornerShape(30.dp)).padding(horizontal=18.dp,vertical=12.dp),
                color=MaterialTheme.colorScheme.primary,fontSize=15.5.sp,fontWeight=FontWeight.Medium)
        }
        TodayCardKind.FEATURES->TodayFeatures(api,cardChildren(row),onOpen)
        TodayCardKind.TOPICS->TodayTopics(api,todayCardTitle(row),cardChildren(row),onOpen)
        TodayCardKind.GENERAL-> {
            val fallback=remember(row){JSONObject(row.toString()).put("_composeCardContext","api")}
            EntityRow(api,fallback,onOpen,onUser,onLink,onGallery,onLike,onMore)
        }
    }
}

@Composable
private fun TodayFeatures(api:ContentApi,items:List<JSONObject>,onOpen:(JSONObject)->Unit) {
    Column(Modifier.padding(start=8.dp,top=8.dp,end=8.dp,bottom=4.dp).fillMaxWidth().background(MaterialTheme.colorScheme.surface,RoundedCornerShape(18.dp)).padding(8.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        items.chunked(2).forEachIndexed { rowIndex,pair ->
            Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                pair.forEachIndexed { column,item ->
                    val image=todayFeatureImage(item);val title=todayFirst(item,"title","goods_title","name")
                    Column(Modifier.weight(1f).aspectRatio(1.3f).clip(RoundedCornerShape(14.dp)).background(Color(todayFeatureColor(item,rowIndex*2+column)))
                        .clickable(onClick=rememberHapticClick{onOpen(todayHeadlineTarget(item))})) {
                        Box(Modifier.fillMaxWidth().weight(1f)){if(image.isNotEmpty())CardImage(api,image,Modifier.fillMaxSize(),radius=14.dp,description=title)}
                        Box(Modifier.fillMaxWidth().height(48.dp).padding(horizontal=10.dp),contentAlignment=Alignment.CenterStart) {
                            Text(title,maxLines=2,overflow=TextOverflow.Ellipsis,color=Color.White,fontSize=16.sp,lineHeight=19.2.sp)
                        }
                    }
                }
                if(pair.size==1)Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun TodayTopics(api:ContentApi,title:String,items:List<JSONObject>,onOpen:(JSONObject)->Unit) {
    val scheme=MaterialTheme.colorScheme
    Column(Modifier.padding(horizontal=8.dp,vertical=4.dp).fillMaxWidth().background(scheme.surface,RoundedCornerShape(18.dp)).padding(start=12.dp,top=10.dp,end=12.dp,bottom=12.dp)) {
        Row(verticalAlignment=Alignment.CenterVertically) {
            MaterialGlyph("local_fire_department_rounded",size=22.dp,color=Color(0xFFFF633D));Spacer(Modifier.width(6.dp))
            Text(title.replaceFirst("🔥","").trim().ifEmpty{"今日话题"},Modifier.weight(1f),fontSize=18.sp,fontWeight=FontWeight.SemiBold,color=scheme.onSurface)
            MaterialGlyph("chevron_right_rounded",size=24.dp,color=scheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(6.dp))
        items.take(4).chunked(2).forEachIndexed { index,pair ->
            if(index>0)Spacer(Modifier.height(6.dp))
            Row { pair.forEach { item ->
                val image=item.text("pic","image","cover","logo","icon");val tag=todayTopicTag(item)
                Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable(onClick=rememberHapticClick{onOpen(todayHeadlineTarget(item))}).padding(horizontal=2.dp,vertical=3.dp),verticalAlignment=Alignment.CenterVertically) {
                    Box(Modifier.size(34.dp).clip(RoundedCornerShape(7.dp)),contentAlignment=Alignment.Center) {
                        if(image.isEmpty())Box(Modifier.fillMaxSize().background(scheme.surfaceContainerHighest),contentAlignment=Alignment.Center) {
                            Text(if(tag.isEmpty())"#"else String(Character.toChars(tag.codePointAt(0))),fontWeight=FontWeight.Bold)
                        }else CardImage(api,image,Modifier.fillMaxSize(),radius=7.dp,description=item.text("title","name","tag"))
                    }
                    Spacer(Modifier.width(8.dp));Text(item.text("title","name","tag"),Modifier.weight(1f),maxLines=1,overflow=TextOverflow.Ellipsis,fontSize=14.5.sp,color=scheme.onSurface)
                }
            }}
        }
    }
}
