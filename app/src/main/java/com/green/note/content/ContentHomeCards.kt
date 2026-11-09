package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.*
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.rememberHapticClick
import com.green.note.ui.AppToastState
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

internal fun homeCalendarTime(raw:String):String = Regex("\\d{4}年(\\d+)月(\\d+)日(\\d+:\\d+)").find(raw)?.let{"${it.groupValues[1]}.${it.groupValues[2]}\n${it.groupValues[3]}"} ?: raw
internal fun configuredCardRatio(row:JSONObject,default:Float=4.5f):Float {
    val dims=cardExtra(row).text("dimensionRatio").split(':');val w=dims.getOrNull(0)?.toFloatOrNull();val h=dims.getOrNull(1)?.toFloatOrNull()
    return if(w!=null&&h!=null&&w.isFinite()&&h.isFinite()&&w>0&&h>0)w/h else default
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun HomeOfflineActivity(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    BoxWithConstraints(Modifier.padding(horizontal=8.dp,vertical=4.dp).fillMaxWidth().background(if(dark)Color(0xFF1E1E1E) else scheme.surface,RoundedCornerShape(14.dp)).clickable(onClick=rememberHapticClick{onOpen(row)}).padding(horizontal=16.dp,vertical=12.dp)) {
        val imageSize=(maxWidth.value*.335f).coerceIn(72f,104f).dp
        Row(verticalAlignment=Alignment.Top){CardImage(api,row.text("goods_pic"),Modifier.size(imageSize),radius=8.dp);Spacer(Modifier.width(8.dp));Column(Modifier.weight(1f)) {
            Text(row.text("goods_title"),fontSize=16.sp,lineHeight=23.2.sp,maxLines=2,overflow=TextOverflow.Ellipsis)
            Spacer(Modifier.height(6.dp));LazyRow(Modifier.height(20.dp),horizontalArrangement=Arrangement.spacedBy(5.dp)){items(row.text("goods_tags").split(Regex("[,，]")).filter{it.trim().isNotEmpty()}.withIndex().toList()){entry->
                Box(Modifier.fillMaxHeight().background(Color(0xFFDD4436).copy(alpha=if(entry.index==0).05f else .02f),RoundedCornerShape(3.dp)).padding(horizontal=5.dp),contentAlignment=Alignment.Center){Text(entry.value,fontSize=11.sp,color=if(entry.index==0)Color(0xFFD94436) else scheme.onSurfaceVariant)}
            }}
            Spacer(Modifier.height(6.dp));FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){Text(row.text("goods_promo_title"),fontSize=14.sp,color=Color(0xFFDD4436));com.green.note.ui.ReviewButton(onClick=rememberHapticClick{onOpen(row)},modifier=Modifier.height(28.dp),contentPadding=PaddingValues(horizontal=16.dp),colors=ButtonDefaults.buttonColors(containerColor=Color(0xFFDD4436),contentColor=Color.White)){Text(row.text("goods_buy_text").ifEmpty{"查看详情"},fontSize=13.sp)}}
        }}
    }
}

@Composable
internal fun HomeUserRanking(api:ContentApi,row:JSONObject,onUser:(String)->Unit) {
    val rank=row.optInt("_composeRowRank",1);val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    var following by remember(row){mutableStateOf(api.isUserFollowed(row))};var busy by remember{mutableStateOf(false)}
    val session=LocalContentSession.current;val scope=rememberCoroutineScope();val owner=remember{api.imageCacheScope()}
    Row(Modifier.padding(horizontal=8.dp).fillMaxWidth().background(if(dark)Color(0xFF1E1E1E) else scheme.surface,if(rank==1)RoundedCornerShape(topStart=14.dp,topEnd=14.dp) else RoundedCornerShape(0.dp)).padding(horizontal=20.dp,vertical=12.dp),verticalAlignment=Alignment.CenterVertically) {
        Box(Modifier.size(18.dp).background(if(rank<=3)listOf(Color(0xFFF44336),Color(0xFFFF9800),Color(0xFFFFC107))[(rank-1).coerceAtLeast(0)] else Color.Transparent,RoundedCornerShape(4.dp)),contentAlignment=Alignment.Center){Text("$rank",fontSize=12.sp,color=if(rank<=3)Color.White else scheme.onSurface)}
        Spacer(Modifier.width(12.dp));ContentAvatar(api,row.text("userAvatar"),row.text("username"),40.dp){onUser(row.text("uid"))};Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f).clickable(onClick=rememberHapticClick{onUser(row.text("uid"))})){Text(row.text("username"),fontSize=16.sp,maxLines=1,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(6.dp));Text("${row.text("follow")}关注  ${row.text("fans")}粉丝",fontSize=12.sp,color=scheme.onSurfaceVariant)}
        Spacer(Modifier.width(8.dp));com.green.note.ui.ReviewOutlinedButton(enabled=!busy,onClick={
            if(!session.authenticated&&!session.anonymous)AppToastState().showSnackbar("请先使用酷安账号登录") else {busy=true;scope.launch{try{check(owner==api.imageCacheScope()){ "账号已切换" };following=api.followUser(row,following)}catch(cancelled:CancellationException){throw cancelled}catch(failure:Exception){AppToastState().showSnackbar(failure.message?:"操作失败")}finally{busy=false}}}
        },modifier=Modifier.height(30.dp),contentPadding=PaddingValues(horizontal=16.dp),border=BorderStroke(1.dp,Color(0xFF009688)),colors=ButtonDefaults.outlinedButtonColors(contentColor=Color(0xFF009688))){Text(if(following)"已关注" else "关注",fontSize=12.sp)}
    }
}
internal fun plainCardText(raw:String)=org.jsoup.Jsoup.parseBodyFragment(raw).text()

