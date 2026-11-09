package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.adjustedWeight
import androidx.compose.ui.platform.LocalView
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder

// Exact navigation defaults retained from feed_pages.dart 2187–2370, not live news data.
private val homeHeaderDefaults = JSONObject("""{"headline":[{"entityTemplate":"imageCarouselCard_1","entityType":"card","entities":[{"title":"年轻人的第一辆车","pic":"https://image.coolapk.com/feed/2024/0905/15/456889_1725522515_8218.jpg","url":"/page?url=V9_CAR_CENTER"},{"title":"今日酷安","pic":"https://image.coolapk.com/feed/2024/0905/15/456889_1725522515_8218.jpg","url":"/feed/headline"}]},{"entityTemplate":"iconLinkGridCard","entityType":"card","entities":[{"title":"值得看","url":"/page?url=V8_ZHUANTI_20180327"},{"title":"热闻","url":"/page?url=V8_JINRI_NEWS"},{"title":"活动","url":"/page?url=V11_ACTIVITIES"},{"title":"AI","url":"/page?url=V9_AI_ZONE"},{"title":"人像摄影","url":"/t/人像摄影"},{"title":"选机中心","url":"https://m.coolapk.com/mp/productSelector/configSearch?callFunction=indexSearch"},{"title":"玩机大神","url":"/page?url=V8_RECOMMEND_USER"},{"title":"投票","url":"#/feed/digestList?type=16&message_status=all"},{"title":"头条榜","url":"/page?url=V9_LISHITOUTIAO_NEW"},{"title":"官方频道","url":"/page?url=V11_ZHUANTI_EDITORIALDEPARTMENT_20211117"}]},{"entityTemplate":"iconMiniScrollCard","entityType":"card","entities":[{"title":"vivo X300 Pro","url":"/page?url=V9_SEARCH_PHONE&key=vivo+X300+Pro"},{"title":"真我Neo8","url":"/page?url=V9_SEARCH_PHONE&key=真我Neo8"},{"title":"小米17 Max","url":"/page?url=V9_SEARCH_PHONE&key=小米17+Max"},{"title":"iPhone 16 Pro","url":"/page?url=V9_SEARCH_PHONE&key=iPhone+16+Pro"},{"title":"一加13","url":"/page?url=V9_SEARCH_PHONE&key=一加13"},{"title":"OPPO Find X8","url":"/page?url=V9_SEARCH_PHONE&key=OPPO+Find+X8"}]}],"hot":[{"entityTemplate":"iconLinkGridCard","entityType":"card","entities":[{"title":"周榜","url":"#/feed/rankList?type=weekly"},{"title":"月榜","url":"#/feed/rankList?type=monthly"},{"title":"收藏榜","url":"#/feed/rankList?type=favorite"},{"title":"酷安指数","url":"/t/酷安指数"},{"title":"酷图榜","url":"#/feed/coolPictureRankList"}]},{"entityTemplate":"iconMiniGridCard","entityType":"card","entities":[{"title":"荣耀Magic7","tag":"荣耀Magic7","pic":"","url":"/t/荣耀Magic7","targetType":"topic"},{"title":"周鸿祎","tag":"周鸿祎","pic":"","url":"/t/周鸿祎","targetType":"topic"},{"title":"华为Mate70","tag":"华为Mate70","pic":"","url":"/t/华为Mate70","targetType":"topic"},{"title":"百瓦快充","tag":"百瓦快充","pic":"","url":"/t/百瓦快充","targetType":"topic"},{"title":"苹果优惠","tag":"苹果","pic":"","url":"/t/苹果","targetType":"topic"},{"title":"鸿蒙NEXT","tag":"鸿蒙NEXT","pic":"","url":"/t/鸿蒙NEXT","targetType":"topic"}]},{"entityTemplate":"capsuleListCard","entityType":"card","entities":[{"title":"薅羊毛"},{"title":"酷安小编"},{"title":"二手"},{"title":"微信"},{"title":"徕卡一瞬"},{"title":"一加13"},{"title":"shizuku"},{"title":"临时root"},{"title":"一加"},{"title":"iqoo15"}]},{"entityTemplate":"selectorLinkCard","entityType":"card","entities":[{"title":"今日热门","url":"/page?url=V9_HOME_TAB_HOT"},{"title":"手机","url":"/page?url=V9_HOME_TAB_HOT_PHONE"},{"title":"系统","url":"/page?url=V9_HOME_TAB_HOT_SYSTEM"},{"title":"平板","url":"/page?url=V9_HOME_TAB_HOT_PAD"},{"title":"耳机","url":"/page?url=V9_HOME_TAB_HOT_EARPHONE"},{"title":"穿戴","url":"/page?url=V9_HOME_TAB_HOT_WEAR"}]}],"tutorial":[{"entityTemplate":"image_1","entityType":"card","title":"全站教程精选","description":"酷安教程中心，收录各类玩机技巧。欢迎各位@全站教程精选 投送优质教程。","pic":""},{"entityTemplate":"selectorLinkCard","entityType":"card","entities":[{"title":"全部","url":"/page?url=V9_TUTORIAL_ALL"},{"title":"进阶","url":"/page?url=V9_TUTORIAL_ADVANCED"},{"title":"苹果","url":"/page?url=V9_TUTORIAL_APPLE"},{"title":"PC","url":"/page?url=V9_TUTORIAL_PC"},{"title":"数码生活","url":"/page?url=V9_TUTORIAL_DIGITAL"}]}],"video":[{"entityTemplate":"iconMiniLinkGridCard","entityType":"card","entities":[{"title":"最新发布","url":"/page?url=V9_HOME_TAB_SHIPIN_LATEST"},{"title":"热门视频","url":"/page?url=V9_HOME_TAB_SHIPIN_HOT"},{"title":"发视频","url":"#/feed/create"}]}]}""")
internal fun homeHeaderDefaults(channel: String): List<JSONObject> = homeHeaderDefaults.optJSONArray(channel).objects().map { JSONObject(it.toString()) }
private fun headerFirst(row: JSONObject, vararg keys: String): String = keys.firstNotNullOfOrNull { row.opt(it)?.takeUnless { value -> value === JSONObject.NULL }?.toString() }.orEmpty()
private fun headerType(row: JSONObject): String = headerFirst(row, "entityTemplate", "entity_template").ifEmpty { headerFirst(row, "entityType", "entity_type", "type") }
private fun headerSelectionType(row: JSONObject): String = headerFirst(row, "entityTemplate", "entityType")
internal data class HomeHeaderPart(val kind: String, val cards: List<JSONObject>)
internal fun homeHeaderParts(channel: String, cards: List<JSONObject>): List<HomeHeaderPart> {
    val filtered = cards.filter { row -> val type = headerType(row); val entities = row.optJSONArray("entities")
        type != "feed" && !(entities != null && entities.length() == 0 && !type.contains("banner") && type != "image_1") }
    val defaults = homeHeaderDefaults(channel)
    fun part(kind: String, fallback: String, match: (String) -> Boolean): HomeHeaderPart {
        val found = filtered.filter { match(headerSelectionType(it)) }
        return HomeHeaderPart(kind, (if (found.isEmpty()) defaults.filter { headerSelectionType(it) == fallback } else found).let { if (kind == "carousel") it else it.take(1) })
    }
    return when(channel) {
        "headline" -> listOf(part("carousel", "imageCarouselCard_1") { it.startsWith("imageCarousel") || it.startsWith("imageSquare") || it in setOf("image_1", "banner") },
            part("iconPages", "iconLinkGridCard") { it in setOf("iconLinkGridCard", "iconGridCard") }, part("mini", "iconMiniScrollCard") { it in setOf("iconMiniScrollCard", "miniScrollCard") })
        "hot" -> listOf(part("rank", "iconLinkGridCard") { it in setOf("iconLinkGridCard", "rankCard") }, part("news", "iconMiniGridCard") { it in setOf("iconMiniGridCard", "miniGridCard") },
            part("capsules", "capsuleListCard") { it in setOf("capsuleListCard", "capsuleCard") }, part("selector", "selectorLinkCard") { it in setOf("selectorLinkCard", "tabLinkCard") })
        "tutorial" -> listOf(part("tutorial", "image_1") { it == "image_1" || it.startsWith("imageCarousel") || it == "tutorialBanner" }, part("selector", "selectorLinkCard") { it in setOf("selectorLinkCard", "tabLinkCard") })
        "video" -> listOf(part("video", "iconMiniLinkGridCard") { it in setOf("iconMiniLinkGridCard", "videoFilterBar") })
        else -> filtered.mapNotNull { row -> val type=headerType(row); val kind=when {
            type.startsWith("imageCarouselCard") || type == "image_1" -> "carousel"
            type == "iconLinkGridCard" -> "rank"; type == "iconMiniScrollCard" -> "mini"; type == "iconMiniGridCard" -> "news"
            type == "capsuleListCard" -> "capsules"; type == "selectorLinkCard" -> "selector"; type == "iconMiniLinkGridCard" -> "video"; else -> return@mapNotNull null }
            HomeHeaderPart(kind, listOf(row)) }
    }
}
private fun headerItems(card: JSONObject, channel: String, index: Int) = card.optJSONArray("entities").objects().ifEmpty { homeHeaderDefaults(channel).getOrNull(index)?.optJSONArray("entities").objects() }
private fun headerImage(row: JSONObject) = headerFirst(row, "pic", "image", "cover")
internal fun homeCarouselItems(cards: List<JSONObject>): List<JSONObject> = cards.flatMap { row ->
    if (row.optJSONArray("entities") != null) row.optJSONArray("entities").objects() else if (headerImage(row).isNotEmpty()) listOf(row) else emptyList()
}.filter { headerImage(it).isNotEmpty() }.ifEmpty { homeHeaderDefaults("headline")[0].optJSONArray("entities").objects() }

