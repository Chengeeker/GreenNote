package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.text.Html
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.*
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.green.note.ui.LocalAppPreferences
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.rememberHapticClick
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

internal fun cardContext(row:JSONObject)=row.text("_composeCardContext").ifEmpty{"api"}
internal fun cardTemplate(row:JSONObject)=row.text("entityTemplate","entity_template").lowercase()
internal fun cardChildren(row:JSONObject)=row.optJSONArray("entities").objects()
internal fun cardImage(row:JSONObject)=row.text("goods_pic","logo","pic","iconUrl","icon","message_cover","cover","img","avatar","userAvatar")
internal fun cardTitle(row:JSONObject)=row.text("goods_title","title","name","productTitle","productName","username","tag")
internal fun cardExtra(row:JSONObject):JSONObject {
    val raw=row.opt("extraDataArr") ?: row.opt("extraData")
    return if(raw is JSONObject)raw else if(raw is String)runCatching{JSONObject(raw)}.getOrDefault(JSONObject()) else JSONObject()
}
internal fun digitalHot(raw:String):String {
    val value=raw.trim();if(value.isEmpty() || value.contains('万') || value.contains('k',true))return value
    val number=value.toDoubleOrNull() ?: return value
    if(!number.isFinite())return value
    return if(number>=10000)String.format(Locale.ROOT,"%.1f",number/10000).removeSuffix(".0")+"万" else value
}
internal fun bannerAspectRatio(url:String,clamp:Boolean=true):Float {
    val parts=Regex("@(\\d+)x(\\d+)").find(url)?.groupValues ?: return 4.5f
    val width=parts[1].toFloatOrNull() ?: return 4.5f;val height=parts[2].toFloatOrNull() ?: return 4.5f
    if(width<=0 || height<=0)return 4.5f
    val ratio=width/height
    return if(!clamp)ratio else if(ratio<3.4f)3.338f else ratio.coerceIn(3.338f,4.5f)
}
internal fun normalizeSpecializedCards(rows:List<JSONObject>):List<JSONObject> {
    val system=ArrayList<JSONObject>();var index=0
    while(index<rows.size) {
        val row=JSONObject(rows[index].toString());val context=cardContext(row)
        if(context=="system" && cardTitle(row).contains("系统区")) {
            val next=rows.getOrNull(index+1)
            val feature=next?.takeIf{cardTitle(it).isEmpty() && cardTemplate(it).contains("grid")}
            system.add(JSONObject().put("entityType","system_zone_card").put("id","system-zone-${row.text("id","title")}").put("title",cardTitle(row))
                .put("mainCard",row).put("featureCard",feature?.let{JSONObject(it.toString())}).put("_composeCardContext",context))
            if(feature!=null)index++
        } else system.add(row)
        index++
    }
    val result=ArrayList<JSONObject>();index=0
    while(index<system.size) {
        val row=system[index];val next=system.getOrNull(index+1)
        if(cardContext(row) in setOf("digital_channel","system") && cardTemplate(row).startsWith("imagecarouselcard") && next!=null && cardTemplate(next)=="iconminilinkgridcard") {
            row.put("quickLinks",next.optJSONArray("entities") ?: JSONArray());index++
        }
        result.add(row);index++
    }
    result.forEachIndexed { i,item ->
        if(item.optBoolean("_composeGroupProducts")&&item.text("entityType").equals("product",true)) {
            fun product(index:Int)=result.getOrNull(index)?.let{it.optBoolean("_composeGroupProducts")&&it.text("entityType").equals("product",true)}==true
            item.put("_composeGroupStart",!product(i-1)).put("_composeGroupEnd",!product(i+1))
        }
    }
    return result
}
internal fun hasSpecializedCard(row:JSONObject):Boolean {
    val type=row.text("entityType","entity_type").lowercase()
    return cardContext(row) in setOf("market","today") || type=="card" || type=="system_zone_card" || (type in setOf("imagetext","user","pear_goods")&&cardContext(row)=="home") || (type=="product" && cardContext(row) in setOf("digital_channel","system","digital_home","brand"))
}

