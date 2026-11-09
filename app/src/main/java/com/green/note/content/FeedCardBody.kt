package com.green.note.content

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.*
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.adjustedWeight
import org.json.JSONObject

@Composable
internal fun FeedCardBody(api:ContentApi,row:JSONObject,username:String,detail:Boolean,article:Boolean,compact:Boolean,official:Boolean,headline:Boolean,
    price:FeedPrice?,parts:List<ArticlePart>,onOpen:(JSONObject)->Unit,onLink:(String)->Unit,onGallery:(List<String>,Int,JSONObject?)->Unit,
    profileCard: Boolean = false) {
    val scheme=MaterialTheme.colorScheme;val title=row.text("title");val generic=feedGenericTitle(title,username)
    val cover=feedArticleCover(row,detail);val summary=remember(row){clipContentPreview(feedArticleSummary(row))};val message=row.text("message")
    val inlineArticle=detail&&article&&parts.isNotEmpty();val images=feedImages(row);val video=remember(row){feedVideo(row)}
    val editorial=row.optBoolean("_composeEditorialCover");val before=row.optBoolean("_composePicturesBeforeText")
    val headerOnly=row.optBoolean("_composeArticleHeaderOnly");val tailOnly=row.optBoolean("_composeArticleTailOnly")
    if(article&&!detail) {
        if(title.isNotEmpty()&&!generic){
            val titleStyle=com.green.note.ui.rememberFlutterArticleStyle(AnnotatedString(title),LocalTextStyle.current.copy(fontSize=16.sp,fontWeight=adjustedWeight(700),lineHeight=21.6.sp),plainTitle=true)
            Text(title,modifier=titleStyle.modifier,style=titleStyle.style,onTextLayout=titleStyle.onTextLayout,maxLines=2,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(8.dp))
        }
        if(cover.isNotEmpty()){FeedCover(api,cover,12.dp,2f,brokenFallback=true);Spacer(Modifier.height(8.dp))}
        if(summary.isNotEmpty()){ContentRichText(summary,maxLines=3,secondary=true,onLink=onLink,fontSize=16.sp,lineHeight=23.2.sp,letterSpacing=.1.sp,maxCharacters=1000,flutterArticleMetrics=true);Spacer(Modifier.height(8.dp))}
        FeedTargetOrTags(api,row,false,onLink)
        return
    }
    if(!tailOnly&&title.isNotEmpty()&&title!=message&&!generic) {
        val vote=row.optJSONObject("vote")
        if(vote!=null)FeedVoteTitle(title)
        else Text(title,fontSize=16.sp,fontWeight=adjustedWeight(700),lineHeight=22.4.sp)
        Spacer(Modifier.height(6.dp))
    }
    if(!tailOnly&&article&&detail&&cover.isNotEmpty()){Spacer(Modifier.height(4.dp));FeedCover(api,cover,12.dp,2f){onGallery(listOf(cover),0,row)};Spacer(Modifier.height(10.dp))}
    if(!tailOnly&&price!=null)FeedPriceLine(price)
    if(headerOnly)return
    if(!tailOnly&&before&&images.isNotEmpty()&&!inlineArticle){Spacer(Modifier.height(8.dp));FeedImages(api,images,detail,joined=true,raw=row){urls,index->onGallery(urls,index,JSONObject(row.toString()).put("_composeGalleryUseDeclaredDimensions",true))};Spacer(Modifier.height(10.dp))}
    if(!tailOnly&&inlineArticle)ArticleBody(api,row,parts,onLink,onGallery)
    else if(!tailOnly&&message.isNotEmpty()&&!editorial) {
        when {
            detail->SelectionContainer{ContentRichText(message,onLink=onLink,fontSize=16.sp,lineHeight=26.4.sp,letterSpacing=.15.sp)}
            row.optBoolean("_composeArticleLayout")->ContentRichText(summary,maxLines=3,secondary=true,onLink=onLink,fontSize=16.sp,lineHeight=23.2.sp,letterSpacing=.1.sp,maxCharacters=1000,flutterArticleMetrics=true)
            official->FeedOfficialMessage(message.trimEnd(),6,false,22.08.sp,onLink){onOpen(row)}
            else->{val prefix=if(price!=null)buildAnnotatedString{withStyle(SpanStyle(color=Color(0xFF009688))){append("¥ 到手价 | ")}}else null
                val darkProfile = profileCard && scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f
                ContentRichText(message,maxLines=8,onLink=onLink,fontSize=16.sp,lineHeight=when{headline->22.08.sp;price!=null->22.4.sp;else->20.8.sp},prefix=prefix,
                    color = if (darkProfile) Color(0xFFD2D2D2) else Color.Unspecified,
                    linkColor = if (darkProfile) darkProfileAccent else if (profileCard) Color(0xFF00796B) else scheme.primary)}
        }
    }
    if(!(before&&images.isNotEmpty()&&!inlineArticle)) {
        when {
            editorial->{val image=row.text("message_cover","pic").ifEmpty{images.firstOrNull().orEmpty()};if(image.isNotEmpty()) {Spacer(Modifier.height(8.dp));Box {FeedCover(api,image,6.dp,20f/9f);Text("◇ 编辑精选",Modifier.padding(start=8.dp,top=8.dp).background(Color(0xFFD84124),RoundedCornerShape(3.dp)).padding(horizontal=4.dp,vertical=2.dp),fontSize=10.sp,color=Color.White)}}}
            video!=null->FeedVideoPreview(api,video)
            !inlineArticle->{
                val effective=if(article&&detail&&cover.isNotEmpty())images.filterNot{it==cover}else images
                if(effective.isNotEmpty()){
                    Spacer(Modifier.height(8.dp))
                    if (profileCard && effective.size == 1) {
                        val picture = effective.single()
                        val metadata = remember(row, picture) { feedPictureMetadata(row, picture) }
                        val ratio = feedPictureDimension(metadata, "width").toFloat() / feedPictureDimension(metadata, "height")
                        FeedImageTile(api, picture, row, 0, false, 0, Modifier.width(140.dp)
                            .aspectRatio(ratio.takeIf { it.isFinite() && it > 0 }?.coerceIn(.65f, 1.8f) ?: 1f)) { onGallery(effective, 0, JSONObject(row.toString()).put("_composeGalleryUseDeclaredDimensions", true)) }
                    } else FeedImages(api,effective,detail,joined=!detail&&(price!=null||compact),raw=row){urls,index->onGallery(urls,index,JSONObject(row.toString()).put("_composeGalleryUseDeclaredDimensions",true))}
                }
            }
        }
    }
    if(editorial&&message.isNotEmpty()){Spacer(Modifier.height(12.dp));FeedOfficialMessage(message,3,true,22.4.sp,onLink){onOpen(row)}}
    row.optJSONObject("vote")?.let{FeedPoll(api,row.text("id"),it)}
    if(price==null||detail)FeedTargetOrTags(api,row,detail,onLink)
}