@Composable
internal fun HomeFeedHeader(api: ContentApi, channelId: String, cards: List<JSONObject>, activeIndex: Int,
    onSelect: (JSONObject, Int) -> Unit, onOpen: (JSONObject) -> Unit) {
    val parts=remember(channelId,cards) { homeHeaderParts(channelId,cards) }
    val open: (JSONObject) -> Unit = { onOpen(todayHeadlineTarget(it)) }
    Column(Modifier.fillMaxWidth()) { parts.forEachIndexed { index, part -> key(index, part.kind) {
        val card = part.cards.firstOrNull() ?: JSONObject()
        when(part.kind) {
            "carousel" -> HomeCarousel(api,part.cards,open)
            "iconPages" -> HomeIconPages(api,card,open)
            "rank" -> HomeRankCard(api,card,open)
            "mini" -> HomeMiniScroll(api,card,open)
            "news" -> HomeNews(api,card,open)
            "capsules" -> HomeCapsules(card) { query -> onOpen(JSONObject().put("_composeHeadlineTarget",true).put("title",query).put("url","searchTab://search?key="+URLEncoder.encode(query,"UTF-8"))) }
            "selector" -> HomeSelector(card,activeIndex,onSelect)
            "tutorial" -> HomeTutorial(api,card)
            "video" -> HomeVideoFilter(card, { item -> open(item) }, { url -> onSelect(JSONObject().put("url",url).put("title",if(channelId=="video")"视频筛选" else "筛选"),0) })
        }
    } } }
}

