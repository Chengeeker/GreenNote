package com.green.note.content

import org.json.JSONObject

internal fun feedFavoriteFlag(feed: JSONObject): Boolean {
    val action = feed.optJSONObject("userAction")
    val value = sequenceOf(action?.opt("favorite"), action?.opt("collect"), feed.opt("isFavorite"), feed.opt("is_favorite"), feed.opt("favorited"))
        .firstOrNull { it != null && it != JSONObject.NULL }
    return value?.toString() in setOf("1", "true")
}

internal val ContentSession.loginRequiredMessage: String
    get() = if (anonymous) "当前为匿名登录，无法使用此功能" else "请先登录"

// main.dart only blocks anonymous mode at the publish menu; guest drafts remain usable.
internal fun publishMenuDenied(session: ContentSession): String? =
    session.loginRequiredMessage.takeIf { session.anonymous }

internal fun collectionPickerDenied(session: ContentSession): String? = when {
    session.authenticated -> null
    session.anonymous -> "匿名账户仅支持本地收藏，暂不支持收藏夹"
    else -> session.loginRequiredMessage
}
