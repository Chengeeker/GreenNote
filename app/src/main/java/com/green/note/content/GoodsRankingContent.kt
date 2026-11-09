package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.*
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.URI
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal fun rankingProduct(item:JSONObject):JSONObject = JSONObject(item.toString()).apply {
    (item.optJSONArray("extra_entities") ?: item.optJSONArray("extraEntities"))?.optJSONObject(0)?.let { extra->extra.keys().forEach { put(it,extra.get(it)) } }
}
internal fun rankingInfo(data:JSONObject):JSONObject = JSONObject(data.toString()).apply {
    data.optJSONObject("goodsListInfo")?.let { extra->extra.keys().forEach { put(it,extra.get(it)) } }
}
internal fun rankingFlag(value:Any?):Boolean=value?.toString() in setOf("true","1")
internal fun rankingBuyUrl(product:JSONObject):String = product.text("product_goods_url","goods_buy_url","goods_url","sell_url","url").takeIf { raw->
    runCatching { val uri=URI(raw);uri.scheme?.lowercase() in setOf("http","https") && !uri.host.isNullOrEmpty() && uri.rawUserInfo.isNullOrEmpty() }.getOrDefault(false)
}.orEmpty()
internal fun rankingVote(item:JSONObject):Pair<Boolean,Long> {
    val vote=item.optJSONObject("goodsListInfo")
    return rankingFlag(vote?.opt("is_vote") ?: item.opt("isVote") ?: item.opt("is_vote")) to
        (vote?.text("vote_num") ?: item.text("vote_num")).toLongOrNull().let{it?:0L}
}
internal fun rankingApplyVote(item:JSONObject):JSONObject = JSONObject(item.toString()).apply {
    val (selected,count)=rankingVote(item);val next=(count+if(selected)-1 else 1).coerceIn(0,1L shl 31)
    put("isVote",if(selected)0 else 1);put("vote_num",next)
    optJSONObject("goodsListInfo")?.apply {put("is_vote",if(selected)0 else 1);put("vote_num",next)}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun GoodsRankingContent(api:ContentApi,data:JSONObject,complete:Boolean,error:String?,onReload:suspend()->Unit,
    onVerify:(suspend()->Unit)?=null,onComments:()->Unit,onUser:(String)->Unit,onLink:(String)->Unit) {
    var local by remember(data) { mutableStateOf(JSONObject(data.toString())) }
    val info=rankingInfo(local);val id=local.text("id","feed_id")
    val items=local.optJSONArray("goodsListItem").objects()
    val session=LocalContentSession.current;val owner=remember {api.imageCacheScope()}
    val scope=rememberCoroutineScope();val context=LocalContext.current
    val busy=remember {mutableStateMapOf<String,Boolean>()}
    var refresh by remember {mutableStateOf(false)}
    var editor by remember {mutableStateOf<String?>(null)}
    var draft by rememberSaveable {mutableStateOf("")}
    var picker by remember {mutableStateOf(false)}
    var recommendation by remember {mutableStateOf<JSONObject?>(null)}
    val theme=MaterialTheme.colorScheme;val dark=theme.surface.red+theme.surface.green+theme.surface.blue<1.5f
    val card=if(dark)Color(0xFF1E1E1E) else theme.surfaceContainerLow
    val bottom=WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val toolbarHeight=(44f+(LocalDensity.current.fontScale*12-12).coerceIn(0f,24f)).dp
    fun toast(message:String){AppToastState().showSnackbar(message)}
    fun authenticated():Boolean { if(!session.authenticated){toast("请先使用酷安账号登录");return false};if(owner!=api.imageCacheScope()){toast("账号已切换，请重新打开榜单");return false};return true }
    fun write(key:String,action:suspend()->Unit) {
        if(busy[key]==true || !authenticated())return
        busy[key]=true
        scope.launch { try { check(owner==api.imageCacheScope()){ "账号已切换，请重新打开榜单" };action() }
            catch(cancelled:CancellationException){throw cancelled}
            catch(failure:Exception){toast(failure.message?:"操作失败")}
            finally{busy.remove(key)} }
    }
    fun reload(){if(refresh)return;refresh=true;scope.launch {try{onReload()}catch(cancelled:CancellationException){throw cancelled}catch(failure:Exception){toast(failure.message?:"加载失败")}finally{refresh=false}}}
    fun invite(){(context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("榜单邀请","${info.text("title")}\nhttps://www.coolapk.com/feed/$id"));toast("邀请链接已复制，可发送给酷友")}
    fun toggle(favorite:Boolean){val key=if(favorite)"collect" else "like";write(key){
        val selected=rankingFlag(local.optJSONObject("userAction")?.opt(key))
        val action=if(favorite)if(selected)"unfavorite" else "favorite" else if(selected)"unlike" else "like"
        api.request("/v6/feed/$action","POST",query=mapOf("id" to id))
        check(owner==api.imageCacheScope()){ "账号已切换，请重新打开榜单" }
        local=JSONObject(local.toString()).apply {
            put("userAction",(optJSONObject("userAction")?:JSONObject()).put(key,if(selected)0 else 1))
            if(favorite)put("goodsListInfo",rankingInfo(this).apply{put("fav_num",(optLong("fav_num")+if(selected)-1 else 1).coerceIn(0,1L shl 31))})
            else put("likenum",(optLong("likenum")+if(selected)-1 else 1).coerceIn(0,1L shl 31))
        }
    }}
    fun comment(){if(authenticated()&&busy["comment"]!=true)editor="comment"}
    fun recommend(){if(authenticated()&&busy["recommend"]!=true)picker=true}
    Box(Modifier.fillMaxSize()) {
    GlassBackdropHost(Modifier.fillMaxSize(),content={
        ReviewRefreshBox(refresh,::reload,Modifier.fillMaxSize().background(com.green.note.ui.LocalScaffoldColor.current),failed=error!=null) {
            LazyColumn(Modifier.fillMaxSize(),state=com.green.note.ui.rememberReviewLazyListState(),contentPadding=PaddingValues(bottom=bottom+toolbarHeight+30.dp)) {
                item { Box {
                    val cover=info.text("cover")
                    if(cover.isNotEmpty())BlurredImage(cover,api.imageHeaders(cover),api.imageCacheScope(),Modifier.matchParentSize())
                    Column(Modifier.padding(start=18.dp,top=76.dp,end=18.dp,bottom=8.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                        Text(info.text("title").ifEmpty{local.text("title","message_title","entityTitle")},Modifier.fillMaxWidth(),fontSize=23.sp,fontWeight=FontWeight.Normal,textAlign=TextAlign.Center)
                        Spacer(Modifier.height(16.dp));ContentRichText(info.text("message","description"),secondary=true,onLink=onLink,lineHeight=24.sp,textAlign=TextAlign.Center)
                        Spacer(Modifier.height(28.dp));Row(verticalAlignment=Alignment.CenterVertically) {
                            if(local.text("username","userAvatar").isNotEmpty())ContentAvatar(api,local.text("userAvatar"),local.text("username"),21.dp){onUser(local.text("uid"))}
                            Spacer(Modifier.width(7.dp));Text(local.text("username"),fontSize=12.sp);Spacer(Modifier.width(10.dp))
                            val seconds=info.text("dateline").toLongOrNull()?:0L
                            val date=if(seconds>=31536000)SimpleDateFormat("yyyy-M-d",Locale.CHINA).format(Date(seconds*1000)) else ""
                            val metadata=listOfNotNull(date.takeIf{it.isNotEmpty()},if(info.has("item_num")||complete||items.isNotEmpty())"${info.opt("item_num")?:items.size}个好物" else null,if(info.has("vote_num")||complete)"${info.opt("vote_num")?:0}人投票" else null).joinToString(" · ")
                            Text(metadata,Modifier.weight(1f),fontSize=11.sp,textAlign=TextAlign.End)
                        }
                        Spacer(Modifier.height(10.dp));Row {
                            RankingAction("thumb_up_outlined",local.text("likenum").ifEmpty{"0"},{toggle(false)},rankingFlag(local.optJSONObject("userAction")?.opt("like")),enabled=busy["like"]!=true)
                            RankingAction("chat_bubble_outline",local.text("replynum").ifEmpty{"0"},onComments)
                            RankingAction("person_add_alt_outlined","邀请推荐",::invite)
                            RankingAction("add_box_outlined","我要推荐",::recommend,enabled=(rankingFlag(info.opt("is_allow_recommend_goods"))||local.text("uid")==session.uid)&&busy["recommend"]!=true)
                        }
                        if(error!=null){Spacer(Modifier.height(8.dp));Text(error,color=theme.error);if(!complete)Text("当前展示入口预览，完整榜单尚未加载",fontSize=12.sp)
                            if(onVerify!=null)com.green.note.ui.ReviewButton(onClick={scope.launch{onVerify()}},iconPadding=true){MaterialGlyph("verified_user_outlined");ReviewButtonIconGap();Text("完成验证并加载榜单")}
                            com.green.note.ui.ReviewTextButton(onClick=::reload,iconPadding=true){MaterialGlyph("refresh");ReviewButtonIconGap();Text("重新加载完整榜单")}
                        } else if(!complete)com.green.note.ui.ReviewLinearProgress(Modifier.fillMaxWidth())
                    }
                } }
                itemsIndexed(items,key={index,item->"${item.text("id","feed_id")}:$index"}) {index,item->
                    val itemId=item.optJSONObject("goodsListInfo")?.text("item_id").orEmpty().ifEmpty{item.text("id","feed_id")}
                    RankingItem(api,item,index+1,card,rankingFlag(info.opt("is_open_vote"))&&itemId.isNotEmpty()&&busy[itemId]!=true,onUser,onLink) {write(itemId){
                        val selected=rankingVote(item).first
                        api.request("/v6/goodsList/vote","POST",body=mapOf("id" to info.text("id").ifEmpty{id},"item_id" to itemId,"value" to if(selected)"-1" else "1"))
                        check(owner==api.imageCacheScope()){ "账号已切换，请重新打开榜单" }
                        local=JSONObject(local.toString()).apply{optJSONArray("goodsListItem")?.put(index,rankingApplyVote(item))}
                    }}
                }
                item {Text(if(complete)"已显示榜单全部好物" else "完整榜单加载后显示更多好物",Modifier.fillMaxWidth().padding(16.dp),textAlign=TextAlign.Center)}
            }
        }
    },overlay={
        Box(Modifier.fillMaxSize(),contentAlignment=Alignment.BottomCenter) {
            Row(Modifier.padding(start=20.dp,end=20.dp,bottom=20.dp+bottom).fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                RankingCapsule(Modifier.weight(9f),toolbarHeight,card) {
                    Row(Modifier.fillMaxSize().clickable(onClick=rememberHapticClick(::comment)).padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically) {
                        val color=if(dark)Color(0xFFCCCCCC) else theme.onSurface
                        MaterialGlyph("drive_file_rename_outline",size=20.dp,color=color);Spacer(Modifier.width(4.dp));Text("写评论",fontSize=14.sp,fontWeight=FontWeight.Normal,color=color)
                    }
                }
                RankingCapsule(Modifier.weight(12f),toolbarHeight,card) {Row(Modifier.fillMaxSize().padding(horizontal=12.dp),verticalAlignment=Alignment.CenterVertically) {
                    RankingAction("thumb_up_outlined",local.text("likenum").ifEmpty{"0"},{toggle(false)},rankingFlag(local.optJSONObject("userAction")?.opt("like")),true,busy["like"]!=true)
                    RankingAction("chat_bubble_outline",local.text("replynum").ifEmpty{"0"},onComments,compact=true)
                    RankingAction("star_border_rounded",info.text("fav_num").ifEmpty{"0"},{toggle(true)},rankingFlag(local.optJSONObject("userAction")?.opt("collect")),true,busy["collect"]!=true)
                    RankingAction("refresh_rounded",local.text("forwardnum").ifEmpty{"0"},::invite,compact=true)
                }}
            }
        }
    })
    StackedRoutes(if(picker)listOf("ranking-goods-picker") else emptyList(),{picker=false}) {
        RankingGoodsPicker(api,{picker=false}) {recommendation=it;picker=false;editor="recommend"}
    }
    editor?.let {mode->RankingEditor(if(mode=="comment")"写评论" else "推荐好物",if(mode=="comment")"内容" else "推荐理由",if(mode=="comment")draft else "",if(mode=="comment")10000 else 1000,{editor=null}) {value->
        editor=null;if(mode=="comment"){draft=value;write("comment"){api.request("/v6/feed/reply","POST",body=mapOf("id" to id,"type" to "feed","message" to draft));check(owner==api.imageCacheScope()){ "账号已切换，请重新打开榜单" };draft="";toast("评论已发送");onReload()}}
        else recommendation?.let {goods->write("recommend"){api.request("/v6/goodsList/addGoods","POST",body=mapOf("feedId" to info.text("id").ifEmpty{id},"goodsId" to goods.text("id","entityId"),"note" to value,"pic" to goods.text("product_goods_cover","goods_pic","pic")));check(owner==api.imageCacheScope()){ "账号已切换，请重新打开榜单" };toast("已提交推荐");onReload()}}
    }}
    }
}

@Composable
private fun RowScope.RankingAction(icon:String,label:String,onClick:()->Unit,selected:Boolean=false,compact:Boolean=false,enabled:Boolean=true) {
    val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    val color=if(selected)scheme.primary else if(compact)if(dark)Color.White else scheme.onSurface else scheme.onSurfaceVariant
    Column(Modifier.weight(1f).heightIn(min=if(compact)44.dp else 48.dp).clickable(enabled=enabled,onClick=rememberHapticClick(onClick)).padding(horizontal=4.dp,vertical=if(compact)3.dp else 10.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
        if(compact&&icon=="chat_bubble_outline")RankingCommentGlyph(color,Modifier.size(22.dp)) else MaterialGlyph(icon,size=if(compact)22.dp else 25.dp,color=if(enabled)color else color.copy(alpha=.38f))
        if(!compact)Spacer(Modifier.height(4.dp))
        Text(label,fontSize=if(compact)10.sp else 12.sp,lineHeight=if(compact)10.sp else 14.sp,fontWeight=FontWeight.Normal,maxLines=1,color=if(compact&&dark&&!selected)Color(0xFFCCCCCC) else color)
    }
}

@Composable
private fun RankingCapsule(modifier:Modifier,height:androidx.compose.ui.unit.Dp,color:Color,content:@Composable BoxScope.()->Unit) {
    if(LocalAppPreferences.current.liquidGlassNavBar)GlassSurface(modifier.height(height),28.dp,liquid=true,interactive=false,material=GlassMaterial.NAVIGATION,content=content)
    else Box(modifier.height(height).clip(RoundedCornerShape(28.dp)).background(color).border(.7.dp,MaterialTheme.colorScheme.outlineVariant.copy(alpha=.4f),RoundedCornerShape(28.dp)),content=content)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RankingItem(api:ContentApi,item:JSONObject,rank:Int,card:Color,enabled:Boolean,onUser:(String)->Unit,onLink:(String)->Unit,onVote:()->Unit) {
    val product=rankingProduct(item);val link=rankingBuyUrl(product);val note=item.text("note","message");val source=item.optJSONObject("userInfo")?:JSONObject()
    val (voted,count)=rankingVote(item)
    Column(Modifier.padding(start=10.dp,top=6.dp,end=10.dp,bottom=3.dp).fillMaxWidth().background(card,RoundedCornerShape(15.dp)).padding(13.dp)) {
        Row(Modifier.fillMaxWidth().clickable(enabled=link.isNotEmpty(),onClick=rememberHapticClick{onLink(link)}),verticalAlignment=Alignment.Top) {
            Box(Modifier.size(100.dp)) {
                val image=product.text("product_goods_cover","product_goods_logo","cover","logo","goods_pic","pic")
                if(image.isNotEmpty())CardImage(api,image,Modifier.fillMaxSize(),radius=10.dp) else Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){MaterialGlyph("shopping_bag_outlined")}
                RankingMedal(rank,Modifier.offset((-5).dp,(-9).dp))
            }
            Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)) {
                Text(product.text("product_goods_title","productGoodsTitle","goods_title","title"),maxLines=3,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.titleMedium.copy(lineHeight=22.4.sp))
                Spacer(Modifier.height(14.dp));FlowRow(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                    val price=product.text("price","product_goods_price","goods_price");if(price.isNotEmpty())Text(if(price.startsWith("¥")||price.startsWith("￥"))price else "¥$price",fontSize=16.sp)
                    if(link.isNotEmpty())Row(verticalAlignment=Alignment.CenterVertically){MaterialGlyph("shopping_cart_outlined",size=18.dp,color=Color(0xFFF44336));Spacer(Modifier.width(2.dp));Text(product.text("mall_name","mall_title").ifEmpty{"购买"},fontSize=15.sp,color=Color(0xFFF44336))}
                }
            }
        }
        if(note.isNotEmpty()) {
            HorizontalDivider(Modifier.padding(vertical=5.dp))
            Row(verticalAlignment=Alignment.Top){ContentAvatar(api,item.text("userAvatar").ifEmpty{source.text("userAvatar")},source.text("username"),23.dp){onUser(source.text("uid").ifEmpty{item.text("uid")})};Spacer(Modifier.width(6.dp));Box(Modifier.weight(1f)){ContentRichText(note,onLink=onLink,fontSize=14.sp,lineHeight=19.6.sp,prefix=androidx.compose.ui.text.buildAnnotatedString{pushStyle(androidx.compose.ui.text.SpanStyle(color=Color(0xFF009688)));append("${source.text("username")}: ");pop()})}}
        }
        com.green.note.ui.ReviewTextButton(onClick=rememberHapticClick(onVote),enabled=enabled,modifier=Modifier.align(Alignment.End),colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.onSurfaceVariant),iconPadding=true) {
            MaterialGlyph("arrow_upward_rounded",color=if(voted)MaterialTheme.colorScheme.primary else LocalContentColor.current);ReviewButtonIconGap();Text("$count")
        }
    }
}