@Composable
private fun rememberHeaderSelection(action:()->Unit):()->Unit {
    val view=LocalView.current;val enabled=com.green.note.ui.LocalAppPreferences.current.haptics
    return { com.green.note.ui.AppHaptics.selection(view,enabled);action() }
}
@Composable
private fun HeaderImage(api: ContentApi, url: String, modifier: Modifier, scale: ContentScale, fallback: @Composable () -> Unit) {
    var failed by remember(url,api.imageCacheScope()) { mutableStateOf(false) }
    Box(modifier,contentAlignment=Alignment.Center) {
        if(url.isEmpty() || failed) fallback() else ContentImage(api,url,null,Modifier.fillMaxSize(),scale=scale,onError={failed=true})
    }
}
@Composable
private fun HeaderCard(content: @Composable ColumnScope.()->Unit) {
    val scheme=MaterialTheme.colorScheme; val dark=scheme.surface.luminance()<.5f
    val color=if(dark) { if(com.green.note.ui.LocalAppPreferences.current.pureBlackDark) Color(0xff121212) else Color(0xff1b1c20) } else scheme.surfaceContainerLowest
    Surface(Modifier.fillMaxWidth().padding(horizontal=10.dp,vertical=4.dp),shape=RoundedCornerShape(16.dp),color=color,shadowElevation=1.dp) { Column(content=content) }
}

