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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.AppToastState
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.rememberHapticClick
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
internal fun discoverySurface():Color {val s=MaterialTheme.colorScheme;return if(s.surface.red+s.surface.green+s.surface.blue<1.5f)Color(0xFF1E1E1E) else s.surfaceContainerLow}
@Composable
internal fun DiscoverySurface(padding:PaddingValues=PaddingValues(horizontal=12.dp,vertical=8.dp),shape:RoundedCornerShape=RoundedCornerShape(12.dp),color:Color=discoverySurface(),content:@Composable ColumnScope.()->Unit) {
    Column(Modifier.padding(start=8.dp,end=8.dp,bottom=8.dp).fillMaxWidth().background(color,shape).padding(padding),content=content)
}

@Composable
private fun DiscoveryRibbon(rank:Int) {
    val colors=listOf(0xFFFF473B,0xFFFF9500,0xFFFFC400,0xFFC7DA27,0xFFB7B7B7)
    val shape=remember{object:androidx.compose.ui.graphics.Shape{override fun createOutline(size:androidx.compose.ui.geometry.Size,layoutDirection:androidx.compose.ui.unit.LayoutDirection,density:androidx.compose.ui.unit.Density)=androidx.compose.ui.graphics.Outline.Generic(androidx.compose.ui.graphics.Path().apply{moveTo(0f,0f);lineTo(size.width,0f);lineTo(size.width,size.height);lineTo(size.width/2,size.height-4*density.density);lineTo(0f,size.height);close()})}}
    Box(Modifier.size(14.dp,18.dp).clip(shape).background(Color(colors[(rank-1).coerceIn(0,4)])),contentAlignment=Alignment.TopCenter){Text("$rank",fontSize=12.sp,lineHeight=14.4.sp,color=Color.White)}
}
@Composable
private fun DiscoveryHeading(row:JSONObject,onOpen:(JSONObject)->Unit,goods:Boolean=false) {
    Row(Modifier.fillMaxWidth().clickable(enabled=row.text("url").isNotEmpty(),onClick=rememberHapticClick{onOpen(row)}).padding(vertical=4.dp),verticalAlignment=Alignment.CenterVertically) {
        Text(cardTitle(row),Modifier.weight(1f),fontSize=if(goods)18.sp else 17.sp,fontWeight=if(goods)FontWeight.SemiBold else FontWeight.Medium)
        if(goods || row.text("url").isNotEmpty()){Text(row.text("subTitle"),fontSize=if(goods)13.sp else 14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);Spacer(Modifier.width(3.dp));MaterialGlyph("chevron_right",size=if(goods)22.dp else 23.dp)}
    }
}
@Composable
internal fun DiscoveryTemplateCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,onLink:(String)->Unit,fallback:@Composable ()->Unit) {
    val template=cardTemplate(row);val children=cardChildren(row);val channel=row.text("_composeDiscoveryChannel")
    when {
        template in setOf("sortselectcard","selectorlinkcard")->DiscoverySelector(row,onOpen)
        channel=="酷品" && template=="iconbuttongridcard"->GridRows(children,2,Modifier.padding(start=8.dp,end=8.dp,bottom=8.dp),gap=8.dp){item,index->
            val url=item.text("pic","logo");val ratio=if(Regex("@\\d+x\\d+").containsMatchIn(url))bannerAspectRatio(url,false) else 2.4f
            Box(Modifier.padding(end=if(index%2==0)8.dp else 0.dp).fillMaxWidth().aspectRatio(ratio).clip(RoundedCornerShape(14.dp)).clickable(onClick=rememberHapticClick{onOpen(item)})){DiscoveryImage(api,url,null,Modifier.fillMaxSize())}
        }
        channel=="酷品" && template=="iconlargescrollcard"->DiscoveryGoodsCarousel(api,row,onOpen)
        template=="iconminigridcard"->DiscoverySurface {DiscoveryHeading(row,onOpen);Spacer(Modifier.height(6.dp));GridRows(children,2,gap=0.dp){item,_->Row(Modifier.height(36.dp).fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(item)}),verticalAlignment=Alignment.CenterVertically){DiscoveryPicture(api,item,Modifier.size(20.dp),radius=4.dp);Spacer(Modifier.width(9.dp));Text(cardTitle(item),Modifier.weight(1f),fontSize=15.sp,maxLines=1,overflow=TextOverflow.Ellipsis)}}}
        template in setOf("imagesquarescrollcard","imagecarouselcard_1")-> {
            if(children.isNotEmpty()) {
                val square=template=="imagesquarescrollcard";val width=with(LocalDensity.current){LocalWindowInfo.current.containerSize.width.toDp()}-16.dp
                val image=children.first().text("pic","logo");val ratio=if(channel=="酷品"&&Regex("@\\d+x\\d+").containsMatchIn(image))bannerAspectRatio(image,false) else configuredCardRatio(row)
                LazyRow(Modifier.padding(bottom=8.dp).height(if(square)68.dp else width/ratio),contentPadding=PaddingValues(horizontal=8.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)){items(children){item->
                    Box(Modifier.width(if(square)68.dp else width).fillMaxHeight().clip(RoundedCornerShape(12.dp)).clickable(onClick=rememberHapticClick{onOpen(item)}),contentAlignment=Alignment.Center){DiscoveryPicture(api,item,Modifier.fillMaxSize(),ContentScale.Crop);if(square){Box(Modifier.fillMaxSize().background(Color(0x40000000)));Text(cardTitle(item),Modifier.padding(4.dp),fontSize=14.sp,fontWeight=FontWeight.SemiBold,color=Color.White,textAlign=TextAlign.Center,maxLines=2,overflow=TextOverflow.Ellipsis)}}
                }}
            }
        }
        template=="iconlinkgridcard"->DiscoverySurface(PaddingValues(horizontal=5.dp,vertical=6.dp),if(channel=="好物榜")RoundedCornerShape(bottomStart=12.dp,bottomEnd=12.dp) else RoundedCornerShape(12.dp)) {
            GridRows(children,5,gap=0.dp){item,_->Column(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(if(channel=="酷图")JSONObject(item.toString()).put("_composeDiscoverySelect",true) else item)}).padding(vertical=6.dp),horizontalAlignment=Alignment.CenterHorizontally){DiscoveryPicture(api,item,Modifier.size(32.dp),ContentScale.Fit);Spacer(Modifier.height(7.dp));Text(cardTitle(item),fontSize=12.sp,maxLines=2,overflow=TextOverflow.Ellipsis,textAlign=TextAlign.Center)}}
        }
        template=="iconlongtitlegridcard"->DiscoverySurface {
            val subscriptions=children.any{it.text("entityType")=="dyh"};DiscoveryHeading(row,onOpen);Spacer(Modifier.height(8.dp))
            GridRows(children,if(subscriptions)3 else 4,gap=0.dp){item,index->if(subscriptions)DiscoveryDyhRecommendation(api,item,onOpen) else Column(Modifier.height(112.dp).fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(item)}),horizontalAlignment=Alignment.CenterHorizontally){
                Box(Modifier.fillMaxWidth()){Box(Modifier.fillMaxWidth().padding(horizontal=8.dp,vertical=6.dp),contentAlignment=Alignment.Center){DiscoveryPicture(api,item,Modifier.size(58.dp,60.dp),ContentScale.Fit)};DiscoveryRibbon(index+1)}
                Text(cardTitle(item),fontSize=14.sp,lineHeight=16.8.sp,maxLines=2,overflow=TextOverflow.Ellipsis,textAlign=TextAlign.Center)
            }}
        }
        template=="icongridcard"->DiscoverySurface {DiscoveryHeading(row,onOpen);Spacer(Modifier.height(10.dp));Row{children.take(4).forEach{item->Column(Modifier.width((with(LocalDensity.current){LocalWindowInfo.current.containerSize.width.toDp()}-40.dp)/4).clickable(onClick=rememberHapticClick{onOpen(item)}),horizontalAlignment=Alignment.CenterHorizontally){ContentAvatar(api,item.text("userAvatar","logo"),item.text("username","title"),48.dp){onOpen(item)};Spacer(Modifier.height(8.dp));Text(item.text("username","title"),fontSize=14.sp,maxLines=1,overflow=TextOverflow.Ellipsis)}}};Spacer(Modifier.height(4.dp))}
        template=="messagecard"->DiscoverySurface(PaddingValues(12.dp),color=if(channel=="二手"&&discoverySurface()==Color(0xFF1E1E1E))Color(0xFF0B201D) else discoverySurface()){ContentRichText(row.text("description","title"),onLink=onLink,fontSize=14.sp,lineHeight=17.5.sp)}
        template=="iconlistcard"&&children.any{it.text("entityType")=="goodsList"}->Column{children.forEach{DiscoveryGoodsBanner(api,it,onOpen)}}
        template=="unlogincard"->DiscoverySurface {Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{AppToastState().showSnackbar("请先使用酷安账号登录")}).padding(vertical=10.dp),verticalAlignment=Alignment.CenterVertically){Text("我订阅的看看号",Modifier.weight(1f),fontSize=17.sp);MaterialGlyph("chevron_right")}}
        template in setOf("imagecard","imagescalecard")->if(row.text("pic","cover").isNotEmpty())Box(Modifier.padding(start=8.dp,end=8.dp,bottom=8.dp).fillMaxWidth().aspectRatio(1000f/375).clip(RoundedCornerShape(12.dp)).clickable(onClick=rememberHapticClick{onOpen(row)})){DiscoveryImage(api,row.text("pic","cover"),null,Modifier.fillMaxSize())}
        else->fallback()
    }
}

