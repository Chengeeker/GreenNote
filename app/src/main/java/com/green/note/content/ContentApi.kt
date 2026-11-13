package com.green.note.content

import org.json.JSONObject

data class LocalFollowSource(val profileId: String, val publicUid: String, val userIds: List<String>, val revision: Long = 0)

interface ContentApi {
    suspend fun verifyFeedDetail(id: String, challenge: com.green.note.network.CaptchaRequired): JSONObject = throw challenge
    suspend fun verifyCommentRequest(challenge: com.green.note.network.CaptchaRequired): Unit = throw challenge
    fun headlineCacheScope(): String = imageCacheScope()
    fun localFollowSources(): kotlinx.coroutines.flow.Flow<LocalFollowSource> = kotlinx.coroutines.flow.emptyFlow()
    fun localFollowRevision(): Long = 0
    suspend fun localLibrary(field: String): List<JSONObject> = error("本地资料服务尚未接入")
    suspend fun resolveApkDownloadUrl(packageName: String, appId: String, versionCode: String): String = error("应用下载服务尚未接入")
    fun imageHeaders(url: String): Map<String, String> = emptyMap()
    fun imageCacheScope(): String = ""
    fun isFeedFavorited(feed: JSONObject): Boolean = feedFavoriteFlag(feed)
    fun isUserFollowed(user: JSONObject): Boolean = listOf("isFollow", "is_follow", "followed").any { user.optString(it) in setOf("1", "true") }
    suspend fun followUser(user: JSONObject, following: Boolean): Boolean {
        request(if (following) "/v6/user/unfollow" else "/v6/user/follow", if (following) "GET" else "POST", mapOf("uid" to user.optString("uid")))
        return !following
    }
    suspend fun setPublicIdentity(user: JSONObject) { error("匿名公开资料服务尚未接入") }
    fun isProductFollowed(product: JSONObject): Boolean = product.optString("is_follow") == "1"
    suspend fun followProduct(product: JSONObject, following: Boolean): Boolean {
        request("/v6/product/changeFollowStatus", "POST", mapOf("id" to product.optString("id"), "status" to if (following) "0" else "1"))
        return !following
    }
    suspend fun uploadFeedImage(bytes: ByteArray): String = error("图片上传服务尚未接入")
    suspend fun uploadMessageImage(bytes: ByteArray, uid: String): String = error("私信图片上传服务尚未接入")
    suspend fun submitMultipart(path: String, fields: Map<String, String>, query: Map<String, String> = emptyMap()): JSONObject = error("表单服务尚未接入")
    suspend fun feedCollections(feedId: String): List<ContentCollection> = error("收藏夹服务尚未接入")
    suspend fun updateFeedCollections(feed: JSONObject, selected: List<String>, cancelled: List<String>) {
        error("收藏夹服务尚未接入")
    }
    suspend fun toggleLocalFavorite(feed: JSONObject): Boolean = error("本地收藏服务尚未接入")
    suspend fun request(
        path: String,
        method: String = "GET",
        query: Map<String, String> = emptyMap(),
        body: Map<String, String>? = null,
    ): JSONObject
}

data class ContentCollection(val id: String, val title: String, val selected: Boolean, val isDefault: Boolean)

data class ContentDestination(val type: String, val title: String = "", val id: String = "", val route: String = "", val eventId: Long = System.nanoTime())

data class ContentSession(
    val uid: String = "",
    val username: String = "",
    val avatar: String = "",
    val authenticated: Boolean = false,
    val anonymous: Boolean = false,
)
