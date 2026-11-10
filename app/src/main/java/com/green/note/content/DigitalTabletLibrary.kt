package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.green.note.ui.*
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun digitalTabletBrand(row:JSONObject):JSONObject {
    val id=row.text("id","entityId");val url=row.text("url").replace(Regex("category_id%3D\\d+",RegexOption.IGNORE_CASE),"category_id%3D1001").replace(Regex("category_id=\\d+"),"category_id=1001")
        .ifEmpty{if(id.isEmpty())""else"/page?url=%2Fproduct%2FseriesList%3FshowTab%3D1%26type%3Dbrand%26id%3D$id%26category_id%3D1001%26showMode%3D0"}
    return JSONObject(row.toString()).put("url",url)
}

@Composable
internal fun DigitalTabletLibrary(api:ContentApi,state:ContentListState,brands:List<JSONObject>,brandError:String?,retryBrands:()->Unit,
    sort:String,onSort:(String)->Unit,onProduct:(JSONObject)->Unit,onBrand:(String,String)->Unit) {
    val scope=rememberCoroutineScope();val list=rememberLazyListState();val bottom=WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    ReviewScrollActivity(list)
    val color=reviewCardSurface();val border=reviewCardBorder();val stroke=with(LocalDensity.current){.8.dp.toPx()}
    LaunchedEffect(state,list){snapshotFlow{list.layoutInfo.visibleItemsInfo.lastOrNull()?.index?:0}.distinctUntilChanged().collect{if(state.rows.isNotEmpty()&&it>=state.rows.size+1&&!state.busy&&state.error==null)state.load()}}
    ReviewRefreshBox(state.refreshing,{scope.launch{state.load(true)}},Modifier.fillMaxSize()) {
        LazyColumn(state=list,contentPadding=PaddingValues(start=10.dp,top=8.dp,end=10.dp,bottom=100.dp+bottom)) {
            item {
                TabletSection {
                    Text("今日热门",style=MaterialTheme.typography.titleLarge)
                    Spacer(Modifier.height(12.dp))
                    when {
                        state.busy && state.rows.isEmpty() -> Box(Modifier.fillMaxWidth().height(140.dp),contentAlignment=Alignment.Center) { com.green.note.ui.ReviewCircularProgress() }
                        state.rows.isEmpty() -> TabletEmpty(state) { scope.launch { state.load(true) } }
                        else -> Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                            state.rows.take(8).chunked(4).forEachIndexed { rowIndex,group ->
                                Row(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                                    group.forEachIndexed { column,item ->
                                        TabletHot(api,item,rowIndex*4+column+1,Modifier.weight(1f).height(132.dp)) { onProduct(item) }
                                    }
                                    repeat(4-group.size) { Spacer(Modifier.weight(1f)) }
                                }
                            }
                        }
                    }
                }
            }
            if(brands.isNotEmpty()||brandError!=null)item {TabletSection{Text("品牌",style=MaterialTheme.typography.titleLarge);Spacer(Modifier.height(12.dp));if(brands.isNotEmpty())FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp),verticalArrangement=Arrangement.spacedBy(10.dp)){brands.forEach{brand->DigitalLibraryBrand(api,brand){onBrand(brand.text("title","name"),brand.text("url"))}}}else Row(verticalAlignment=Alignment.CenterVertically){Text(brandError?:"正在加载品牌",Modifier.weight(1f));com.green.note.ui.ReviewTextButton(onClick=retryBrands){Text("重试")}}}}
            item {
                Column(Modifier.padding(top=5.dp).fillMaxWidth().clip(RoundedCornerShape(topStart=20.dp,topEnd=20.dp)).background(color)
                    .drawBehind {
                        drawLine(border,Offset(0f,0f),Offset(size.width,0f),stroke)
                        drawLine(border,Offset(0f,0f),Offset(0f,size.height),stroke)
                        drawLine(border,Offset(size.width,0f),Offset(size.width,size.height),stroke)
                    }.padding(start=14.dp,top=12.dp,end=14.dp)) {
                    Row(verticalAlignment=Alignment.CenterVertically) {
                        Text("产品评分",Modifier.weight(1f),style=MaterialTheme.typography.titleLarge)
                        listOf("热度","评分","最新").forEachIndexed { index,label ->
                            if(index>0)Spacer(Modifier.width(5.dp))
                            DigitalSortChip(label,sort==label) { onSort(label) }
                        }
                    }
                    if(state.rows.isEmpty())TabletEmpty(state) { scope.launch { state.load(true) } }
                }
            }
            itemsIndexed(state.rows,key={_,row->entityKey(row)}) {index,item->Box(Modifier.fillMaxWidth().background(color).drawBehind{drawLine(border,Offset(0f,0f),Offset(0f,size.height),stroke);drawLine(border,Offset(size.width,0f),Offset(size.width,size.height),stroke)}.padding(horizontal=14.dp)){TabletRankRow(api,item,index+1){onProduct(item)}}}
            item {Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(bottomStart=20.dp,bottomEnd=20.dp)).background(color).border(.8.dp,border,RoundedCornerShape(bottomStart=20.dp,bottomEnd=20.dp)));Spacer(Modifier.height(5.dp));if(state.error!=null&&state.rows.isNotEmpty())com.green.note.ui.ReviewTextButton(onClick={scope.launch{state.load()}}){Text("加载失败，点击重试：${state.error}")};if(state.busy&&state.rows.isNotEmpty())Box(Modifier.fillMaxWidth().padding(16.dp),contentAlignment=Alignment.Center){com.green.note.ui.ReviewCircularProgress()}}
        }
    }
}