@Composable
private fun DiscoverySelector(row:JSONObject,onOpen:(JSONObject)->Unit) {
    val children=cardChildren(row);if(children.isEmpty())return
    val sort=cardTemplate(row)=="sortselectcard";val selected=row.text("_composeSelectedRoute").ifEmpty{children.first().text("url")}
    @Composable fun Buttons(modifier:Modifier) {Row(modifier.horizontalScroll(rememberScrollState()).then(if(sort)Modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha=.1f),RoundedCornerShape(20.dp)).padding(2.dp) else Modifier)){children.forEach{item->
        val active=item.text("url")==selected;val radius=if(sort)20.dp else 10.dp
        Text(cardTitle(item),Modifier.padding(end=if(sort)0.dp else 8.dp).background(if(active)if(sort)discoverySurface() else Color(0xFF009688) else if(sort)Color.Transparent else discoverySurface(),RoundedCornerShape(radius)).clickable(onClick=rememberHapticClick{onOpen(JSONObject(item.toString()).put("_composeDiscoverySelect",true))}).padding(horizontal=if(sort)10.dp else 13.dp,vertical=if(sort)6.dp else 8.dp),fontSize=if(sort)13.sp else 15.sp,color=if(active&&!sort)Color.White else LocalContentColor.current)
    }}}
    Row(Modifier.padding(start=if(sort)18.dp else 8.dp,top=if(sort)4.dp else 0.dp,end=8.dp,bottom=8.dp),verticalAlignment=Alignment.CenterVertically){if(sort){Text(cardTitle(row),Modifier.weight(1f),fontSize=14.sp);Buttons(Modifier.weight(2f,fill=false))}else Buttons(Modifier)}
}