@Composable
private fun RankingMedal(rank:Int,modifier:Modifier=Modifier) {
    val color=when(rank){1->Color(0xFFFFD15D);2->Color(0xFFAECBF0);3->Color(0xFFE3B592);else->Color(0xFFC7C7C7)}
    Box(modifier.size(28.dp,37.dp)) {
        Canvas(Modifier.fillMaxSize()){scale(size.width/28,size.height/37,pivot=Offset.Zero){val ribbon=Path().apply{moveTo(0f,0f);lineTo(28f,0f);lineTo(18f,10f);lineTo(10f,10f);close()};drawPath(ribbon,color);drawCircle(color,13f,Offset(14f,23f));drawCircle(Color.White.copy(alpha=.7f),11f,Offset(14f,23f),style=Stroke(1.5f))}}
        Text("$rank",Modifier.fillMaxWidth().padding(top=11.dp),fontSize=13.sp,color=Color(0xFF444444),textAlign=TextAlign.Center)
    }
}

@Composable
private fun RankingCommentGlyph(color:Color,modifier:Modifier) {Canvas(modifier) {scale(size.width/24,size.height/24,pivot=Offset.Zero){
    val p=Path().apply{moveTo(22f,12f);cubicTo(22f,6.5f,17.5f,2f,12f,2f);cubicTo(6.5f,2f,2f,6.5f,2f,12f);cubicTo(2f,17.5f,6.5f,22f,12f,22f);lineTo(18.5f,22f);quadraticTo(22f,22f,22f,18.5f);close()}
    drawPath(p,color,style=Stroke(1.9f,cap=StrokeCap.Round,join=StrokeJoin.Round));drawLine(color,Offset(7f,9f),Offset(17f,9f),1.9f,StrokeCap.Round);drawLine(color,Offset(7f,14f),Offset(14f,14f),1.9f,StrokeCap.Round)
}}}