@Composable
private fun TabletSection(content:@Composable ColumnScope.()->Unit) {
    Column(Modifier.padding(vertical=5.dp).fillMaxWidth().dropShadow(RoundedCornerShape(20.dp),Shadow(radius=1.dp,color=Color.Black.copy(alpha=.1f))).background(reviewCardSurface(),RoundedCornerShape(20.dp)).border(.8.dp,reviewCardBorder(),RoundedCornerShape(20.dp)).padding(start=14.dp,top=12.dp,end=14.dp,bottom=14.dp),content=content)
}
@Composable
private fun TabletEmpty(state:ContentListState,retry:()->Unit){Box(Modifier.fillMaxWidth().height(120.dp),contentAlignment=Alignment.Center){Column(horizontalAlignment=Alignment.CenterHorizontally){Text(state.error?:"暂无产品数据");if(state.error!=null)com.green.note.ui.ReviewTextButton(onClick=retry){Text("重试")}}}}
@Composable
private fun TabletBadge(rank:Int,modifier:Modifier=Modifier){Text(rank.toString(),modifier.background(if(rank<=3)Color(0xFFFF9800)else Color.Black.copy(alpha=.38f),RoundedCornerShape(4.dp)).padding(horizontal=4.dp,vertical=1.dp),color=Color.White,fontWeight=FontWeight.Bold)}
@Composable
private fun TabletHot(api:ContentApi,row:JSONObject,rank:Int,modifier:Modifier,onClick:()->Unit) {
    Column(modifier.clickable(onClick=rememberHapticClick(onClick)),horizontalAlignment=Alignment.CenterHorizontally){Box(Modifier.weight(1f).fillMaxWidth(),contentAlignment=Alignment.Center){val image=row.text("logo","pic","cover","thumb");CardImage(api,image,Modifier.fillMaxSize(),ContentScale.Fit){MaterialGlyph("tablet_android_rounded",size=38.dp)};TabletBadge(rank,Modifier.align(Alignment.TopStart))};Text(row.text("title","name").ifEmpty{"平板"},maxLines=2,overflow=TextOverflow.Ellipsis,textAlign=TextAlign.Center,style=MaterialTheme.typography.bodyMedium);val hot=row.text("hot_num_txt","hot","hot_num");if(hot.isNotEmpty())Text("🔥 $hot",maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
}
@Composable
private fun TabletRankRow(api:ContentApi,row:JSONObject,rank:Int,onClick:()->Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick=rememberHapticClick(onClick)).padding(vertical=9.dp),verticalAlignment=Alignment.CenterVertically){Box(Modifier.size(64.dp,66.dp),contentAlignment=Alignment.Center){val image=row.text("logo","pic","cover","thumb");CardImage(api,image,Modifier.size(54.dp,60.dp),ContentScale.Fit){MaterialGlyph("tablet_android_rounded")};TabletBadge(rank,Modifier.align(Alignment.TopStart))};Spacer(Modifier.width(10.dp));Column(Modifier.weight(1f)){Text(row.text("title","name").ifEmpty{"平板"},maxLines=2,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.titleMedium);Spacer(Modifier.height(4.dp));val hot=row.text("hot_num_txt","hot","hot_num");val comments=row.text("feedCommentNumTxt","commentnum");Text(listOf(if(hot.isNotEmpty())"🔥 $hot 热度"else"",if(comments.isNotEmpty())"$comments 讨论"else"").filter(String::isNotEmpty).joinToString("  "),maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)};val score=row.text("star_average_score","score","recent_30_days_owner_star_average_score");if(score.isNotEmpty())Text(score,style=MaterialTheme.typography.headlineSmall,color=MaterialTheme.colorScheme.tertiary)}
}
@Composable
internal fun DigitalSortChip(label:String,selected:Boolean,onClick:()->Unit){
    val scheme=MaterialTheme.colorScheme
    DigitalLibraryStaticText(label,LocalTextStyle.current.copy(fontSize=11.5.sp,fontWeight=if(selected)FontWeight.Bold else FontWeight.Normal,color=if(selected)scheme.onSurface else scheme.outline),
        Modifier.background(if(selected)scheme.surfaceContainerHighest else Color.Transparent,RoundedCornerShape(14.dp)).clickable(onClick=rememberHapticClick(onClick)).padding(horizontal=10.dp).fractionalVerticalPadding(3.5.dp))
}

