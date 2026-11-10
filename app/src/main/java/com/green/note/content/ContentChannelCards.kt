package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.rememberHapticClick
import org.json.JSONObject
import kotlin.math.round

@Composable
internal fun DigitalProductRow(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,brand:Boolean=false) {
    val scheme=MaterialTheme.colorScheme;val hot=digitalHot(row.text("hot_num_txt","hot_num"));val comments=row.text("feed_comment_num","feedCommentNumTxt","commentnum","commentNum")
    val score=row.text("star_average_score","score","rating_score");val numeric=score.toFloatOrNull()?:0f;val unreleased=row.text("release_status")=="0"
    val extra=cardExtra(row);val top=extra.text("rightTopText");val bottom=extra.text("rightBottomText")
    Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(row)}).padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
        Box(Modifier.size(64.dp),contentAlignment=Alignment.Center) {
            Box(Modifier.size(60.dp).then(if(brand)Modifier else Modifier.background(scheme.surfaceContainerHighest.copy(alpha=.4f),RoundedCornerShape(8.dp))),contentAlignment=Alignment.Center) {
                CardPicture(api,row,Modifier.size(if(brand)60.dp else 54.dp),radius=if(brand)8.dp else 0.dp,fallback="devices_other_rounded",fallbackSize=32.dp,errorFallback=true)
            }
            if(unreleased)Text("-- 未发布 --",Modifier.background(Color.Black.copy(alpha=.72f),RoundedCornerShape(4.dp)).padding(horizontal=4.dp,vertical=2.dp),fontSize=8.5.sp,fontWeight=FontWeight.Bold,color=Color.White)
        }
        Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)) {
            Text(cardTitle(row).ifEmpty{"数码产品"},fontSize=15.sp,fontWeight=if(brand)FontWeight.Normal else FontWeight.Bold,maxLines=1,overflow=TextOverflow.Ellipsis)
            Spacer(Modifier.height(5.dp));Row(verticalAlignment=Alignment.CenterVertically) {
                if(hot.isNotEmpty()){MaterialGlyph("local_fire_department",size=13.dp,color=Color(0xFFFF5722));Spacer(Modifier.width(2.dp));Text("${hot}热度",fontSize=12.sp,color=scheme.onSurfaceVariant)}
                if(comments.isNotEmpty()&&comments!="0"){Spacer(Modifier.width(8.dp));Text("${comments}讨论",fontSize=12.sp,color=scheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}
            }
        }
        Spacer(Modifier.width(8.dp));Column(horizontalAlignment=Alignment.End) {
            when {
                top.isNotEmpty()->{Text(top,fontSize=20.sp,fontWeight=FontWeight.Bold,color=Color(0xFFFF8F00));Text(bottom,fontSize=11.sp,color=scheme.onSurfaceVariant)}
                unreleased&&row.text("release_time").isNotEmpty()->{Text(row.text("release_time"),fontSize=12.sp,fontWeight=FontWeight.SemiBold,color=Color(0xFF00B074));Text("发布时间",fontSize=11.sp,color=scheme.onSurfaceVariant)}
                numeric>0->{Text(score,fontSize=20.sp,fontWeight=FontWeight.Bold,color=if(brand)scheme.onSurface else Color(0xFFFF8F00));if(brand){Spacer(Modifier.height(4.dp));Row(horizontalArrangement=Arrangement.spacedBy(2.dp)){repeat(5){index->val n=round(numeric)/2;val empty=n<=index;Box(Modifier.size(12.dp).background(if(empty)scheme.outlineVariant else Color(0xFFDFA900),RoundedCornerShape(3.dp)),contentAlignment=Alignment.Center){MaterialGlyph(if(!empty&&n<index+1)"star_half_rounded" else "star_rounded",size=9.dp,color=Color.White.copy(alpha=if(empty).54f else 1f))}}}}else Text("综合评分",fontSize=11.sp,color=scheme.onSurfaceVariant)}
                else->Text("暂无人评分",fontSize=12.sp,color=scheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
internal fun GroupedDigitalProductRow(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val shape=RoundedCornerShape(topStart=if(row.optBoolean("_composeGroupStart"))18.dp else 0.dp,topEnd=if(row.optBoolean("_composeGroupStart"))18.dp else 0.dp,
        bottomStart=if(row.optBoolean("_composeGroupEnd"))18.dp else 0.dp,bottomEnd=if(row.optBoolean("_composeGroupEnd"))18.dp else 0.dp)
    Box(Modifier.padding(horizontal=10.dp).fillMaxWidth().background(com.green.note.ui.reviewCardSurface(),shape).padding(horizontal=12.dp)){DigitalProductRow(api,row,onOpen,brand=true)}
}

@Composable
internal fun DigitalProductListCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,brand:Boolean) {
    DigitalReviewCard {Column(Modifier.padding(start=14.dp,top=12.dp,end=14.dp,bottom=8.dp)) {
        if(cardTitle(row).isNotEmpty()){CardHeading(row,onOpen,defaultMore=if(cardTitle(row)=="最新产品")"" else "更多");Spacer(Modifier.height(6.dp))}
        cardChildren(row).forEach{DigitalProductRow(api,it,onOpen,brand)}
    }}
}

@Composable
internal fun ChannelIconGrid(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val scheme=MaterialTheme.colorScheme
    DigitalReviewCard {Column(Modifier.padding(horizontal=14.dp,vertical=12.dp)) {
        if(cardTitle(row).isNotEmpty()){CardHeading(row,onOpen);Spacer(Modifier.height(12.dp))}
        GridRows(cardChildren(row).take(4),4){item,_->Column(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(item)}).padding(2.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            CardPicture(api,item,Modifier.size(58.dp).background(scheme.surfaceContainerHighest.copy(alpha=.5f),RoundedCornerShape(14.dp)),ContentScale.Crop,14.dp,"computer_rounded",errorFallback=true)
            Spacer(Modifier.height(6.dp));Text(cardTitle(item),fontSize=12.5.sp,fontWeight=FontWeight.SemiBold,textAlign=TextAlign.Center,maxLines=1,overflow=TextOverflow.Ellipsis)
            val heat=digitalHot(item.text("hot_num_txt","hot_num","subTitle")).replace("热度","").replace("🔥","").trim()
            if(heat.isNotEmpty()){Spacer(Modifier.height(2.dp));Row(verticalAlignment=Alignment.CenterVertically){MaterialGlyph("local_fire_department",size=11.dp,color=scheme.onSurfaceVariant);Spacer(Modifier.width(1.dp));Text(heat,fontSize=10.5.sp,color=scheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}}
        }}
    }}
}

@Composable
internal fun BrandHorizonCard(api:ContentApi,items:List<JSONObject>,onOpen:(JSONObject)->Unit) {
    LazyRow(Modifier.padding(horizontal=10.dp,vertical=4.dp).height(126.dp),horizontalArrangement=Arrangement.spacedBy(10.dp)) {
        items(items.chunked(2)){group->Column(verticalArrangement=Arrangement.spacedBy(8.dp)){group.forEach{brand->Column(Modifier.width(68.dp).clickable(onClick=rememberHapticClick{onOpen(brand)}),horizontalAlignment=Alignment.CenterHorizontally) {
            Surface(shape=RoundedCornerShape(8.dp),color=Color.White,shadowElevation=1.dp){Box(Modifier.size(68.dp,38.dp).padding(horizontal=6.dp,vertical=3.dp),contentAlignment=Alignment.Center) {
                val logo = cardImage(brand)
                val fallback: @Composable () -> Unit = { Text(cardTitle(brand),fontSize=11.sp,fontWeight=FontWeight.Bold,color=Color.Black.copy(alpha=.87f)) }
                val route = brand.text("url")
                if (brand.text("entityType").equals("productBrand", true) ||
                    route.contains("/product/seriesList", true) || route.contains("product%2FseriesList", true)) {
                    DigitalBrandLogo(api, brand, logo, Modifier.fillMaxSize(), fallback)
                } else CardImage(api, logo, Modifier.fillMaxSize(), ContentScale.Fit, fallback = fallback)
            }}
            Spacer(Modifier.height(4.dp));Text(cardTitle(brand),Modifier.width(68.dp),fontSize=12.sp,textAlign=TextAlign.Center,maxLines=1,overflow=TextOverflow.Ellipsis)
        }}}}
    }
}

@Composable
internal fun SystemShortcutGrid(api:ContentApi,items:List<JSONObject>,onOpen:(JSONObject)->Unit) {
    GridRows(items,2,gap=8.dp){item,index->Row(Modifier.fillMaxWidth().padding(end=if(index%2==0)10.dp else 0.dp).clickable(onClick=rememberHapticClick{onOpen(item)}).padding(2.dp),verticalAlignment=Alignment.CenterVertically) {
        if(cardImage(item).isNotEmpty())CardPicture(api,item,Modifier.size(24.dp),radius=5.dp,fallback="system_update_alt_rounded",fallbackSize=20.dp,errorFallback=true) else MaterialGlyph("system_update_alt_rounded",size=20.dp)
        Spacer(Modifier.width(8.dp));Text(cardTitle(item),Modifier.weight(1f),fontSize=13.5.sp,fontWeight=FontWeight.Normal,maxLines=1,overflow=TextOverflow.Ellipsis)
    }}
}

@Composable
internal fun NewSystemCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val header=if(row.text("moreUrl","url").isEmpty())JSONObject(row.toString()).put("url","#/topic/tagList?withSymbol=0&keywords=2026rom&sort=hot_num&cacheExpires=300&title=新系统") else row
    DigitalReviewCard {Column(Modifier.padding(14.dp)){CardHeading(header,onOpen);Spacer(Modifier.height(10.dp));SystemShortcutGrid(api,cardChildren(row),onOpen)}}
}

@Composable
internal fun SystemZoneCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val main=row.optJSONObject("mainCard")?.let(::cardChildren)?.firstOrNull();val features=row.optJSONObject("featureCard")?.let(::cardChildren).orEmpty()
    DigitalReviewCard {Column(Modifier.padding(14.dp)){Text(cardTitle(row),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.Bold);Spacer(Modifier.height(12.dp))
        if(main!=null){SystemFeatureRow(api,main,onOpen,true);Spacer(Modifier.height(12.dp))}
        if(features.isNotEmpty())SystemShortcutGrid(api,features,onOpen)
    }}
}

@Composable
internal fun HotFeaturesCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit) {
    val header=if(row.text("moreUrl","url").isEmpty())JSONObject(row.toString()).put("url","#/topic/tagList?filterId=1&keywords=系统功能&ratingUI=1&withConfigCard=1&configCardExtraData=%7B%22withRanking%22%3A1%7D&title=热门功能") else row
    DigitalReviewCard {Column(Modifier.padding(14.dp)){CardHeading(header,onOpen,defaultMore="榜单");Spacer(Modifier.height(12.dp));Column(verticalArrangement=Arrangement.spacedBy(14.dp)){cardChildren(row).forEach{SystemFeatureRow(api,it,onOpen)}}}}
}