@Composable
private fun FeedVoteTitle(title:String) {
    val density=LocalDensity.current
    val labelStyle=LocalTextStyle.current.copy(fontSize=11.sp,fontWeight=FontWeight.Normal,color=Color.White)
    val labelSize=rememberTextMeasurer().measure("投票",labelStyle).size
    val placeholder=with(density){Placeholder((labelSize.width.toDp()+18.dp).toSp(),(labelSize.height.toDp()+2.dp).toSp(),PlaceholderVerticalAlign.Center)}
    val text=remember(title){buildAnnotatedString{appendInlineContent("vote-label","投票 ");append(title)}}
    Text(text,fontSize=16.sp,fontWeight=adjustedWeight(700),lineHeight=22.4.sp,
        inlineContent=mapOf("vote-label" to InlineTextContent(placeholder){
            Box(Modifier.fillMaxSize().padding(end=8.dp).background(Color(0xFFFF9800),RoundedCornerShape(3.dp)).padding(horizontal=5.dp,vertical=1.dp),contentAlignment=Alignment.Center){Text("投票",style=labelStyle,softWrap=false,maxLines=1)}
        }))
}

@Composable
private fun FeedCover(api:ContentApi,url:String,radius:Dp,ratio:Float,brokenFallback:Boolean=false,onClick:(()->Unit)?=null) {
    var failed by remember(url,api.imageCacheScope()){mutableStateOf(false)}
    Box(Modifier.fillMaxWidth().aspectRatio(ratio).clip(RoundedCornerShape(radius))
        .then(if(onClick!=null)Modifier.clickable(onClick=onClick)else Modifier),contentAlignment=Alignment.Center) {
        if(brokenFallback&&failed) {
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha=.4f)),contentAlignment=Alignment.Center){MaterialGlyph("broken_image_outlined",size=32.dp,color=MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha=.5f))}
        } else ContentImage(api,url,null,Modifier.fillMaxSize(),heroCornerRadius=radius,onError=if(brokenFallback)({failed=true})else null)
    }
}