@Composable
internal fun HomeTemplateCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,onLink:(String)->Unit,fallback:@Composable ()->Unit) {
    val template=cardTemplate(row);val children=cardChildren(row);val scheme=MaterialTheme.colorScheme
    val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    when {
        template=="messagecard"->Box(Modifier.padding(8.dp).fillMaxWidth().background(if(dark)Color(0xFF192D29) else Color(0xFFE7F4EF),RoundedCornerShape(12.dp)).padding(12.dp)){ContentRichText(plainCardText(row.text("description")),onLink=onLink,fontSize=14.sp,lineHeight=17.5.sp)}
        template=="producttimelinelistcard"->Column {
            HomeCardHeading(row,onOpen)
            children.forEach{item->Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(item)}).padding(start=32.dp,top=10.dp,end=36.dp,bottom=10.dp),verticalAlignment=Alignment.CenterVertically){
                Text(homeCalendarTime(item.text("release_time")),Modifier.width(48.dp),fontSize=14.sp,lineHeight=21.sp,textAlign=TextAlign.Center)
                Box(Modifier.padding(horizontal=12.dp).size(8.dp).background(Color(0xFF353535),RoundedCornerShape(4.dp)))
                CardPicture(api,item,Modifier.size(36.dp),radius=9.dp);Spacer(Modifier.width(8.dp));Text(plainCardText(cardTitle(item)),Modifier.weight(1f),fontSize=14.sp,maxLines=2,overflow=TextOverflow.Ellipsis);Spacer(Modifier.width(8.dp));MaterialGlyph("local_fire_department_outlined",size=16.dp,color=Color.Gray);Text(item.text("hot_num_txt","hot_num"),fontSize=13.sp)
            }}
            Spacer(Modifier.height(18.dp))
        }
        template=="iconbuttongridcard"->Row(Modifier.padding(horizontal=8.dp,vertical=4.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)){children.forEach{item->HomeBanner(api,item,onOpen,Modifier.weight(1f),2.44f,false)}}
        template=="imagetextscrollcard"->Column {
            HomeCardHeading(row,onOpen);LazyRow(Modifier.height(156.dp),contentPadding=PaddingValues(horizontal=8.dp),horizontalArrangement=Arrangement.spacedBy(10.dp)){items(children){HomeBanner(api,it,onOpen,Modifier.width(216.dp),2.22f)}};Spacer(Modifier.height(12.dp))
        }
        template=="imagetextgridcard" || row.text("entityType")=="imageText"->Column(Modifier.padding(horizontal=8.dp,vertical=4.dp).background(if(dark)Color(0xFF1E1E1E) else scheme.surface,RoundedCornerShape(14.dp)).padding(8.dp)){children.ifEmpty{listOf(row)}.forEach{HomeBanner(api,it,onOpen,Modifier.fillMaxWidth(),2.22f)}}
        template=="imagecarouselcard_1" && row.text("_composeHomeDestination")=="activities"->Column(Modifier.padding(start=8.dp,top=16.dp,end=8.dp,bottom=4.dp)){Text(plainCardText(cardTitle(row)),Modifier.padding(horizontal=12.dp),fontSize=17.sp,fontWeight=FontWeight.Medium);Spacer(Modifier.height(2.dp));children.forEach{HomeBanner(api,it,onOpen,Modifier.fillMaxWidth(),configuredCardRatio(row),false)}}
        else->fallback()
    }
}

@Composable
private fun HomeCardHeading(row:JSONObject,onOpen:(JSONObject)->Unit) {Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(row)}).padding(start=20.dp,top=16.dp,end=20.dp,bottom=12.dp),verticalAlignment=Alignment.CenterVertically){Text(plainCardText(cardTitle(row)),Modifier.weight(1f),fontSize=16.sp,fontWeight=FontWeight.Medium);MaterialGlyph("chevron_right_rounded",color=Color.Gray)}}

@Composable
private fun HomeBanner(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,modifier:Modifier,ratio:Float,caption:Boolean=true) {
    Column(modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick=rememberHapticClick{onOpen(row)})) {
        val picture=cardImage(row)
        Box(Modifier.fillMaxWidth().aspectRatio(ratio)){if(picture.isNotEmpty())ContentImage(api,picture,null,Modifier.fillMaxSize())}
        if(caption){val raw=row.text("picColor","backgroundColor","color").removePrefix("#").toLongOrNull(16);val color=if(raw==null)Color(0xFF434A60) else Color((0xFF000000L or raw).toInt())
            Text(plainCardText(cardTitle(row)),Modifier.fillMaxWidth().background(color).padding(horizontal=12.dp,vertical=4.dp),fontSize=16.sp,lineHeight=19.2.sp,fontWeight=FontWeight.Medium,color=Color.White,maxLines=2,overflow=TextOverflow.Ellipsis)
        }
    }
}
