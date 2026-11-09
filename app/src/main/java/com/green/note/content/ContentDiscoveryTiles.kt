package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.*
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.rememberHapticClick
import org.json.JSONObject

internal fun discoveryImageMetadata(row:JSONObject,url:String):JSONObject=feedPictureMetadata(row,url)
internal fun discoveryPictureRatio(row:JSONObject,url:String):Float {
    val meta=discoveryImageMetadata(row,url);val geo=meta.optJSONObject("geo");val match=Regex("@(\\d+)x(\\d+)").find(url)
    val w=(meta.text("width","w").ifEmpty{geo?.text("width").orEmpty()}.ifEmpty{match?.groupValues?.get(1).orEmpty()}).toFloatOrNull()
    val h=(meta.text("height","h").ifEmpty{geo?.text("height").orEmpty()}.ifEmpty{match?.groupValues?.get(2).orEmpty()}).toFloatOrNull()
    return if(w!=null&&h!=null&&w>0&&h>0&&w.isFinite()&&h.isFinite())(w/h).coerceIn(.35f,2f) else .5f
}

@Composable
internal fun DiscoveryPictureTile(api:ContentApi,row:JSONObject,imageIndex:Int=0,onGallery:(List<String>,Int,JSONObject)->Unit) {
    val urls=feedImages(row).ifEmpty{listOf(row.text("message_cover","cover","pic")).filter{it.isNotEmpty()}}
    val url=urls.getOrNull(imageIndex).orEmpty();var decoded by remember(url){mutableStateOf<Float?>(null)}
    Box(Modifier.padding(bottom=4.dp).fillMaxWidth().aspectRatio(decoded?:discoveryPictureRatio(row,url)).clip(RoundedCornerShape(4.dp)).clickable(enabled=urls.isNotEmpty(),onClick=rememberHapticClick{onGallery(urls,imageIndex,row)})) {
        if(url.isEmpty())MaterialGlyph("broken_image_outlined") else ContentImage(api,url,"查看${row.text("username")}的酷图",Modifier.fillMaxSize(),heroCornerRadius=4.dp,onDecoded={w,h->if(w>0&&h>0)decoded=(w.toFloat()/h).coerceIn(.35f,2f)})
    }
}

@Composable
internal fun DiscoveryWaterfallCard(api:ContentApi,row:JSONObject,secondhand:Boolean,onOpen:(JSONObject)->Unit,onUser:(String)->Unit) {
    val media=remember(row){EntityDetails.objectValue(row.opt("media_info"))}
    val trade=remember(row,secondhand){if(secondhand)secondhandInfo(row)else null}
    val goods=remember(row,secondhand){EntityDetails.objectValue(row.opt(if(secondhand)"ershou_info" else "goods"))}
    val image=media.text("cover").ifEmpty{feedImages(row).firstOrNull().orEmpty()}.ifEmpty{goods.text("cover","product_logo")}
    val dims=Regex("@(\\d+)x(\\d+)").find(image);val w=media.text("width").ifEmpty{dims?.groupValues?.get(1).orEmpty()}.toFloatOrNull();val h=media.text("height").ifEmpty{dims?.groupValues?.get(2).orEmpty()}.toFloatOrNull()
    val ratio=if(secondhand&&w!=null&&h!=null&&w>0&&h>0)(w/h).coerceIn(.65f,1.4f) else .75f
    val user=row.optJSONObject("userInfo")?:JSONObject();val username=row.text("username").ifEmpty{user.text("username")};val avatar=row.text("userAvatar").ifEmpty{user.text("userAvatar")}
    Column(Modifier.padding(bottom=if(secondhand)4.dp else 8.dp).fillMaxWidth().clip(RoundedCornerShape(if(secondhand)5.dp else 12.dp)).background(discoverySurface()).clickable(onClick=rememberHapticClick{onOpen(row)})) {
        Box(Modifier.fillMaxWidth().aspectRatio(ratio)) {
            if(image.isNotEmpty())DiscoveryImage(api,image,null,Modifier.fillMaxSize())
            if(!secondhand&&row.text("media_type")=="2")Box(Modifier.padding(start=8.dp,top=8.dp).size(21.dp).background(Color(0x66000000),RoundedCornerShape(99.dp)),contentAlignment=Alignment.Center){MaterialGlyph("play_arrow_rounded",size=19.dp,color=Color.White)}
        }
        Column(Modifier.padding(start=8.dp,top=10.dp,end=8.dp,bottom=10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (trade?.merchant == true) SecondhandMerchantBadge()
                Text(plainCardText(if(secondhand)trade?.title ?: row.text("message_title","title") else row.text("message")),
                    Modifier.weight(1f), fontSize=if(secondhand)15.sp else 14.sp, lineHeight=if(secondhand)21.sp else 17.5.sp,
                    maxLines=if(secondhand)3 else 2,overflow=TextOverflow.Ellipsis)
            }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(4.dp)) {
                val price=trade?.price ?: goods.text("price")
                if(secondhand) SecondhandPrice(price,20.sp,Modifier.weight(1f))
                else Text(if(price.isEmpty())"" else "¥$price",Modifier.weight(1f),fontSize=17.sp,color=Color(0xFFF44336))
                if(trade?.xianyu == true) XianyuMark()
                Text(if(secondhand)if(trade?.xianyu == true)"闲鱼" else trade?.platform.orEmpty() else "${row.text("replynum").ifEmpty{"0"}}人评论",
                    fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)
            }
            if(secondhand){HorizontalDivider(Modifier.padding(vertical=10.5.dp));Row(verticalAlignment=Alignment.CenterVertically){ContentAvatar(api,avatar,username,30.dp){onUser(row.text("uid").ifEmpty{user.text("uid")})};Spacer(Modifier.width(8.dp));Column(Modifier.weight(1f)){Text(username,fontSize=13.sp,maxLines=1,overflow=TextOverflow.Ellipsis);Text(listOf(relativeTime(row.text("dateline")),trade?.location.orEmpty()).filter(String::isNotEmpty).joinToString("·"),fontSize=11.sp,color=Color.Gray,maxLines=1,overflow=TextOverflow.Ellipsis)}}}
        }
    }
}