@Composable
private fun FeedPriceLine(price:FeedPrice) {
    val orange=Color(0xFFFF9800);val scheme=MaterialTheme.colorScheme;val dark=scheme.surface.red+scheme.surface.green+scheme.surface.blue<1.5f
    FlowRow(Modifier.padding(top=12.dp,bottom=8.dp),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
        Row(Modifier.align(Alignment.CenterVertically).clip(RoundedCornerShape(4.dp)).border(1.dp,orange,RoundedCornerShape(4.dp)).padding(1.dp),verticalAlignment=Alignment.CenterVertically) {
            Box(Modifier.background(orange).padding(2.dp)){Box(Modifier.size(13.dp).border(1.dp,Color.White,androidx.compose.foundation.shape.CircleShape),contentAlignment=Alignment.Center){Text("¥",fontSize=10.sp,lineHeight=10.sp,color=Color.White)}}
            Text("到手价",Modifier.padding(horizontal=3.dp),fontSize=12.sp,color=orange)
        }
        Text("¥${price.formatted}",Modifier.align(Alignment.CenterVertically),fontSize=18.sp,fontWeight=FontWeight.SemiBold,color=orange)
        if(price.config.isNotEmpty())Text(price.config,Modifier.align(Alignment.CenterVertically).background(if(dark)Color(0xFF2C2C2C)else scheme.surfaceContainerHighest,RoundedCornerShape(4.dp)).padding(horizontal=5.dp,vertical=3.dp),fontSize=12.sp,color=scheme.onSurfaceVariant)
    }
}

@Composable
private fun FeedOfficialMessage(message:String,lines:Int,secondary:Boolean,lineHeight:TextUnit,onLink:(String)->Unit,onMore:()->Unit) {
    val preview=remember(message){clipContentPreview(message)}
    val measurer=rememberTextMeasurer();val density=LocalDensity.current
    val color=if(secondary)MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface
    val style=MaterialTheme.typography.bodyMedium.copy(fontSize=16.sp,lineHeight=lineHeight,color=color)
    BoxWithConstraints {
        val width=with(density){maxWidth.roundToPx()}
        val visible=remember(preview){
            val content = parseContentText(preview)
            AnnotatedString(content.plain, content.styles)
        }
        val layout=remember(visible,width,style,density){measurer.measure(visible,style,maxLines=lines,constraints=Constraints(maxWidth=width))}
        val suffix=buildAnnotatedString{withLink(LinkAnnotation.Clickable("feed-more",TextLinkStyles(SpanStyle(color=Color(0xFF009688))),LinkInteractionListener{onMore()})){append("…查看更多")}}
        val count=if(layout.hasVisualOverflow) {
            val link=measurer.measure(suffix,style);val last=layout.lineCount-1
            layout.getOffsetForPosition(Offset((width-link.size.width).coerceAtLeast(0).toFloat(),(layout.getLineTop(last)+layout.getLineBottom(last))/2)).coerceIn(0,visible.length)
        }else null
        ContentRichText(preview,onLink=onLink,fontSize=16.sp,lineHeight=lineHeight,secondary=secondary,maxCharacters=count,suffix=if(count!=null)suffix else null)
    }
}