@Composable
internal fun SpecializedEntityCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,onUser:(String)->Unit,
    onLink:(String)->Unit,onGallery:(List<String>,Int,JSONObject?)->Unit,onLike:(JSONObject)->Unit,onMore:(JSONObject)->Unit) {
    val template=cardTemplate(row);val type=row.text("entityType","entity_type").lowercase();val context=cardContext(row)
    if(context=="market"){MarketCard(api,row,onOpen,onUser,onLink,onGallery,onLike,onMore);return}
    if(context=="today"){TodayHeadlineCard(api,row,onOpen,onUser,onLink,onGallery,onLike,onMore);return}
    val children=cardChildren(row);val title=cardTitle(row)
    val child:@Composable (JSONObject)->Unit={item->
        val tagged=remember(item,context){JSONObject(item.toString()).put("_composeCardContext",context)}
        EntityRow(api,tagged,onOpen,onUser,onLink,onGallery,onLike,onMore)
    }
    if(template in setOf("nomoredatacard","configcard","sponsorcard") || type=="ad")return
    when {
        type=="system_zone_card" -> SystemZoneCard(api,row,onOpen)
        context=="home"&&type=="user"->HomeUserRanking(api,row,onUser)
        context=="home"&&type=="pear_goods"&&row.text("_composeHomeDestination")=="activities"->HomeOfflineActivity(api,row,onOpen)
        type=="product" -> if(row.optBoolean("_composeGroupProducts"))GroupedDigitalProductRow(api,row,onOpen)else DigitalProductRow(api,row,onOpen,brand=context=="brand")
        context=="home" -> HomeTemplateCard(api,row,onOpen,onLink) {GeneralTemplateCard(api,row,onOpen,child)}
        context=="discovery" -> DiscoveryTemplateCard(api,row,onOpen,onLink) {GeneralTemplateCard(api,row,onOpen,child)}
        context=="digital_home" -> when {
            title=="我的关注" || template.contains("follow") -> DigitalFollowCard(api,row,onOpen)
            template.contains("iconlinkgrid") || template.contains("icontablinkgrid") -> DigitalCategoryCard(api,children,onOpen)
            template.contains("imagecarousel") || template=="imagecard" -> CardCarousel(api,row,onOpen,home=true)
            template.contains("producttimeline") -> DigitalTimelineCard(api,row,onOpen)
            template.contains("grid") -> DigitalRankCard(api,row,onOpen,home=true)
            template in setOf("iconlistcard","feedlistcard") -> DigitalHomeListCard(api,row,onOpen,onUser,onLink,onGallery,onLike,onMore)
            else -> GeneralTemplateCard(api,row,onOpen,child)
        }
        context in setOf("digital_channel","system","brand") -> when {
            context=="system" && title.contains("新系统") -> NewSystemCard(api,row,onOpen)
            context=="system" && title.contains("热门功能") -> HotFeaturesCard(api,row,onOpen)
            title.contains("动态区") || template=="sortselectcard" -> DigitalSortHeader(row,onOpen)
            template=="iconlongtitlegridcard" || title=="今日热门" -> DigitalRankCard(api,row,onOpen,home=false)
            template=="icongridhorizoncard" -> BrandHorizonCard(api,children,onOpen)
            template=="iconminilinkgridcard" -> DigitalReviewCard { QuickLinks(api,children,onOpen) }
            template.startsWith("imagecarouselcard") || template.startsWith("imagecard") -> CardCarousel(api,row,onOpen,home=false)
            template in setOf("iconlistcard","listcard") || (children.isNotEmpty() && children.all{it.text("entityType")=="product"} && !template.contains("grid")) -> DigitalProductListCard(api,row,onOpen,context=="brand")
            template.contains("grid") -> if(context=="system")DigitalReviewCard { Column(Modifier.padding(14.dp)) { CardHeading(row,onOpen);SystemShortcutGrid(api,children,onOpen) } } else ChannelIconGrid(api,row,onOpen)
            else -> GeneralTemplateCard(api,row,onOpen,child)
        }
        else -> GeneralTemplateCard(api,row,onOpen,child)
    }
}