@Composable
private fun DiscoveryGoodsCarousel(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val width=((with(LocalDensity.current){LocalWindowInfo.current.containerSize.width.toDp().value}-56f)/3).coerceIn(96f,160f).dp;val scale=LocalDensity.current.fontScale
    DiscoverySurface(PaddingValues(start=12.dp,top=8.dp,end=12.dp,bottom=10.dp),RoundedCornerShape(18.dp)){DiscoveryHeading(row,onOpen,true);Spacer(Modifier.height(8.dp));LazyRow(Modifier.height(width+(7+13*scale*2.4f+5+14*scale*1.5f+8+32).dp),horizontalArrangement=Arrangement.spacedBy(8.dp)){items(cardChildren(row)){DiscoveryGoodsTile(api,it,onOpen,Modifier.width(width))}}}
}

@Composable
internal fun DiscoveryGoodsTile(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,modifier:Modifier=Modifier,pear:Boolean=false) {
    Column(modifier) {
        Column(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(row)})) {
            DiscoveryImage(api,row.text("goods_pic","pic"),null,Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(if(pear)10.dp else 9.dp)))
            Spacer(Modifier.height(if(pear)6.dp else 7.dp));Text(row.text("goods_title","title"),fontSize=13.sp,lineHeight=15.6.sp,maxLines=2,overflow=TextOverflow.Ellipsis)
            if(pear||row.text("goods_promo_title").isNotEmpty()){Spacer(Modifier.height(if(pear)4.dp else 5.dp));Text(row.text("goods_promo_title"),fontSize=if(pear)13.sp else 14.sp,fontWeight=FontWeight.SemiBold,color=Color(0xFFFF5149),maxLines=1,overflow=TextOverflow.Ellipsis)}
        }
        if(row.text("goods_buy_text").isNotEmpty()&&row.text("goods_buy_url").isNotEmpty()) {
            Spacer(Modifier.height(if(pear)6.dp else 8.dp));Box(Modifier.fillMaxWidth().height(if(pear)30.dp else 32.dp).background(Color(0xFFE94D45),RoundedCornerShape(if(pear)18.dp else 20.dp)).clickable(onClick=rememberHapticClick{onOpen(JSONObject().put("title",cardTitle(row)).put("url",row.text("goods_buy_url")))}),contentAlignment=Alignment.Center){Text(row.text("goods_buy_text"),fontSize=if(pear)12.sp else 13.sp,color=Color.White,maxLines=1,overflow=TextOverflow.Ellipsis)}
        }
    }
}