@Composable
internal fun DigitalLibraryStaticText(value:String,style:androidx.compose.ui.text.TextStyle,modifier:Modifier=Modifier) {
    val metrics=rememberFlutterArticleStyle(androidx.compose.ui.text.AnnotatedString(value),style,plainTitle=true)
    Text(value,modifier.then(metrics.modifier),style=metrics.style,onTextLayout=metrics.onTextLayout)
}
@Composable
internal fun DigitalLibraryBrand(api:ContentApi,row:JSONObject,selected:Boolean=false,onClick:()->Unit){val name=row.text("title","name");Column(Modifier.size(66.dp,54.dp).clickable(onClick=rememberHapticClick(onClick)),horizontalAlignment=Alignment.CenterHorizontally){Box(Modifier.size(66.dp,34.dp).dropShadow(RoundedCornerShape(8.dp),Shadow(radius=4.dp,color=Color.Black.copy(alpha=.05f),offset=DpOffset(0.dp,1.5.dp))).background(Color.White,RoundedCornerShape(8.dp)).border(1.5.dp,if(selected)Color(0xFF00B074)else Color.Transparent,RoundedCornerShape(8.dp)).padding(horizontal=7.5.dp,vertical=4.5.dp),contentAlignment=Alignment.Center){val image=row.text("logo","pic","icon");DigitalBrandLogo(api,row,image,Modifier.fillMaxSize()){Text(name,fontSize=10.sp,fontWeight=FontWeight.Bold,color=Color.Black.copy(alpha=.87f),maxLines=1,overflow=TextOverflow.Ellipsis)}};Spacer(Modifier.height(2.dp));Text(name,fontSize=11.sp,fontWeight=if(selected)FontWeight.Bold else FontWeight.Normal,color=if(selected)Color(0xFF00B074)else MaterialTheme.colorScheme.onSurface,maxLines=1,overflow=TextOverflow.Ellipsis)}
}

@Composable
internal fun DigitalCategoryRail(categories:List<JSONObject>,selected:String,expanded:Set<String>,onExpanded:(Set<String>)->Unit,onSelect:(String)->Unit) {
    val colors=MaterialTheme.colorScheme;val dark=colors.surface.let{it.red+it.green+it.blue<1.5f};val green=Color(0xFF00B074)
    val background=if(dark)Color(0xFF1C1C1E)else colors.surfaceContainerLow
    LazyColumn(Modifier.width(100.dp).fillMaxHeight().background(background),state=com.green.note.ui.rememberReviewLazyListState(),contentPadding=PaddingValues(vertical=4.dp)) {
        categories.forEach{category->val id=category.text("id");val children=digitalChildren(category);val childSelected=children.any{it.text("id")==selected};val direct=id==selected&&children.isEmpty()
            item(key=id){Box(Modifier.fillMaxWidth().height(48.dp).background(if(direct)colors.surfaceContainerHighest.copy(alpha=.6f)else background).clickable {
                if(children.isEmpty()){if(id!=selected)onSelect(id)}else if(id in expanded)onExpanded(expanded-id)else{onExpanded(expanded+id);if(!childSelected)onSelect(children.first().text("id"))}
            }){if(direct)Box(Modifier.width(3.5.dp).fillMaxHeight().background(green));Text(category.text("title"),Modifier.align(Alignment.CenterStart).padding(start=if(direct)17.5.dp else 14.dp,end=14.dp),fontSize=if(id==selected||childSelected)14.5.sp else 13.5.sp,fontWeight=if(id==selected||childSelected)FontWeight.Bold else FontWeight.Normal,color=if(direct)green else if(childSelected)colors.onSurface else colors.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}}
            if(id in expanded)items(children,key={"$id:${it.text("id")}"}){child->val active=child.text("id")==selected;Box(Modifier.fillMaxWidth().height(42.dp).background(if(active)if(dark)Color(0xFF003830)else green.copy(alpha=.12f)else if(dark)Color(0xFF101010)else colors.surface).clickable{if(!active)onSelect(child.text("id"))}){if(active)Box(Modifier.width(3.5.dp).fillMaxHeight().background(green));Text(child.text("title","name"),Modifier.align(Alignment.CenterStart).padding(start=if(active)21.5.dp else 18.dp,end=10.dp),fontSize=13.sp,fontWeight=if(active)FontWeight.Bold else FontWeight.Normal,color=if(active)green else colors.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}}
        }
    }
}
