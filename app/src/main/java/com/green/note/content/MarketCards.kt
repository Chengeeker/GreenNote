package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.green.note.ui.MaterialGlyph
import org.json.JSONObject

internal fun marketCardTarget(row:JSONObject):JSONObject {
    val copy=JSONObject(row.toString());val route=row.text("url","apkUrl");val type=row.text("entityType")
    val packageName=row.text("apkname","packageName")
    when {
        type=="apk"||packageName.isNotEmpty()||Regex("^/(apk|game)/[^/?]+\\.[^/?]+$").matches(route)->copy.put("entityType","apk").put("id",packageName.ifEmpty{route.substringAfterLast('/').ifEmpty{row.text("id")}})
        type=="album"||Regex("^/album/\\d+$").matches(route)->copy.put("entityType","album").put("id",row.text("id","entityId").ifEmpty{route.substringAfterLast('/')})
        route.startsWith("/apk/")||route.startsWith("/album/")||route.startsWith('#')||route.startsWith("/page?")||route.startsWith("/v6/")->copy.put("_composeMarketList",true).put("url",route)
    }
    return copy
}
internal fun marketImageRatio(row:JSONObject):Float {
    val values=cardExtra(row).text("dimensionRatio").split(':');if(values.size!=2)return 16f/9f
    val width=values[0].toFloatOrNull() ?: return 16f/9f;val height=values[1].toFloatOrNull() ?: return 16f/9f
    return if(width.isFinite()&&height.isFinite()&&width>0&&height>0)(width/height).takeIf{it.isFinite()&&it>0} ?: (16f/9f)else 16f/9f
}
internal fun marketVideo(row:JSONObject):JSONObject {
    val extra=cardExtra(row);val source=row.opt("videoParams") ?: extra.opt("videoParams")
    return when(source){is JSONObject->JSONObject(source.toString());is String->runCatching{JSONObject(source)}.getOrDefault(JSONObject());else->JSONObject()}
}
internal fun marketDuration(value:String):String {
    val seconds=((value.toLongOrNull() ?: 0)/1000).coerceAtLeast(0)
    return listOf(seconds/3600,seconds/60%60,seconds%60).joinToString(":"){it.toString().padStart(2,'0')}
}

