package com.green.note.network

import com.green.note.account.AccountRepository
import com.green.note.content.ContentApi
import com.green.note.content.ContentCollection
import com.green.note.content.LocalFollowSource
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.ByteString.Companion.encodeUtf8
import okio.ByteString.Companion.toByteString
import org.json.JSONArray
import org.json.JSONObject

class ContentActions(private val api: ApiClient, private val accounts: AccountRepository, private val session: () -> ApiSession,
    private val solveCaptcha: suspend (CaptchaRequired) -> String?,
) : ContentApi by api {
    override fun headlineCacheScope(): String = accounts.state.value.let { state ->
        when {
            state.authenticated -> state.requestCookie.encodeUtf8().sha256().hex()
            state.anonymous -> "anonymous-${JSONObject(state.localJson).optString("activeProfileId")}"
            else -> "guest"
        }
    }
    override fun localFollowRevision(): Long = accounts.state.value.sessionRevision

    override fun localFollowSources(): kotlinx.coroutines.flow.Flow<LocalFollowSource> = accounts.state.map { state ->
        if (!state.anonymous) LocalFollowSource("", "", emptyList(), state.sessionRevision) else {
            // AccountState contains an immutable canonical JSON snapshot; never mix fields from
            // two revisions by separately reading exportLocal and the public identity.
            val local = JSONObject(state.localJson)
            LocalFollowSource(local.getString("activeProfileId"), local.optJSONObject("publicIdentity")?.optString("uid").orEmpty(),
                local.optJSONObject("follows")?.keys()?.asSequence()?.toList().orEmpty(), state.sessionRevision)
        }
    }.distinctUntilChanged().flowOn(Dispatchers.Default)

    override suspend fun localLibrary(field: String): List<JSONObject> = withContext(Dispatchers.IO) {
        require(field in setOf("favorites", "follows", "productFollows")) { "本地资料类型无效" }
        val owner = session()
        require(owner.anonymous) { "请先切换到匿名账户" }
        val values = accounts.exportLocal().optJSONObject(field) ?: JSONObject()
        val rows = values.keys().asSequence().mapNotNull { key -> values.optJSONObject(key)?.let { JSONObject(it.toString()) } }.toList()
        check(owner == session()) { "账号已变更，请重新加载" }
        rows
    }
    override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
        return try { api.request(path, method, query, body) } catch (error: CaptchaRequired) {
            if (path != "/v6/feed/detail" || method != "GET") throw error
            val validate = solveCaptcha(error) ?: throw error
            api.verifyFeedDetail(query["id"].orEmpty(), error, validate)
        }
    }
    override suspend fun submitMultipart(path: String, fields: Map<String, String>, query: Map<String, String>): JSONObject = api.multipart(path, fields, query)
    private val collectionScopes = ConcurrentHashMap<String, ApiSession>()
    private val uploadClient = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()

    override fun isProductFollowed(product: JSONObject): Boolean = if (accounts.state.value.anonymous)
        accounts.localContains("productFollows", product.optString("id"))
        else product.optString("is_follow") in setOf("1", "true")

    override suspend fun followProduct(product: JSONObject, following: Boolean): Boolean {
        val revision = accounts.state.value.revision
        val id = product.optString("id")
        require(id.matches(Regex("[1-9][0-9]*"))) { "机型标识无效" }
        if (accounts.state.value.anonymous) {
            val item = JSONObject().put("id", id)
            listOf("title", "pic", "logo", "cover", "hot_num", "votenum").forEach { key -> if (product.has(key)) item.put(key, product.optString(key)) }
            accounts.toggleLocal("productFollows", id, item, expectedRevision = revision)
            return isProductFollowed(product)
        }
        requireSession(session())
        api.request("/v6/product/changeFollowStatus", "POST", mapOf("id" to id, "status" to if (following) "0" else "1"))
        return !following
    }

    private fun requireSession(owner: ApiSession) {
        if (!owner.authenticated || owner != session()) throw ApiException("账号已变更，请重新打开页面")
    }

    override suspend fun feedCollections(feedId: String): List<ContentCollection> {
        require(feedId.isNotBlank()) { "缺少动态 ID" }
        val owner = session()
        val collections = linkedMapOf<String, ContentCollection>()
        var first = ""
        var last = ""
        var page = 1
        while (true) {
            requireSession(owner)
            val root = api.request("/v6/collection/list", query = mapOf("uid" to "", "id" to feedId, "type" to "feed", "showDefault" to "1",
                "page" to page.toString(), "firstItem" to first, "lastItem" to last))
            requireSession(owner)
            val data = root.opt("data")
            val rows = if (data is JSONArray) data else (data as? JSONObject)?.let { value ->
                listOf("entities", "list", "rows", "data").firstNotNullOfOrNull { value.optJSONArray(it) }
            } ?: throw ApiException("收藏夹数据格式异常")
            val before = collections.size
            for (i in 0 until rows.length()) {
                val row = rows.optJSONObject(i) ?: continue
                val type = row.optString("entityType", row.optString("entity_type"))
                if (type.isNotEmpty() && type != "collection") continue
                fun field(vararg keys: String) = keys.firstNotNullOfOrNull { row.opt(it)?.takeUnless { it == JSONObject.NULL } }?.toString().orEmpty()
                fun flag(vararg keys: String) = field(*keys) in setOf("true", "1")
                val id = field("id", "collectionId", "entityId")
                if (id.isNotEmpty()) collections.putIfAbsent(id, ContentCollection(id, field("title", "name").ifBlank { "未命名收藏夹" },
                    flag("isBeCollected", "is_be_collected"), flag("defaultCollected", "default_collected", "isDefault", "is_default", "isDefaultCollection")))
            }
            if (!ApiRules.hasMore(root, rows.length()) || collections.size == before) break
            if (first.isEmpty()) first = root.optString("firstItem", rows.optJSONObject(0)?.let { it.optString("entityId", it.optString("id")) }.orEmpty())
            last = root.optString("lastItem", rows.optJSONObject(rows.length()-1)?.let { it.optString("entityId", it.optString("id", it.optString("collectionId"))) }.orEmpty())
            page++
        }
        collectionScopes[feedId] = owner
        return collections.values.toList()
    }

    override suspend fun updateFeedCollections(feed: JSONObject, selected: List<String>, cancelled: List<String>) {
        val id = feed.optString("id")
        require(id.isNotBlank() && (selected + cancelled).none { it.isBlank() || ',' in it }) { "收藏参数无效" }
        val owner = collectionScopes[id] ?: throw ApiException("请重新加载收藏夹")
        requireSession(owner)
        api.request("/v6/collection/addItem", "POST", body = mapOf("id" to selected.distinct().joinToString(","),
            "cancelId" to cancelled.distinct().joinToString(","), "targetId" to id,
            "type" to feed.optString("entityType", feed.optString("feedType", "feed")),
            "trace" to feed.optString("trace", feed.optString("extra_key"))))
        requireSession(owner)
    }

    override suspend fun toggleLocalFavorite(feed: JSONObject): Boolean {
        val revision = accounts.state.value.revision
        check(accounts.state.value.anonymous) { "当前不是匿名账户" }
        val id = feed.optString("id")
        val snapshot = JSONObject()
        listOf("id", "uid", "username", "userAvatar", "message", "pic", "dateline").forEach { key ->
            snapshot.put(key, feed.optString(key))
        }
        if (snapshot.optString("pic").isEmpty()) feed.optJSONArray("picArr")?.let { pics ->
            snapshot.put("pic", (0 until pics.length()).map { pics.optString(it) }.joinToString(","))
        }
        snapshot.put("entityType", "feed")
        accounts.toggleLocal("favorites", id, snapshot, expectedRevision = revision)
        return accounts.localContains("favorites", id)
    }

    suspend fun toggleDefaultFavorite(feed: JSONObject): Boolean {
        if (accounts.state.value.anonymous) return toggleLocalFavorite(feed)
        val rows = feedCollections(feed.optString("id"))
        val selected = rows.filter { it.selected }.map { it.id }
        val favorited = selected.isNotEmpty()
        val default = rows.firstOrNull { it.isDefault } ?: rows.firstOrNull { it.title.lowercase() in setOf("默认收藏夹", "默认收藏单", "default") }
        if (!favorited && default == null) throw ApiException("未找到默认收藏夹，请长按选择收藏夹")
        updateFeedCollections(feed, if (favorited) emptyList() else listOf(default!!.id), if (favorited) selected else emptyList())
        return !favorited
    }

    override fun isUserFollowed(user: JSONObject): Boolean = if (accounts.state.value.anonymous)
        accounts.localContains("follows", user.optString("uid"))
        else listOf("isFollow", "is_follow", "followed").any { user.optString(it) in setOf("1", "true") }

    override fun isFeedFavorited(feed: JSONObject): Boolean = if (accounts.state.value.anonymous)
        accounts.localContains("favorites", feed.optString("id"))
        else api.isFeedFavorited(feed)

    override suspend fun setPublicIdentity(user: JSONObject) {
        val revision = accounts.state.value.revision
        check(accounts.state.value.anonymous) { "当前不是匿名账户" }
        val local = accounts.exportLocal()
        accounts.updateProfile(local.getString("activeProfileId"), local.getString("name"), local.getString("avatar"), user, expectedRevision = revision)
    }

    override suspend fun followUser(user: JSONObject, following: Boolean): Boolean {
        val revision = accounts.state.value.revision
        val uid = user.optString("uid")
        require(uid.matches(Regex("[1-9][0-9]*"))) { "用户标识无效" }
        if (accounts.state.value.anonymous) {
            accounts.toggleLocal("follows", uid, JSONObject().put("uid", uid).put("username", user.optString("username")).put("userAvatar", user.optString("userAvatar")), expectedRevision = revision)
            return isUserFollowed(user)
        } else {
            requireSession(session())
            api.request(if (following) "/v6/user/unfollow" else "/v6/user/follow", if (following) "GET" else "POST", mapOf("uid" to uid))
        }
        return !following
    }

    override suspend fun uploadFeedImage(bytes: ByteArray): String {
        val owner = session()
        requireSession(owner)
        var uid = accounts.state.value.uid
        if (uid.isEmpty()) uid = api.request("/v6/account/checkLoginInfo").optJSONObject("data")?.optString("uid").orEmpty()
        return uploadImage(bytes, uid, false, owner)
    }

    override suspend fun uploadMessageImage(bytes: ByteArray, uid: String) = uploadImage(bytes, uid, true, session())

    private suspend fun uploadImage(bytes: ByteArray, uid: String, message: Boolean, owner: ApiSession): String = withContext(Dispatchers.IO) {
        requireSession(owner)
        require(uid.matches(Regex("[1-9][0-9]*"))) { "登录状态无效" }
        val (width, height) = pngDimensions(bytes)
        val prepare = api.request("/v6/upload/ossUploadPrepare", "POST", body = mapOf(
            "uploadBucket" to if (message) "message" else "image", "uploadDir" to if (message) "message" else "feed",
            "is_anonymous" to "0", "toUid" to uid, "feed_type" to if (message) "" else "feed",
            "uploadFileList" to JSONArray().put(JSONObject().put("name", if (message) "message.png" else "feed.png")
                .put("resolution", "${width}x$height").put("md5", bytes.toByteString().md5().hex()).put("hdr", 0)).toString(),
        ))
        requireSession(owner)
        val data = prepare.optJSONObject("data") ?: throw ApiException("未获得上传凭据")
        val info = data.optJSONArray("fileInfo")?.optJSONObject(0) ?: throw ApiException("未获得上传凭据")
        val credentials = data.optJSONObject("uploadPrepareInfo") ?: throw ApiException("未获得上传凭据")
        if (info.optString("url").isNotEmpty()) return@withContext validImageUrl(info.getString("url"))
        val endpoint = credentials.optString("endPoint").let { if (it.startsWith("http")) it else "https://$it" }.toHttpUrlOrNull()
        val bucket = credentials.optString("bucket")
        val key = info.optString("uploadFileName")
        require(endpoint != null && endpoint.host.endsWith(".aliyuncs.com") && endpoint.username.isEmpty() && endpoint.password.isEmpty() &&
            bucket.matches(Regex("[a-z0-9-]+")) && key.isNotBlank() && ".." !in key && !key.startsWith('/')) { "上传地址无效" }
        val access = credentials.optString("accessKeyId")
        val secret = credentials.optString("accessKeySecret")
        val token = credentials.optString("securityToken")
        require(access.isNotEmpty() && secret.isNotEmpty() && token.isNotEmpty()) { "上传凭据不完整" }
        val date = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US).apply { timeZone = TimeZone.getTimeZone("GMT") }.format(Date())
        val digest = bytes.toByteString().md5().base64()
        val sign = "PUT\n$digest\nimage/png\n$date\nx-oss-callback:$UPLOAD_CALLBACK\nx-oss-callback-var:$UPLOAD_CALLBACK_VAR\nx-oss-security-token:$token\n/$bucket/$key"
        val signature = sign.encodeUtf8().hmacSha1(secret.encodeUtf8()).base64()
        val url = endpoint.newBuilder().scheme("https").host("$bucket.${endpoint.host}").port(443).encodedPath("/").query(null).fragment(null)
            .addPathSegments(key).build()
        val request = Request.Builder().url(url).put(bytes.toRequestBody("image/png".toMediaType()))
            .header("Authorization", "OSS $access:$signature").header("Content-MD5", digest).header("Date", date)
            .header("x-oss-callback", UPLOAD_CALLBACK).header("x-oss-callback-var", UPLOAD_CALLBACK_VAR).header("x-oss-security-token", token).build()
        requireSession(owner)
        uploadClient.newCall(request).await().use { if (!it.isSuccessful) throw ApiException("图片上传失败（${it.code}）") }
        requireSession(owner)
        validImageUrl("${credentials.optString("uploadImagePrefix", "https://image.coolapk.com")}/$key")
    }

    companion object {
        internal fun pngDimensions(bytes: ByteArray): Pair<Int, Int> {
            require(bytes.size in 24..(16 * 1024 * 1024) && bytes.take(8) == listOf(137,80,78,71,13,10,26,10).map { it.toByte() }) { "图片格式或大小无效" }
            val width = ByteBuffer.wrap(bytes, 16, 4).int
            val height = ByteBuffer.wrap(bytes, 20, 4).int
            require(width > 0 && height > 0 && width.toLong() * height <= 64_000_000) { "图片尺寸无效" }
            return width to height
        }
        internal fun validImageUrl(raw: String): String {
            val url = raw.toHttpUrlOrNull()
            require(url != null && url.username.isEmpty() && url.password.isEmpty() &&
                (url.host.endsWith(".coolapk.com") || url.host.endsWith(".aliyuncs.com"))) { "图片地址无效" }
            return url.newBuilder().scheme("https").port(443).build().toString()
        }
    }
}