@Composable
private fun SystemFeatureRow(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,zone:Boolean=false) {
    val hot=digitalHot(row.text("hot_num_txt","hot_num"));val comments=digitalHot(row.text("commentnum","commentNum","feedCommentNumTxt"));val score=row.text("star_average_score","score")
    Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick{onOpen(row)}).padding(vertical=if(zone)2.dp else 0.dp),verticalAlignment=Alignment.CenterVertically) {
        CardPicture(api,row,Modifier.size(58.dp),ContentScale.Crop,if(zone)12.dp else 10.dp,if(zone)"system_update_alt_rounded" else "apps_rounded",fallbackSize=if(zone)38.dp else 36.dp,errorFallback=true)
        Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){Text(cardTitle(row),fontSize=if(zone)17.sp else 16.sp,fontWeight=FontWeight.Bold,maxLines=1,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(if(zone)5.dp else 6.dp));Text(listOfNotNull(hot.takeIf{it.isNotEmpty()}?.let{"🔥 ${it}热度"},comments.takeIf{it.isNotEmpty()}?.let{"${it}讨论"}).joinToString(" "),fontSize=12.5.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}
        if(score.isNotEmpty()){Spacer(Modifier.width(8.dp));Column(horizontalAlignment=Alignment.End){Text(score,fontSize=if(zone)22.sp else 20.sp,lineHeight=if(zone)24.2.sp else 22.sp,fontWeight=FontWeight.Bold);Spacer(Modifier.height(3.dp));DigitalStars(score.toFloatOrNull()?:0f,13.dp,boxed=false)}}
    }
}