@Composable
private fun RankingEditor(title:String,label:String,initial:String,limit:Int,onDismiss:()->Unit,onSave:(String)->Unit) {
    var value by remember {mutableStateOf(initial)};var invalid by remember {mutableStateOf(false)}
    com.green.note.ui.ReviewAlertDialog(appDialog=true,onDismissRequest=onDismiss,title={Text(title)},text={
        CommunityFormField(value,{value=it;invalid=false},label,Modifier.fillMaxWidth().padding(bottom=12.dp),
            lines=if(label=="内容"||label=="说明")5 else 1,limit=limit,error=if(invalid)"请填写$label"else null)
    },dismissButton={com.green.note.ui.ReviewTextButton(onClick=onDismiss){Text("取消")}},confirmButton={com.green.note.ui.ReviewButton(onClick={if(label!="说明"&&value.isBlank())invalid=true else onSave(value.trim())}){Text("确认")}})
}

@Composable
private fun RankingGoodsPicker(api:ContentApi,onBack:()->Unit,onPick:(JSONObject)->Unit) {
    var input by rememberSaveable {mutableStateOf("")};var keyword by rememberSaveable {mutableStateOf("")}
    val repo=remember(api){ContentRepository(api)}
    val state=remember(keyword){ContentListState {page,first,last->repo.page(ContentRequest("/v6/goods/search",mapOf("keyword" to keyword,"sortName" to "","sort" to "","isCoupon" to "0")),page,first,last)}}
        Column(Modifier.fillMaxSize().background(LocalScaffoldColor.current).statusBarsPadding()) {
            ReviewToolbarIcons { Row(Modifier.fillMaxWidth().height(52.dp),verticalAlignment=Alignment.CenterVertically){Box(Modifier.width(56.dp),contentAlignment=Alignment.Center){ContentIcon("arrow_back","返回",onBack)};Spacer(Modifier.width(16.dp));Text("搜索推荐好物",fontSize=18.sp,fontWeight=adjustedWeight(700))} }
            CommunityFormField(input,{input=it},"",Modifier.fillMaxWidth().padding(16.dp),limit=100,hint="输入商品名称",autofocus=true,prefixIcon="search",imeAction=ImeAction.Search,onSubmit={keyword=it.trim()})
            if(keyword.isNotEmpty())ContentList(api,state,{},{},{},{_,_,_->},{},{},itemContent={row->
                ContentListTile(headlineContent={Text(row.text("product_goods_title","goods_title","title"),maxLines=2,overflow=TextOverflow.Ellipsis)},supportingContent={Text(row.text("price","goods_promo_title"))},trailingContent={MaterialGlyph("add_circle_outline")},modifier=Modifier.clickable(enabled=row.text("id","entityId").isNotEmpty(),onClick=rememberHapticClick{onPick(row)}))
            })
        }
}