@Composable
internal fun DiscoveryGoodsRanking(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val info=row.optJSONObject("goodsListInfo")?:JSONObject();val items=row.optJSONArray("goodsListItem").objects().take(3)
    DiscoverySurface(PaddingValues(12.dp)) {
        Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(row)}),verticalAlignment=Alignment.CenterVertically) {
            Text(row.text("title","message_title"),Modifier.weight(1f),fontSize=18.sp,maxLines=2,overflow=TextOverflow.Ellipsis);Spacer(Modifier.width(6.dp));Text("查看更多",Modifier.background(Color(0xFF009688),RoundedCornerShape(topStart=20.dp,bottomStart=20.dp)).padding(horizontal=10.dp,vertical=4.dp),fontSize=13.sp,color=Color.White)
        }
        Spacer(Modifier.height(12.dp));Row(horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.Top) {
            items.forEachIndexed{index,item->Column(Modifier.weight(1f).clip(RoundedCornerShape(9.dp)).background(MaterialTheme.colorScheme.onSurface.copy(alpha=.07f)).clickable(onClick=rememberHapticClick{onOpen(row)})) {
                Box(Modifier.fillMaxWidth().aspectRatio(1f)){DiscoveryImage(api,item.text("product_goods_cover","pic"),null,Modifier.fillMaxSize());Text("TOP${index+1}",Modifier.background(Color(listOf(0xFFFFECA2,0xFFD0E7F7,0xFFFFDCB7)[index]),RoundedCornerShape(bottomEnd=8.dp)).padding(horizontal=4.dp,vertical=2.dp),fontSize=12.sp,color=Color.White)}
                Column(Modifier.padding(start=8.dp,top=10.dp,end=8.dp,bottom=8.dp)){Text(item.text("product_goods_title","title"),fontSize=13.sp,lineHeight=18.2.sp,maxLines=2,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(8.dp));Text("¥${item.text("price")}",fontSize=13.sp)}
            }}
        }
        Spacer(Modifier.height(10.dp));Row {Text("${info.opt("item_num")?:items.size}个好物 · ${info.opt("vote_num")?:0}人投票",Modifier.weight(1f),fontSize=13.sp);Text(row.text("dateline_text"),fontSize=13.sp)}
    }
}