@Composable
private fun HomeCarousel(api: ContentApi,cards:List<JSONObject>,onOpen:(JSONObject)->Unit) {
    val items=remember(cards){homeCarouselItems(cards)}
    val signature=items.map { Triple(headerImage(it),headerFirst(it,"url"),headerFirst(it,"title")) }
    key(signature) {
        val count=items.size;val total=if(count>1)count*10000 else 1
        val pager=rememberPagerState(initialPage=if(count>1)count*5000 else 0,pageCount={total})
        val lifecycle=LocalLifecycleOwner.current.lifecycle
        val preparation=LocalTopicPreparation.current
        val scope=rememberCoroutineScope();var launching by remember { mutableStateOf(false) }
        WarmCurrentTopic(items[pager.currentPage%count])
        LaunchedEffect(pager,lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            launching=false
            if(count>1) while(true) {
                snapshotFlow{pager.isScrollInProgress}.first{!it}
                val interrupted=withTimeoutOrNull(5000){snapshotFlow{pager.isScrollInProgress}.first{it}}
                if(interrupted==null && pager.currentPage+1<total) pager.animateScrollToPage(pager.currentPage+1,animationSpec=tween(420,easing=CubicBezierEasing(.215f,.61f,.355f,1f)))
            } else awaitCancellation()
        } }
        Box(Modifier.fillMaxWidth().padding(horizontal=10.dp,vertical=4.dp).aspectRatio(4.35f)) {
            HorizontalPager(pager,Modifier.fillMaxSize()) { page -> val item=items[page%count]
                HeaderImage(api,headerImage(item),Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)).clickable(onClick=rememberHeaderSelection {
                    if(!launching) { launching=true;val tag=carouselTopicTag(item);if(tag.isNotEmpty())preparation?.prepare(tag);onOpen(item)
                        scope.launch { delay(300);if(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))launching=false }
                    }
                }),ContentScale.Crop) { Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha=.12f)),contentAlignment=Alignment.Center){MaterialGlyph("broken_image_outlined")} }
            }
            if(count>1) Row(Modifier.align(Alignment.BottomEnd).padding(end=12.dp,bottom=8.dp)) { repeat(count) { index ->
                Box(Modifier.padding(start=4.dp).size(5.5.dp).background(Color.White.copy(alpha=if(index==pager.currentPage%count)1f else .45f),CircleShape))
            } }
        }
    }
}

