package com.green.note.content

import org.json.JSONObject
import java.util.Locale

internal data class FeedPrice(val amount:Double,val config:String) {
    val formatted:String get()=if(amount%1.0==0.0)String.format(Locale.ROOT,"%.0f",amount) else String.format(Locale.ROOT,"%.2f",amount).removeSuffix("0")
}
internal fun feedPrice(row:JSONObject):FeedPrice? {
    if(row.text("tsubid")!="6")return null
    val data=when(val raw=row.opt("tsubdata")){is JSONObject->raw;is String->runCatching{JSONObject(raw)}.getOrNull();else->null} ?: return null
    val amount=data.text("final_price").toDoubleOrNull()?.takeIf{it.isFinite()&&it>0} ?: return null
    return FeedPrice(amount,data.text("config_name"))
}
internal fun feedArticleCover(row:JSONObject,detail:Boolean):String {
    for(key in listOf("message_cover","cover","coverPic","cover_pic")+(if(detail)emptyList() else listOf("extra_pic"))+listOf("header_image")+(if(detail)emptyList() else listOf("pic"))) {
        val value=row.text(key).substringBefore(',').trim()
        if(value.startsWith("http://")||value.startsWith("https://")||value.startsWith('/'))return value
    }
    return if(detail)"" else feedImages(row).firstOrNull().orEmpty()
}
internal fun feedArticleSummary(row:JSONObject):String {
    val title=row.text("title")
    for(key in listOf("description","subTitle","intro","summary")) {
        val raw=row.text(key)
        if(raw.isNotEmpty()&&raw!=title) {
            val value=plainCardText(raw).removePrefix(title).trim()
            if(value.isNotEmpty())return value
        }
    }
    return row.text("message").removePrefix(title).trim().replace(Regex("^#+\\s*.*?\\n"),"").trim()
}
internal fun feedGenericTitle(title:String,username:String)=title.contains("动态")||title.contains("图文")||title==username||title.startsWith("${username}的")
internal fun feedIsArticle(row:JSONObject,detail:Boolean,hasParts:Boolean=false):Boolean {
    val title=row.text("title");val username=row.text("username").ifEmpty{row.optJSONObject("userInfo")?.text("username").orEmpty()}
    return row.optBoolean("_composeArticleLayout") || (detail&&hasParts) || row.text("entityType","entity_type").lowercase() in setOf("article","feedarticle","feed_article","dyharticle","news") ||
        listOf(row.text("feedType","feed_type"),row.text("entityTemplate","entity_template")).any{it.lowercase() in setOf("feedarticle","feed_article","article","dyharticle")} ||
        (title.isNotEmpty()&&!feedGenericTitle(title,username)&&feedArticleCover(row,detail).isNotEmpty()&&feedPrice(row)==null&&row.optJSONObject("vote")==null)
}
internal fun feedCount(value:Int)=if(value<=0)"" else if(value>10000)String.format(Locale.ROOT,"%.1fw",value/10000.0) else value.toString()
internal fun feedPictureMetadata(row:JSONObject?,url:String):JSONObject {
    val result=JSONObject()
    if(row==null)return result
    val normalized = com.green.note.network.normalizeNetworkImageUrl(url)
    if (normalized.isEmpty()) return result
    for(field in listOf("picArr","pics","imageUriList","image_uri_list")) {
        val array=row.optJSONArray(field) ?: continue
        for(i in 0 until array.length()) {
            val item=array.optJSONObject(i) ?: continue
            val source = item.text("url","pic","image","original","originalUrl")
            if (source == url || com.green.note.network.normalizeNetworkImageUrl(source) == normalized) {
                item.keys().forEach { result.put(it, item.opt(it)) }
            }
        }
    }
    return result
}
internal fun feedPictureDimension(raw:JSONObject,name:String):Int {
    val large=raw.optJSONObject("large");val geo=raw.optJSONObject("geo")
    val value=raw.opt(name) ?: raw.opt(if(name=="width")"w" else "h") ?: geo?.opt(name) ?: large?.opt(name) ?: large?.optJSONObject("geo")?.opt(name)
    return value?.toString()?.toDoubleOrNull()?.takeIf{it.isFinite()&&it>0}?.toInt() ?: 0
}
internal fun feedImageBadge(url:String,raw:JSONObject,feed:JSONObject?,knownHdr:Boolean,width:Int=0,height:Int=0):String? {
    val lower=url.lowercase()
    if(lower.contains(".gif"))return "GIF"
    fun hdr(value:JSONObject?)=listOf("is_hdr","isHdr","hdr").any{value?.opt(it)?.toString() in setOf("1","true")}
    if(knownHdr||hdr(raw)||hdr(feed)||listOf("is_hdr=1","hdr=1","ultrahdr","ultra_hdr","gainmap").any(lower::contains))return "HDR"
    val w=feedPictureDimension(raw,"width").takeIf{it>0} ?: width
    val h=feedPictureDimension(raw,"height").takeIf{it>0} ?: height
    return if((w>0&&h.toDouble()/w>2)||lower.contains("is_long=1"))"长图" else null
}