@Composable
internal fun DigitalSortHeader(row:JSONObject,onOpen:(JSONObject)->Unit) {
    val tabs=cardChildren(row).ifEmpty{listOf(JSONObject().put("title","最近回复").put("url","#/feed/targetFeedList?tagKeywords=2024rom&sortField=lastupdate_desc"),JSONObject().put("title","热门排序").put("url","#/feed/targetFeedList?tagKeywords=2024rom&sortField=rank_score"))}
    val selected=row.text("_selectedSortTitle").ifEmpty{"最近回复"}
    Row(Modifier.padding(start=14.dp,top=16.dp,end=14.dp,bottom=8.dp).fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.SpaceBetween) {
        Text(cardTitle(row).ifEmpty{"动态区"},style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.Bold)
        Row(Modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha=.6f),RoundedCornerShape(16.dp)).padding(2.5.dp)) {tabs.forEach{tab->
            val active=cardTitle(tab)==selected;val color by animateColorAsState(if(active)MaterialTheme.colorScheme.surfaceContainerHighest else Color.Transparent,tween(200),label="sort selection")
            Text(cardTitle(tab),Modifier.background(color,RoundedCornerShape(14.dp)).clickable(onClick=rememberHapticClick{onOpen(JSONObject(tab.toString()).put("_composeSortRequest",true))}).padding(horizontal=10.dp,vertical=4.dp),fontSize=12.5.sp,fontWeight=if(active)FontWeight.Bold else FontWeight.Normal,color=if(active)MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
        }}
    }
}