@Composable
internal fun MarketCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,onUser:(String)->Unit,onLink:(String)->Unit,
    onGallery:(List<String>,Int,JSONObject?)->Unit,onLike:(JSONObject)->Unit,onMore:(JSONObject)->Unit) {
    val template=row.text("entityTemplate");val children=cardChildren(row)
    val open:(JSONObject)->Unit={onOpen(marketCardTarget(it))}
    when(template) {
        "configCard","noMoreDataCard"->return
        "linkCard","iconButtonGridCard"->{Row(Modifier.padding(start=8.dp,end=8.dp,bottom=2.dp)) {children.forEach{item->com.green.note.ui.ReviewButton(onClick={open(item)},modifier=Modifier.weight(1f).padding(horizontal=3.dp).heightIn(min=32.dp),contentPadding=PaddingValues(horizontal=2.dp),colors=ButtonDefaults.buttonColors(containerColor=Color(0xFF009688),contentColor=Color.White)){Text(item.text("title"),fontSize=14.sp)}}};return}
        "titleCard"->{MarketHeading(row,open);return}
        "imageScaleCard"->{Box(Modifier.padding(start=8.dp,end=8.dp,bottom=8.dp).fillMaxWidth().aspectRatio(marketImageRatio(row)).clip(RoundedCornerShape(14.dp)).clickable{open(row)}){MarketImage(api,row.text("pic","cover"),Modifier.fillMaxSize())};return}
    }
    if(children.isEmpty()) {
        if(row.text("entityType")=="category")Row(Modifier.fillMaxWidth().clickable{open(row)}.padding(horizontal=14.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
            MarketImage(api,row.text("logo"),Modifier.size(48.dp),48.dp);Spacer(Modifier.width(16.dp));Column(Modifier.weight(1f)){Text(row.text("title"),fontWeight=FontWeight.SemiBold);Text(row.text("keywords"),fontSize=14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)};MaterialGlyph("chevron_right")
        }else MarketAppRow(api,row,open)
        return
    }
    val dark=MaterialTheme.colorScheme.surface.let{it.red+it.green+it.blue<1.5f}
    Column(Modifier.padding(start=8.dp,end=8.dp,bottom=8.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(if(dark)Color(0xFF1E1E1E)else MaterialTheme.colorScheme.surface)) {
        MarketHeading(row,open)
        when {
            template=="apkImageCard"->children.forEach{MarketHero(api,it,open)}
            template.contains("Scroll")||template=="colorfulScrollCard"->{
                val wide=template.contains("Image")||template=="imageScrollCard";val scale=LocalDensity.current.fontScale
                LazyRow(Modifier.height(((if(wide)190f else 148f)+(scale-1)*40).dp),contentPadding=PaddingValues(12.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                    itemsIndexed(children){_,item->Column(Modifier.width(if(wide)240.dp else 72.dp).clickable{open(item)},horizontalAlignment=Alignment.CenterHorizontally) {
                        if(wide)MarketImage(api,item.text("cover","pic","logo"),Modifier.fillMaxWidth().aspectRatio(16f/9f))else MarketImage(api,item.text("logo","icon","pic"),Modifier.size(56.dp),56.dp)
                        Spacer(Modifier.height(8.dp));Text(item.text("title"),maxLines=1,overflow=TextOverflow.Ellipsis)
                        if(!wide)Text(item.text("apksize","score"),fontSize=11.sp,color=Color.Gray,maxLines=1)
                    }}
                }
            }
            template=="iconGridCard"||template=="gridCard"->children.chunked(4).forEach{group->Row {group.forEach{item->Column(Modifier.weight(1f).clickable{open(item)}.padding(10.dp),horizontalAlignment=Alignment.CenterHorizontally){MarketImage(api,item.text("logo","pic"),Modifier.size(48.dp),48.dp);Spacer(Modifier.height(6.dp));Text(item.text("title"),maxLines=1,overflow=TextOverflow.Ellipsis)}};repeat(4-group.size){Spacer(Modifier.weight(1f))}}}
            else->children.forEach{MarketAppRow(api,it,open)}
        }
    }
}

@Composable
private fun MarketHeading(row:JSONObject,onOpen:(JSONObject)->Unit) {
    val title=row.text("title");if(title.isEmpty())return
    val enabled=row.text("url").isNotEmpty()
    Row(Modifier.fillMaxWidth().clickable(enabled=enabled){onOpen(row)}.padding(start=12.dp,top=12.dp,end=12.dp,bottom=4.dp),verticalAlignment=Alignment.CenterVertically){Text(title,Modifier.weight(1f),fontSize=17.sp,fontWeight=FontWeight.SemiBold);if(enabled)MaterialGlyph("chevron_right",color=Color.Gray)}
}

@Composable
private fun MarketAppRow(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,subtitle:String?=null) {
    val apk=row.text("entityType")=="apk"||row.text("apkname","packageName").isNotEmpty()
    val description=plainCardText(row.text("description","note","related_text"))
    val counts="${row.text("downCount","downnum")}下载  ${row.text("commentnum","commentCount")}评论"
    Row(Modifier.fillMaxWidth().clickable{onOpen(row)}.padding(horizontal=12.dp,vertical=10.dp),verticalAlignment=Alignment.CenterVertically) {
        MarketImage(api,row.text("logo","icon","pic"),Modifier.size(56.dp),56.dp);Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)){Text(row.text("cardTitle","title","name"),fontSize=17.sp,fontWeight=FontWeight.Normal,maxLines=1,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(5.dp));Text(subtitle?:if(apk)counts else description,fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=2,overflow=TextOverflow.Ellipsis)}
        Spacer(Modifier.width(8.dp));if(apk)NativeAppDownload(api,row,compact=true)else MaterialGlyph("chevron_right")
    }
}

@Composable
private fun MarketHero(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val combined=remember(row){JSONObject(row.toString()).apply{val extra=cardExtra(row);extra.keys().forEach{put(it,extra.opt(it))}}}
    val cover=combined.text("cover","pic");val video=remember(row){marketVideo(row)};val params=video.text("requestParams");val url=video.text("url","videoUrl")
    val play=LocalContentVideo.current;val canPlay=params.isNotEmpty()||url.isNotEmpty()
    Column {
        Box(Modifier.fillMaxWidth().aspectRatio(16f/9f).clickable{if(canPlay)play(JSONObject().put("url",url).put("requestParams",params).put("cover",cover).put("title",row.text("title")))else onOpen(row)}) {
            MarketImage(api,cover,Modifier.fillMaxSize());if(canPlay)MaterialGlyph("play_arrow_rounded",Modifier.align(Alignment.Center),48.dp,Color.White)
            if(canPlay&&(video.text("duration").toLongOrNull()?:0)>0)Text(marketDuration(video.text("duration")),Modifier.align(Alignment.BottomEnd).padding(end=16.dp,bottom=12.dp),fontSize=13.sp,color=Color.White)
        }
        MarketAppRow(api,row,onOpen,combined.text("subTitle","description"))
    }
}

@Composable
private fun MarketImage(api:ContentApi,url:String,modifier:Modifier,size:Dp?=null) {
    CardImage(api,url,modifier,ContentScale.Crop,if(size==null)0.dp else 13.dp){MaterialGlyph("apps")}
}