@Composable
private fun DiscoveryDyhRecommendation(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    var following by remember(row){mutableStateOf(row.optJSONObject("userAction")?.text("follow")=="1")};var working by remember{mutableStateOf(false)}
    val scope=rememberCoroutineScope();val owner=remember{api.imageCacheScope()};val session=LocalContentSession.current
    Column(Modifier.fillMaxWidth().padding(bottom=8.dp),horizontalAlignment=Alignment.CenterHorizontally){
        Column(Modifier.clickable(onClick=rememberHapticClick{onOpen(row)}),horizontalAlignment=Alignment.CenterHorizontally){DiscoveryPicture(api,row,Modifier.size(56.dp),ContentScale.Crop,8.dp);Spacer(Modifier.height(8.dp));Text(cardTitle(row),fontSize=14.sp,maxLines=1,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(4.dp));Text("${row.text("follownum")}人订阅",fontSize=11.sp)}
        Spacer(Modifier.height(6.dp));com.green.note.ui.ReviewButton(enabled=!working&&!following,contentPadding=PaddingValues(horizontal=16.dp),modifier=Modifier.defaultMinSize(minWidth=56.dp,minHeight=28.dp).height(28.dp),colors=ButtonDefaults.buttonColors(containerColor=Color(0xFF009688),contentColor=Color.White),onClick={
            if(!session.authenticated)AppToastState().showSnackbar("请先使用酷安账号登录") else {working=true;scope.launch{try{check(owner==api.imageCacheScope()){ "账号已切换" };api.request("/v6/dyh/follow","POST",query=mapOf("dyhId" to row.text("id")));check(owner==api.imageCacheScope()){ "账号已切换" };following=true}catch(cancelled:CancellationException){throw cancelled}catch(failure:Exception){AppToastState().showSnackbar(failure.message?:"订阅失败")}finally{working=false}}}
        }){Text(if(working)"…" else if(following)"已订阅" else "订阅",fontSize=13.sp)}
    }
}

@Composable
internal fun DiscoveryGoodsBanner(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    Box(Modifier.padding(horizontal=8.dp).fillMaxWidth().aspectRatio(1680f/720).clip(RoundedCornerShape(topStart=12.dp,topEnd=12.dp)).clickable(onClick=rememberHapticClick{onOpen(row)})) {
        DiscoveryImage(api,row.text("cover","pic"),null,Modifier.fillMaxSize());Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent,Color(0x88000000)))))
        if(row.text("recommend")!="0")Text("♨ 推荐",Modifier.padding(start=12.dp,top=12.dp).background(Color(0xFFFFC044),RoundedCornerShape(4.dp)).padding(horizontal=7.dp,vertical=4.dp),fontSize=12.sp,color=Color.White)
        Text(cardTitle(row),Modifier.align(Alignment.BottomStart).padding(start=16.dp,end=16.dp,bottom=42.dp),fontSize=19.sp,fontWeight=FontWeight.SemiBold,fontStyle=FontStyle.Italic,color=Color.White,maxLines=2,overflow=TextOverflow.Ellipsis)
        Text("${row.opt("item_num")?:0}个好物  ${row.opt("vote_num")?:0}人投票",Modifier.align(Alignment.BottomEnd).padding(end=14.dp,bottom=16.dp),fontSize=12.sp,color=Color.White)
    }
}