@Composable
internal fun DigitalReviewCard(home:Boolean=false,modifier:Modifier=Modifier,content:@Composable ColumnScope.()->Unit) {
    val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    val black=LocalAppPreferences.current.pureBlackDark && dark
    val color=if(dark)if(black)Color(0xFF121212) else Color(0xFF1B1C20) else scheme.surfaceContainerLowest
    Box(modifier.padding(horizontal=if(home)8.dp else 10.dp,vertical=if(home)4.dp else 5.dp).fillMaxWidth()
        .shadow(if(home)0.dp else 1.dp,RoundedCornerShape(20.dp),clip=false).background(color,RoundedCornerShape(20.dp))
        .border(.8.dp,if(black)Color.White.copy(alpha=.12f) else scheme.outlineVariant.copy(alpha=if(dark).2f else .25f),RoundedCornerShape(20.dp))) {
        Column(content=content)
    }
}

@Composable
internal fun CardHeading(row:JSONObject,onOpen:(JSONObject)->Unit,home:Boolean=false,defaultMore:String="更多",titleStyle:androidx.compose.ui.text.TextStyle=LocalTextStyle.current) {
    val title=cardTitle(row);val subtitle=row.text("subTitle");val target=row.text("moreUrl","url")
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
        Text(title,Modifier.weight(1f),style=titleStyle,fontSize=if(home)14.sp else 16.sp,fontWeight=if(home)FontWeight.Medium else FontWeight.Bold)
        if(home || target.isNotEmpty() || subtitle.isNotEmpty())Row(Modifier.clickable(onClick=rememberHapticClick { onOpen(JSONObject(row.toString()).put("url",target)) }),verticalAlignment=Alignment.CenterVertically) {
            Text(subtitle.takeIf{it.isNotEmpty()&&it!=title} ?: defaultMore,fontSize=if(home)12.sp else 13.5.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(2.dp));MaterialGlyph("chevron_right_rounded",size=16.dp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun CardPicture(api:ContentApi,row:JSONObject,modifier:Modifier,scale:ContentScale=ContentScale.Fit,radius:Dp=0.dp,fallback:String="devices_rounded",fallbackSize:Dp=28.dp,fallbackColor:Color=com.green.note.ui.LocalMaterialGlyphColor.current,errorFallback:Boolean=false) {
    val url=cardImage(row)
    if(errorFallback)CardImage(api,url,modifier,scale,radius,cardTitle(row)){MaterialGlyph(fallback,size=fallbackSize,color=fallbackColor)}
    else Box(modifier.clip(RoundedCornerShape(radius)),contentAlignment=Alignment.Center) {
        if(url.isNotEmpty())ContentImage(api,url,cardTitle(row),Modifier.fillMaxSize(),scale,heroCornerRadius=radius)
        else MaterialGlyph(fallback,size=fallbackSize,color=fallbackColor)
    }
}

@Composable
internal fun CardCarousel(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,home:Boolean) {
    val children=cardChildren(row).ifEmpty {if(cardImage(row).isNotEmpty())listOf(row) else emptyList()}
    if(children.isEmpty())return
    val state=rememberPagerState{children.size};val lifecycle=LocalLifecycleOwner.current.lifecycle
    WarmCurrentTopic(children[state.currentPage.coerceIn(children.indices)])
    val context=LocalContext.current
    val durationScale=android.provider.Settings.Global.getFloat(context.contentResolver,android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,1f)
    LaunchedEffect(children.map(::cardImage),home,durationScale) { if(home && durationScale>0)while(true) {
        delay(5000);if(children.size>1 && !state.isScrollInProgress && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
            state.animateScrollToPage((state.currentPage+1)%children.size,animationSpec=tween(350,easing=CubicBezierEasing(.215f,.61f,.355f,1f)))
    } }
    DigitalReviewCard(home) {
        Box(Modifier.fillMaxWidth().aspectRatio(if(home)4.5f else bannerAspectRatio(cardImage(children.first()))).clip(RoundedCornerShape(if(home)20.dp else 14.dp))) {
            HorizontalPager(state,modifier=Modifier.fillMaxSize()) { index->CardImage(api,if(home)digitalHomeImage(children[index])else cardImage(children[index]),Modifier.fillMaxSize().clickable(onClick=rememberHapticClick{onOpen(children[index])}),ContentScale.Crop,if(home)6.dp else 0.dp) }
            if(home && children.size>1)Row(Modifier.align(Alignment.BottomEnd).padding(end=8.dp,bottom=6.dp),horizontalArrangement=Arrangement.spacedBy(4.dp)) {
                repeat(children.size){index->Box(Modifier.size(4.dp).background(Color.White.copy(alpha=if(index==state.currentPage)1f else .35f),CircleShape))}
            }
        }
        if(!home)row.optJSONArray("quickLinks")?.objects()?.takeIf{it.isNotEmpty()}?.let {
            Box(Modifier.background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha=.6f),RoundedCornerShape(bottomStart=14.dp,bottomEnd=14.dp))) {QuickLinks(api,it,onOpen)}
        }
    }
}

@Composable
internal fun QuickLinks(api:ContentApi,items:List<JSONObject>,onOpen:(JSONObject)->Unit) {
    Row(Modifier.padding(horizontal=6.dp,vertical=12.dp)) { items.forEach{item->
        Row(Modifier.weight(1f).clickable(onClick=rememberHapticClick{onOpen(item)}).padding(vertical=4.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.Center) {
            if(cardImage(item).isNotEmpty()){CardImage(api,cardImage(item),Modifier.size(18.dp),ContentScale.Fit);Spacer(Modifier.width(6.dp))}
            Text(cardTitle(item),fontSize=13.5.sp,fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis)
        }
    } }
}

@Composable
private fun GeneralTemplateCard(api:ContentApi,row:JSONObject,onOpen:(JSONObject)->Unit,child:@Composable (JSONObject)->Unit) {
    val template=cardTemplate(row);val title=cardTitle(row);val children=cardChildren(row)
    when {
        template=="textcard" -> Column(Modifier.padding(start=16.dp,top=16.dp,end=16.dp,bottom=8.dp)) {
            if(title.isNotEmpty())Text(title,style=MaterialTheme.typography.titleMedium)
            if(row.text("description").isNotEmpty()){Spacer(Modifier.height(8.dp));ContentRichText(row.text("description"),onLink={onOpen(JSONObject().put("url",it))})}
        }
        template=="imagescalecard" -> {val picture=cardImage(row).ifEmpty{children.firstOrNull()?.let(::cardImage).orEmpty()};if(picture.isNotEmpty())ContentImage(api,picture,title,Modifier.padding(horizontal=12.dp,vertical=8.dp).fillMaxWidth().aspectRatio(bannerAspectRatio(picture,false)).clip(RoundedCornerShape(12.dp))) }
        template=="refreshcard" -> Box(Modifier.padding(16.dp)){com.green.note.ui.ReviewButton(onClick=rememberHapticClick{onOpen(row)}){Text(title)}}
        template in setOf("headcard","titlecard") -> Column(Modifier.padding(start=14.dp,top=18.dp,end=14.dp,bottom=6.dp)) {
            if(title.isNotEmpty())Text(title,style=MaterialTheme.typography.titleMedium)
            row.text("description","subTitle").takeIf{it.isNotEmpty()}?.let{Text(it,style=MaterialTheme.typography.bodySmall)}
        }
        template in setOf("iconlinkgridcard","iconminigridcard","imagetextgridcard") -> Column {
            if(title.isNotEmpty())Text(title,Modifier.padding(start=14.dp,top=16.dp,end=14.dp,bottom=4.dp),style=MaterialTheme.typography.titleMedium)
            GridRows(children,4,Modifier.padding(horizontal=8.dp,vertical=4.dp)){item,_->Box(Modifier.aspectRatio(.82f)){TemplateItem(api,item,onOpen,true)}}
        }
        template in setOf("imagecarouselcard_1","iconminiscrollcard","iconlargescrollcard","imagesquarescrollcard","iconscrollcard","imagetextscrollcard") -> {
            val users=title=="用户" || children.any{it.text("entityType","entity_type").contains("user",true)||it.has("uid")}
            if(users)Surface(Modifier.padding(start=10.dp,top=8.dp,end=10.dp,bottom=4.dp),shape=RoundedCornerShape(16.dp),color=MaterialTheme.colorScheme.surfaceContainerLowest) {
                Column(Modifier.padding(start=14.dp,top=12.dp,end=14.dp,bottom=10.dp)) {
                    Text("用户",Modifier.padding(start=2.dp,bottom=8.dp),fontSize=15.sp,fontWeight=FontWeight.Bold,color=Color.White)
                    LazyRow(Modifier.height(104.dp),contentPadding=PaddingValues(horizontal=2.dp),horizontalArrangement=Arrangement.spacedBy(14.dp)){items(children){item->Box(Modifier.width(72.dp)){TemplateItem(api,item,onOpen)}}}
                    Spacer(Modifier.height(8.dp));Text("更多相关用户",Modifier.align(Alignment.CenterHorizontally).clickable{onOpen(JSONObject(row.toString()).put("_switchSearchTab","user"))}.padding(horizontal=16.dp,vertical=6.dp),fontSize=13.sp,fontWeight=FontWeight.Medium,color=Color(0xFF00B075))
                }
            } else Column {
                if(title.isNotEmpty())Text(title,Modifier.padding(start=14.dp,top=16.dp,end=14.dp,bottom=4.dp),style=MaterialTheme.typography.titleMedium)
                LazyRow(Modifier.height(116.dp),contentPadding=PaddingValues(horizontal=14.dp,vertical=6.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)){items(children){item->Box(Modifier.width(92.dp)){TemplateItem(api,item,onOpen)}}}
            }
        }
        else -> Column {
            if(title.isNotEmpty())Text(title,Modifier.padding(start=14.dp,top=16.dp,end=14.dp,bottom=4.dp),style=MaterialTheme.typography.titleMedium)
            children.forEach{child(it)}
        }
    }
}

@Composable
internal fun <T> GridRows(items:List<T>,columns:Int,modifier:Modifier=Modifier,gap:Dp=0.dp,content:@Composable RowScope.(T,Int)->Unit) {
    Column(modifier,verticalArrangement=Arrangement.spacedBy(gap)) { items.chunked(columns).forEachIndexed { row,group->Row(Modifier.fillMaxWidth()) {
        group.forEachIndexed { index,item->Box(Modifier.weight(1f)){Row{content(item,row*columns+index)}} }
        repeat(columns-group.size){Spacer(Modifier.weight(1f))}
    } } }
}

@Composable
private fun TemplateItem(api:ContentApi,item:JSONObject,onOpen:(JSONObject)->Unit,compact:Boolean=false) {
    val type=contentEntityType(item)
    val user=type.contains("user")||item.has("uid")||(item.has("username")&&!type.contains("feed"));val image=item.text("goods_pic","logo","icon","pic","cover","avatar")
    val target=remember(item){JSONObject(item.toString()).put("_composeApiTemplateItem",true)}
    val enabled=contentEntityId(item).isNotEmpty()||item.text("url").isNotEmpty()
    Column(Modifier.fillMaxWidth().clickable(enabled=enabled,onClick=rememberHapticClick{onOpen(target)}).padding(horizontal=4.dp,vertical=6.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
        if(image.isNotEmpty())CardImage(api,image,Modifier.size(if(user)52.dp else if(compact)42.dp else 64.dp),ContentScale.Crop,if(user)100.dp else 10.dp) { MaterialGlyph(if(user)"person_outline_rounded" else "widgets_outlined",size=if(compact)30.dp else 40.dp) }
        else MaterialGlyph(if(user)"person_outline_rounded" else "widgets_outlined",size=if(compact)30.dp else 40.dp)
        Spacer(Modifier.height(6.dp));Text(cardTitle(item).ifEmpty{"更多"},fontSize=12.sp,color=if(user)Color.White.copy(alpha=.7f) else MaterialTheme.colorScheme.onSurface,fontWeight=if(user)FontWeight.Normal else FontWeight.Medium,maxLines=2,textAlign=TextAlign.Center,overflow=TextOverflow.Ellipsis)
    }
}

@Composable
internal fun RankRibbon(rank:Int,width:Dp=16.dp,height:Dp=20.dp) {
    val shape=remember{object:Shape{override fun createOutline(size:Size,layoutDirection:LayoutDirection,density:Density)=Outline.Generic(Path().apply{lineTo(0f,size.height);lineTo(size.width*.5f,size.height*.78f);lineTo(size.width,size.height);lineTo(size.width,0f);close()})}}
    val color=when(rank){1->0xFFFF443C;2->0xFFFF8700;3->0xFFFFBD00;4->0xFFC5DF2D;else->0xFF7A7F85}
    Box(Modifier.size(width,height).clip(shape).background(Color(color)).padding(top=1.dp),contentAlignment=Alignment.TopCenter){Text("$rank",fontSize=10.sp,lineHeight=11.sp,fontWeight=FontWeight.ExtraBold,color=Color.White)}
}