@Composable
private fun HomeIconPages(api:ContentApi,card:JSONObject,onOpen:(JSONObject)->Unit) {
    val items=headerItems(card,"headline",1);val count=((items.size+4)/5).coerceIn(1,4);val pager=rememberPagerState(pageCount={count});val scheme=MaterialTheme.colorScheme
    Column(Modifier.padding(horizontal=10.dp,vertical=4.dp),horizontalAlignment=Alignment.CenterHorizontally) {
        HorizontalPager(pager,Modifier.fillMaxWidth().height(66.dp)) { page ->
            Row(Modifier.fillMaxSize(),verticalAlignment=Alignment.CenterVertically) { repeat(5) { offset -> val item=items.getOrNull(page*5+offset)
                if(item==null)Spacer(Modifier.weight(1f)) else Column(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).clickable(onClick=rememberHeaderSelection{onOpen(item)}).padding(vertical=2.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
                    val title=headerFirst(item,"title");val pic=headerFirst(item,"pic","icon","logo").takeUnless{it.endsWith(".gif")}.orEmpty()
                    HeaderImage(api,pic,Modifier.size(36.dp),ContentScale.Fit) { SolidHeaderIcon(title) }
                    Spacer(Modifier.height(3.dp));Text(title,fontSize=11.5.sp,fontWeight=adjustedWeight(500),color=scheme.onSurface,maxLines=1,overflow=TextOverflow.Ellipsis)
                }
            } }
        }
        if(count>1) { Spacer(Modifier.height(3.dp));Row { repeat(2) { index ->
            val width by animateDpAsState(if(pager.currentPage==index)10.dp else 5.dp,tween(200,easing=LinearEasing),label="header-page-width")
            val color by animateColorAsState(if(pager.currentPage==index)scheme.primary else scheme.onSurfaceVariant.copy(alpha=.35f),tween(200,easing=LinearEasing),label="header-page-color")
            Box(Modifier.padding(horizontal=1.5.dp).size(width,2.5.dp).background(color,RoundedCornerShape(1.5.dp)))
        } };Spacer(Modifier.height(2.dp)) }
    }
}
@Composable
private fun SolidHeaderIcon(title:String) {
    val (name,color)=when {
        title.contains("值得看")->"verified_rounded" to Color(0xff2979ff)
        title.contains("热闻")||title.contains("新闻")->"article_rounded" to Color(0xffff9800)
        title.contains("活动")->"local_activity_rounded" to Color(0xffff4d4d)
        title.contains("AI")->"smart_toy_rounded" to Color(0xff00b0ff)
        title.contains("摄影")->"face_rounded" to Color(0xff00e5ff)
        title.contains("选机")->"phone_android_rounded" to Color(0xff7c4dff)
        title.contains("玩机")||title.contains("大神")->"psychology_rounded" to Color(0xffff4081)
        title.contains("投票")->"how_to_vote_rounded" to Color(0xff536dfe)
        title.contains("榜")->"leaderboard_rounded" to Color(0xffff6d00)
        title.contains("频道")->"campaign_rounded" to Color(0xff00c853)
        else->"apps_rounded" to MaterialTheme.colorScheme.primary
    }
    Box(Modifier.size(36.dp).background(color,CircleShape),contentAlignment=Alignment.Center){MaterialGlyph(name,size=20.dp,color=Color.White)}
}
private fun rankFallback(title:String):Pair<String,Color> = when {
    title.contains("周榜")->"thumb_up_rounded" to Color(0xffff5252);title.contains("月榜")->"chat_bubble_rounded" to Color(0xff00e5ff)
    title.contains("收藏")->"star_rounded" to Color(0xffffb300);title.contains("指数")->"show_chart_rounded" to Color(0xff7c4dff)
    title.contains("图")->"bar_chart_rounded" to Color(0xffff6d00);else->"bar_chart_rounded" to Color(0xffff9800)
}
@Composable
private fun HomeRankCard(api:ContentApi,card:JSONObject,onOpen:(JSONObject)->Unit) {
    val items=card.optJSONArray("entities").objects().ifEmpty { listOf("周榜" to "V9_WEEK_RANK","月榜" to "V9_MONTH_RANK","收藏榜" to "V9_FAV_RANK","酷安指数" to "V9_COOL_INDEX","酷图榜" to "V9_COOL_PICTURE_RANK").map{JSONObject().put("title",it.first).put("url","/page?url="+it.second)} }
    HeaderCard { Row(Modifier.fillMaxWidth().padding(horizontal=6.dp,vertical=12.dp)) { items.take(5).forEach { item ->
        val title=headerFirst(item,"title");val pic=headerFirst(item,"pic","icon","logo").takeUnless{it.endsWith(".gif")}.orEmpty()
        Column(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).clickable(onClick=rememberHeaderSelection{onOpen(item)}),horizontalAlignment=Alignment.CenterHorizontally) {
            HeaderImage(api,pic,Modifier.size(36.dp),ContentScale.Fit) { val (name,color)=rankFallback(title);MaterialGlyph(name,size=36.dp,color=color) }
            Spacer(Modifier.height(6.dp));Text(title,fontSize=12.sp,fontWeight=adjustedWeight(500),color=MaterialTheme.colorScheme.onSurface,maxLines=1,overflow=TextOverflow.Ellipsis)
        }
    } } }
}
@Composable
private fun HomeMiniScroll(api:ContentApi,card:JSONObject,onOpen:(JSONObject)->Unit) {
    val scheme=MaterialTheme.colorScheme
    LazyRow(Modifier.padding(vertical=4.dp).fillMaxWidth().height(28.dp),contentPadding=PaddingValues(horizontal=10.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
        items(headerItems(card,"headline",2)) { item ->
            Row(Modifier.fillMaxHeight().clip(RoundedCornerShape(14.dp)).background(scheme.surfaceContainerHighest.copy(alpha=.45f)).border(.6.dp,scheme.outlineVariant.copy(alpha=.25f),RoundedCornerShape(14.dp))
                .clickable(onClick=rememberHeaderSelection{onOpen(item)}).padding(.6.dp).padding(horizontal=8.dp,vertical=2.dp),verticalAlignment=Alignment.CenterVertically) {
                val pic=headerFirst(item,"pic","icon","logo")
                if(pic.isEmpty())MaterialGlyph("phone_android_rounded",size=13.dp,color=scheme.primary) else HeaderImage(api,pic,Modifier.size(14.dp).clip(RoundedCornerShape(4.dp)),ContentScale.Crop){MaterialGlyph("phone_android_rounded",size=13.dp,color=scheme.primary)}
                Spacer(Modifier.width(5.dp));Text(headerFirst(item,"title"),fontSize=11.5.sp,fontWeight=adjustedWeight(500),color=scheme.onSurface)
            }
        }
    }
}

internal fun homeNewsImage(row:JSONObject):String {
    for(key in listOf("pic","logo","icon","image","cover","tagLogo","tag_logo","tagPic","tag_pic","subPic","sub_pic","userAvatar","user_avatar","userSmallAvatar")) row.text(key).trim().takeIf{it.isNotEmpty()&&!it.endsWith(".gif")}?.let{return it}
    for(nested in listOf(row.optJSONObject("target_row")?:row.optJSONObject("targetRow"),row.optJSONObject("extraData")?:row.optJSONObject("extra_data"))) {
        for(key in listOf("pic","logo","icon","image","cover","tagLogo")) nested?.text(key)?.trim()?.takeIf{it.isNotEmpty()&&!it.endsWith(".gif")}?.let{return it}
    };return ""
}
private fun decodeHeader(value:String)=runCatching{URLDecoder.decode(value.replace("+","%2B"),"UTF-8")}.getOrDefault(value)
private fun headerQueryTag(url:String):String=runCatching{URI(if(url.startsWith('/'))"https://coolapk.com"+url else url).rawQuery.orEmpty().split('&').firstOrNull{it.substringBefore('=')=="tag"}?.substringAfter('=')?.let{URLDecoder.decode(it,"UTF-8")}.orEmpty()}.getOrDefault("")
internal fun homeNewsTitle(row:JSONObject,index:Int):String {
    var title=headerFirst(row,"title","entityTitle","tag","name","text","subTitle").trim()
    if(title.isEmpty()){val url=headerFirst(row,"url","href");title=when{url.contains("/t/")->decodeHeader(url.substringAfter("/t/").substringBefore('?').substringBefore('/'));url.contains("tag=")->headerQueryTag(url);else->""}}
    return title.ifEmpty{homeHeaderDefaults("hot")[1].optJSONArray("entities").objects().getOrNull(index)?.text("title").orEmpty()}
}
internal fun homeNewsTag(row:JSONObject,title:String):String {
    fun clean(s:String)=s.replace("#","").trim()
    headerFirst(row,"tag","target_tag","topic").trim().takeIf{it.isNotEmpty()}?.let{return clean(it)}
    val url=headerFirst(row,"url","href","target_url").trim()
    if(url.contains("/t/"))decodeHeader(url.substringAfter("/t/").substringBefore('?').substringBefore('/')).takeIf{it.isNotEmpty()}?.let{return clean(it)}
    if(url.contains("tag="))headerQueryTag(url).takeIf{it.isNotEmpty()}?.let{return clean(it)}
    val target=row.optJSONObject("target_row")?:row.optJSONObject("targetRow")
    target?.let{headerFirst(it,"tag","title").trim() }?.takeIf{it.isNotEmpty()}?.let{return clean(it)}
    Regex("#([^#]+)#").find(title)?.groupValues?.get(1)?.let{return it.trim()}
    val text=clean(title)
    for(keyword in listOf("荣耀WIN2","荣耀Magic","荣耀","华为Mate","华为","苹果","iPhone","iPad","小米","Redmi","红米","OPPO","vivo","iQOO","一加","魅族","三星","周鸿祎","鸿蒙","快充","芯片","高通","联发科","英伟达","AI","手机","数码"))if(text.contains(keyword,ignoreCase=true))return keyword
    return if(text.length>6)text.take(4) else text
}
/** Dart VM's UTF-16 Jenkins String hash, checked against the retained Dart runtime. */
internal fun homeDartStringHash(value:String):Int {
    var hash=0
    for(char in value){hash+=char.code;hash+=hash shl 10;hash=hash xor (hash ushr 6)}
    hash+=hash shl 3;hash=hash xor (hash ushr 11);hash+=hash shl 15
    return hash and 0x3fffffff
}
private object HeaderTopicLogoCache {
    private var owner="";private val logos=linkedMapOf<String,String>()
    @Synchronized fun get(scope:String,tag:String):String { if(owner!=scope){owner=scope;logos.clear()};return logos[tag].orEmpty() }
    @Synchronized fun put(scope:String,tag:String,logo:String) { if(owner!=scope)return;logos.remove(tag);logos[tag]=logo;while(logos.size>128)logos.remove(logos.keys.first()) }
}
@Composable
private fun HomeNews(api:ContentApi,card:JSONObject,onOpen:(JSONObject)->Unit) {
    val items=headerItems(card,"hot",1).take(8);val owner=api.imageCacheScope();val lifecycle=LocalLifecycleOwner.current.lifecycle
    val resolved=remember(owner){mutableStateMapOf<String,String>()};val signature=items.map{it.toString()}
    LaunchedEffect(signature,owner,lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
        val gate=Semaphore(3)
        coroutineScope { items.mapIndexed { index,item -> homeNewsTag(item,homeNewsTitle(item,index)) to item }.distinctBy{it.first}.map { (tag,item) -> launch {
            if(tag.isEmpty())return@launch
            val cached=HeaderTopicLogoCache.get(owner,tag);val supplied=homeNewsImage(item)
            if(supplied.isNotEmpty()){HeaderTopicLogoCache.put(owner,tag,supplied);resolved[tag]=supplied;return@launch}
            if(cached.isNotEmpty()){resolved[tag]=cached;return@launch}
            try { gate.withPermit {
                val root=api.request("/v6/topic/newTagDetail",query=mapOf("tag" to tag));val detail=root.optJSONObject("data")?:root
                var logo=headerFirst(detail,"logo","icon","pic","avatar").trim()
                if(logo.isEmpty()){val search=api.request("/v6/search",query=mapOf("searchValue" to tag,"type" to "topic","page" to "1","sort" to "default","sortType" to "default","show_flag" to "1"));logo=parsePage(search,1).rows.firstOrNull()?.let{headerFirst(it,"logo","icon","pic","avatar").trim()}.orEmpty()}
                ensureActive();if(owner==api.imageCacheScope()&&logo.isNotEmpty()){HeaderTopicLogoCache.put(owner,tag,logo);resolved[tag]=logo}
            } } catch(cancelled:CancellationException){throw cancelled}catch(_:Exception){ /* Original per-icon failure keeps the colorful fallback. */ }
        } }.joinAll() };awaitCancellation()
    } }
    HeaderCard { Column(Modifier.padding(horizontal=12.dp,vertical=10.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        items.chunked(2).forEachIndexed { r,pair -> Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) { repeat(2) { col ->
            val item=pair.getOrNull(col)
            if(item==null)Spacer(Modifier.weight(1f)) else {
                val title=homeNewsTitle(item,r*2+col);val tag=homeNewsTag(item,title);val pic=homeNewsImage(item).ifEmpty{resolved[tag].orEmpty().ifEmpty{HeaderTopicLogoCache.get(owner,tag)}}
                val target=JSONObject(item.toString()).apply{if(headerFirst(this,"title").isEmpty())put("title",title);if(headerFirst(this,"tag").isEmpty())put("tag",tag.ifEmpty{title});if(pic.isNotEmpty()&&headerFirst(this,"pic").isEmpty()){put("pic",pic);put("logo",pic)}}
                Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable(onClick=rememberHeaderSelection{onOpen(target)}),verticalAlignment=Alignment.CenterVertically){
                    HeaderImage(api,pic,Modifier.size(26.dp).clip(RoundedCornerShape(6.dp)),ContentScale.Crop){HomeTopicFallback(title)}
                    Spacer(Modifier.width(8.dp));Text(title,Modifier.weight(1f),fontSize=12.5.sp,fontWeight=adjustedWeight(400),color=MaterialTheme.colorScheme.onSurface,maxLines=1,overflow=TextOverflow.Ellipsis)
                }
            }
        } } }
    } }
}
@Composable
private fun HomeTopicFallback(title:String) {
    val colors=listOf(0xff00b0ff,0xff00e676,0xffff5252,0xffff9100,0xff7c4dff,0xffff4081,0xff00bfa5,0xffffab00)
    val color=Color(colors[homeDartStringHash(title)%8]);val clean=title.replace("#","").trim();val first=clean.take(1).ifEmpty{"#"};val text=if(first[0] in 'a'..'z'||first[0] in 'A'..'Z'||first[0] in '0'..'9')first.uppercase()else first
    Box(Modifier.size(26.dp).background(color.copy(alpha=.12f),RoundedCornerShape(6.dp)).border(.8.dp,color.copy(alpha=.35f),RoundedCornerShape(6.dp)),contentAlignment=Alignment.Center){Text(text,fontSize=12.sp,lineHeight=13.2.sp,fontWeight=adjustedWeight(800),color=color)}
}
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HomeCapsules(card:JSONObject,onSearch:(String)->Unit) {
    HeaderCard { FlowRow(Modifier.fillMaxWidth().padding(horizontal=12.dp,vertical=10.dp),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        headerItems(card,"hot",2).forEach { item ->val title=headerFirst(item,"title")
            Text(title,Modifier.clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha=.5f)).clickable(onClick=rememberHeaderSelection{onSearch(title)}).padding(horizontal=12.dp,vertical=6.dp),fontSize=12.sp,fontWeight=adjustedWeight(400),color=MaterialTheme.colorScheme.onSurface)
        }
    } }
}
@Composable
private fun HomeSelector(card:JSONObject,active:Int,onSelect:(JSONObject,Int)->Unit) {
    val items=card.optJSONArray("entities").objects();if(items.isEmpty())return;val scheme=MaterialTheme.colorScheme
    LazyRow(Modifier.padding(vertical=4.dp).height(38.dp).fillMaxWidth(),contentPadding=PaddingValues(horizontal=10.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
        items(items.size) { index -> val selected=index==active
            val color by animateColorAsState(if(selected)scheme.primary else scheme.surfaceContainerHighest.copy(alpha=.35f),tween(200,easing=LinearEasing),label="selector-color")
            val border by animateColorAsState(if(selected)Color.Transparent else scheme.outlineVariant.copy(alpha=.2f),tween(200,easing=LinearEasing),label="selector-border")
            Box(Modifier.fillMaxHeight().clip(RoundedCornerShape(19.dp)).background(color).border(.6.dp,border,RoundedCornerShape(19.dp)).clickable(onClick=rememberHeaderSelection{onSelect(items[index],index)}).padding(horizontal=14.dp,vertical=6.dp),contentAlignment=Alignment.Center) {
                Text(headerFirst(items[index],"title"),fontSize=13.sp,fontWeight=adjustedWeight(if(selected)700 else 400),color=if(selected)scheme.onPrimary else scheme.onSurface)
            }
        }
    }
}
@Composable
private fun HomeTutorial(api:ContentApi,card:JSONObject) {
    val image=headerImage(card).ifEmpty{card.optJSONArray("entities").objects().firstOrNull()?.let{headerFirst(it,"pic","image")}.orEmpty()}
    val description=headerFirst(card,"description","subTitle").let{if(card.has("description")||card.has("subTitle"))it else "酷安教程中心，收录各类玩机技巧。欢迎各位@全站教程精选 投送优质教程。"}
    HeaderCard {
        HeaderImage(api,image,Modifier.fillMaxWidth().aspectRatio(3.2f).clip(RoundedCornerShape(topStart=16.dp,topEnd=16.dp)),ContentScale.Crop) {
            Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xff00b4d8),Color(0xff48cae4),Color(0xff90e0ef)))),contentAlignment=Alignment.Center) {
                Column(horizontalAlignment=Alignment.CenterHorizontally) {
                    Text("全站教程精选",Modifier.background(Color.White.copy(alpha=.9f),RoundedCornerShape(8.dp)).padding(horizontal=14.dp,vertical=4.dp),fontSize=20.sp,fontWeight=adjustedWeight(900),color=Color(0xff0077b6))
                    Spacer(Modifier.height(6.dp));Text("收获玩机乐趣",Modifier.background(Color(0xff0077b6),RoundedCornerShape(12.dp)).padding(horizontal=10.dp,vertical=2.dp),fontSize=11.sp,fontWeight=adjustedWeight(700),color=Color.White)
                }
            }
        }
        Text(description,Modifier.padding(start=14.dp,top=10.dp,end=14.dp,bottom=12.dp),fontSize=13.sp,lineHeight=18.2.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable
private fun HomeVideoFilter(card:JSONObject,onOpen:(JSONObject)->Unit,onFilter:(String)->Unit) {
    HeaderCard { Row(Modifier.fillMaxWidth().padding(horizontal=12.dp,vertical=10.dp),horizontalArrangement=Arrangement.SpaceAround,verticalAlignment=Alignment.CenterVertically) {
        headerItems(card,"video",0).take(3).forEach { item ->val title=headerFirst(item,"title")
            val (icon,color)=when{title.contains("最新")->"explore_rounded" to Color(0xff7c4dff);title.contains("热门")->"local_fire_department_rounded" to Color(0xffff9100);title.contains("发视频")||title.contains("发布")->"videocam_rounded" to Color(0xffff5252);else->"play_circle_outline_rounded" to LocalContentColor.current}
            Row(Modifier.clip(RoundedCornerShape(20.dp)).clickable(onClick=rememberHeaderSelection{if(title.contains("发视频"))onOpen(JSONObject(item.toString()).put("url","#/feed/create"))else headerFirst(item,"url").takeIf{it.isNotEmpty()}?.let(onFilter)}).padding(horizontal=10.dp,vertical=4.dp),verticalAlignment=Alignment.CenterVertically){
                MaterialGlyph(icon,size=18.dp,color=color);Spacer(Modifier.width(6.dp));Text(title,fontSize=13.sp,fontWeight=adjustedWeight(600),color=MaterialTheme.colorScheme.onSurface)
            }
        }
    } }
}
