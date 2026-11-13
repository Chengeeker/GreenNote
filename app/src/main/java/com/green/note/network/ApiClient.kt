package com.green.note.network

import com.green.note.content.ContentApi
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okio.ByteString.Companion.encodeUtf8
import org.json.JSONArray
import org.json.JSONObject
import kotlin.coroutines.resumeWithException

class ApiClient(
    private val session: () -> ApiSession,
    private val signer: RequestSigner,
    private val http: OkHttpClient = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS).callTimeout(45, TimeUnit.SECONDS)
        .dispatcher(Dispatcher().apply { maxRequestsPerHost = 32 })
        .connectionPool(ConnectionPool(32, 30, TimeUnit.SECONDS))
        .followRedirects(false).followSslRedirects(false).build(),
    private val elapsedNanos: () -> Long = System::nanoTime,
    verifiedReadSessionStore: VerifiedReadSessionStore? = null,
    wallClockMillis: () -> Long = System::currentTimeMillis,
) : ContentApi {
    private val readSessions = VerifiedReadSessions(session, verifiedReadSessionStore, wallClockMillis)
    private data class ImageOwner(val session: ApiSession)
    override fun imageCacheScope(): String = session().let { owner ->
        "${owner.revision}:${owner.anonymous}:${owner.effectiveCookie}".encodeUtf8().sha256().hex()
    }

    fun imageHttpClient(): OkHttpClient = http.newBuilder().followRedirects(true).followSslRedirects(false)
        .addInterceptor { chain ->
            val request = chain.request()
            val expected = request.header("X-GreenNote-Image-Scope")
            if (expected != null && expected != imageCacheScope()) throw IOException("图片会话已变更")
            chain.proceed(request.newBuilder().tag(ImageOwner::class.java, ImageOwner(session())).build())
        }
        .addNetworkInterceptor { chain ->
            val original = chain.request()
            val expectedScope = original.header("X-GreenNote-Image-Scope")
            if (expectedScope != null && expectedScope != imageCacheScope()) throw IOException("图片会话已变更")
            val owner = original.tag(ImageOwner::class.java)?.session ?: throw IOException("图片请求缺少会话上下文")
            val request = original.newBuilder()
            original.headers.names().filter { it.equals("Cookie", true) || it.startsWith("X-", true) }.forEach(request::removeHeader)
            if (ApiRules.trusted(original.url)) {
                if (owner != session()) throw IOException("图片会话已变更")
                headers(owner).forEach { (key, value) -> request.header(key, value) }
                request.header("X-App-Token", signer.token(owner.device))
                if (owner.authenticated) request.header("Cookie", owner.effectiveCookie)
                request.header("Cache-Control", "no-store")
            }
            val response = chain.proceed(request.build())
            if (ApiRules.trusted(original.url) && owner != session()) { response.close(); throw IOException("图片会话已变更") }
            response
        }.build()
    private data class ReadVerification(val request: CommentCaptchaRequest?, val context: String, val cookieProof: String?)
    private data class VerifiedCommentResponse(val request: CommentCaptchaRequest, val context: String, val expires: Long, val json: String)
    private val verificationIssuer = Any()
    // One short-lived handoff to the list loader, never a persistent or general response cache.
    private var verifiedCommentResponse: VerifiedCommentResponse? = null

    override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
        val owner = session()
        readSessions.restore(owner)
        takeVerifiedCommentResponse(path, method, query, body, owner)?.let { cached ->
            return withContext(Dispatchers.Default) {
                val result = JSONObject(cached.json)
                if (owner != session() || cached.context != readSessions.context(owner, cached.request.url)) throw ApiException("账号、设备或会话已变更，已忽略旧验证结果")
                result
            }
        }
        suspend fun fetch(target: String): JSONObject {
            try { return execute(target, method, query, body, owner, owner, true) }
            catch (failure: ApiException) {
                if (failure is CaptchaRequired || failure is UnsupportedCaptcha || owner != session() || !method.equals("GET", true) ||
                    ApiRules.resolve(target, emptyMap()).encodedPath != "/v6/feed/replyList" ||
                    failure.message?.contains("评论接口异常") != true || failure.message?.contains("升级") != true) throw failure
                return execute(target, method, query, body, owner, owner, true, modernReplies = true)
            }
        }
        if (method.equals("GET", true) && path in setOf("/v6/feed/replyList", "/v6/feed/hotReplyList")) {
            try { return fetch("https://api2.coolapk.com$path") }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (challenge: CaptchaRequired) { throw challenge }
            catch (failure: Exception) { if (owner != session()) throw failure }
        }
        return fetch(path)
    }

    private fun takeVerifiedCommentResponse(path: String, method: String, query: Map<String, String>, body: Map<String, String>?, owner: ApiSession): VerifiedCommentResponse? =
        synchronized(this) {
            val cached = verifiedCommentResponse ?: return@synchronized null
            if (owner != session() || cached.context != readSessions.context(owner, cached.request.url) || elapsedNanos() >= cached.expires) {
                verifiedCommentResponse = null
                return@synchronized null
            }
            if (!method.equals("GET", true) || body != null) return@synchronized null
            val targets = if (path in setOf("/v6/feed/replyList", "/v6/feed/hotReplyList"))
                listOf("https://api2.coolapk.com$path", path) else listOf(path)
            val matched = targets.any { target ->
                val url = ApiRules.resolve(target, query)
                // A previously challenged upgraded request is already verified. Reuse that exact
                // profile instead of sending the older request (and its upgrade probe) again.
                val profiles = if (url.encodedPath == "/v6/feed/replyList") listOf(false, true) else listOf(false)
                profiles.any { modern -> cached.request.matches(url, modern) }
            }
            if (!matched) return@synchronized null
            verifiedCommentResponse = null
            cached
        }

    suspend fun validateCookie(candidate: String): JSONObject {
        require(candidate.length <= 32768 && candidate.none { it.code < 32 || it.code == 127 }) { "Cookie格式无效" }
        val owner = session()
        return execute("/v6/account/checkLoginInfo", "GET", emptyMap(), null,
            owner, owner.copy(cookie = candidate, anonymous = false), false)
    }

    suspend fun logoutRemote() {
        val owner = session()
        if (!owner.authenticated) return
        val request = Request.Builder().url("https://account.coolapk.com/auth/logout")
            .header("Cookie", owner.effectiveCookie).header("User-Agent", headers(owner).getValue("User-Agent")).build()
        http.newCall(request).await().use { response ->
            if (!response.isSuccessful && !response.isRedirect) throw ApiException("远程退出失败，本机登录状态将清除")
        }
    }

    override suspend fun resolveApkDownloadUrl(packageName: String, appId: String, versionCode: String): String = withContext(Dispatchers.IO) {
        require(packageName.isNotBlank() && appId.isNotBlank() && versionCode.isNotBlank()) { "应用缺少下载所需的版本信息" }
        val owner = session()
        val url = ApiRules.resolve("/v6/apk/download", mapOf("extra" to "", "pn" to packageName, "aid" to appId, "vc" to versionCode))
        val request = Request.Builder().url(url).post(FormBody.Builder().build()).apply {
            headers(owner).forEach { (key,value) -> header(key,value) }
            header("X-App-Token", signer.token(owner.device))
            if (owner.authenticated) header("Cookie", owner.effectiveCookie)
        }.build()
        http.newCall(request).await().use { response ->
            if (owner != session()) throw ApiException("账号或设备已变更，已忽略旧请求")
            if (response.code == 403) throw ApiException("酷安暂时拒绝了下载请求")
            if (response.code !in 200..399) throw ApiException("暂时无法获取应用下载地址")
            val location = response.header("Location")?.let(url::resolve)
            if (location == null || !location.isHttps || location.username.isNotEmpty() || location.password.isNotEmpty()) throw ApiException("酷安没有返回有效的下载地址")
            location.toString()
        }
    }

    suspend fun requestPublic(path: String, query: Map<String, String> = emptyMap()): JSONObject {
        val owner = session()
        return execute(path, "GET", query, null, owner, owner.copy(cookie = "", anonymous = true), false)
    }

    suspend fun multipart(path: String, fields: Map<String, String>, query: Map<String, String> = emptyMap(), avatar: ByteArray? = null): JSONObject {
        require(path in setOf("/v6/collection/create", "/v6/account/changeAvatar", "/v6/message/send", "/v6/feed/createFeed")) { "不支持的提交类型" }
        val owner = session()
        if (!owner.authenticated) throw ApiException("请先使用酷安账号登录")
        val body = MultipartBody.Builder().setType(MultipartBody.FORM).apply {
            fields.forEach { (key, value) -> addFormDataPart(key, value) }
            if (avatar != null) {
                require(avatar.size in 24..(16 * 1024 * 1024)) { "图片大小无效" }
                addFormDataPart("imgFile", "avatar.png", avatar.toRequestBody("image/png".toMediaType()))
            }
        }.build()
        return execute(path, "POST", query, null, owner, owner, true, extraBody = body)
    }

    suspend fun verifyFeedDetail(id: String, error: CaptchaRequired, validate: String): JSONObject {
        require(id.matches(Regex("[1-9][0-9]*"))) { "动态标识无效" }
        val owner = session()
        readSessions.restore(owner)
        if (error.context != readSessions.context(owner, ApiRules.resolve("/v6/feed/detail", emptyMap()))) throw ApiException("账号、设备或会话已变更，请重新加载榜单")
        val proof = error.challenge.proof(validate) ?: throw ApiException("验证结果无效，请重试")
        val query = mutableMapOf("id" to id)
        if (error.challenge.field.isNotEmpty()) query[error.challenge.field] = proof
        return execute("/v6/feed/detail", "GET", query, null, owner, owner, true,
            explicitProof = proof.takeIf { error.challenge.field.isEmpty() },
            verification = ReadVerification(null, error.context, proof.takeIf { error.challenge.field.isEmpty() }))
    }

    suspend fun verifyCommentRequest(error: CaptchaRequired, validate: String) {
        val request = error.request?.takeIf { it.issuer === verificationIssuer && ApiRules.commentRead(it.url) }
            ?: throw ApiException("缺少当前评论的验证请求，请重新加载评论")
        val owner = session()
        readSessions.restore(owner)
        if (error.context != readSessions.context(owner, request.url)) throw ApiException("账号、设备或会话已变更，请重新加载评论")
        val proof = error.challenge.proof(validate) ?: throw ApiException("验证结果无效，请重试")
        if (!request.claim()) throw ApiException("这次验证已提交，请重新加载评论后重试")
        synchronized(this) { verifiedCommentResponse = null }
        val target = if (error.challenge.field.isEmpty()) request.url else request.url.newBuilder()
            .setQueryParameter(error.challenge.field, proof).build()
        // Directly replay the challenged GET. Do not enter host fallback, version upgrades, or
        // another interactive verification from here. A second challenge returns to the caller.
        execute(target.toString(), "GET", emptyMap(), null, owner, owner, true,
            explicitProof = proof.takeIf { error.challenge.field.isEmpty() },
            modernReplies = request.modernReplies,
            verification = ReadVerification(request, error.context, proof.takeIf { error.challenge.field.isEmpty() }))
    }

    override fun imageHeaders(url: String): Map<String, String> {
        val parsed = url.toHttpUrlOrNull()
        if (parsed != null && ApiRules.trusted(parsed)) {
            val owner = session()
            return headers(owner).toMutableMap().apply {
                put("X-GreenNote-Image-Scope", imageCacheScope())
                if (owner.authenticated) put("Cookie", owner.effectiveCookie)
                // Image signing must not perform bcrypt on the UI thread; API images use session headers.
            }
        }
        return mapOf("User-Agent" to "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            "Referer" to "https://www.coolapk.com/", "Accept" to "image/avif,image/webp,image/apng,image/*,*/*;q=0.8")
    }

    private suspend fun execute(
        path: String, method: String, query: Map<String, String>, body: Map<String, String>?,
        owner: ApiSession, requestSession: ApiSession, rememberSession: Boolean, explicitProof: String? = null, extraBody: RequestBody? = null,
        modernReplies: Boolean = false,
        verification: ReadVerification? = null,
    ): JSONObject = withContext(Dispatchers.IO) {
        require(method.uppercase() in setOf("GET", "POST")) { "接口方法无效" }
        var requestPath = path
        val params = query.toMutableMap()
        if (path in setOf("/v6/product/feedList", "/product/feedList")) {
            requestPath = "/v6/page/dataList"
            params.putIfAbsent("url", "/page?url=/product/feedList")
            when (params["type"]) { "picture" -> params["type"] = "article"; "ershou" -> params["type"] = "trade" }
        }
        val url = ApiRules.resolve(requestPath, params)
        ApiRules.allow(requestSession, method, url.encodedPath)
        if (rememberSession) readSessions.restore(owner)
        val sentSession = readSessions.prepare(owner, url, rememberSession, explicitProof, verification != null, method.equals("GET", true))
        val requestContext = sentSession.context
        if (verification != null && (owner != session() || verification.context != requestContext)) {
            throw ApiException("账号、设备或会话已变更，请重新加载评论")
        }
        val proof = sentSession.proof
        var cookie = requestSession.effectiveCookie
        if (sentSession.hasSessionOverride) cookie = withCookie(cookie, "SESSID", sentSession.sessionValue.orEmpty())
        if (proof != null) cookie = withCookie(cookie, "validate", java.net.URLEncoder.encode(proof, "UTF-8").replace("+", "%20"))
        val builder = Request.Builder().url(url)
        headers(requestSession, replyList = modernReplies).forEach { (name, value) -> builder.header(name, value) }
        builder.header("X-App-Token", signer.token(requestSession.device, appCode = if (modernReplies) 2609291 else 2604201))
        if (cookie.isNotEmpty()) builder.header("Cookie", cookie)
        if (method.uppercase() == "POST") builder.post(extraBody ?: FormBody.Builder().apply { body.orEmpty().forEach { (k,v) -> add(k,v) } }.build())
        if (verification != null && (owner != session() || verification.context != readSessions.context(owner, url))) {
            throw ApiException("账号、设备或会话已变更，请重新加载评论")
        }
        val response = http.newCall(builder.build()).await()
        response.use {
            if (owner != session()) throw ApiException("账号或设备已变更，已忽略旧请求")
            val responseContext = readSessions.response(owner, url, response.headers, sentSession, rememberSession, verification != null)
            try {
                if (response.isRedirect) throw ApiException("接口返回了重定向，请重新加载")
                val bytes = ByteArrayOutputStream()
                response.body?.byteStream()?.use { stream ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (bytes.size() + count > 20 * 1024 * 1024) throw ApiException("接口响应过大")
                        bytes.write(buffer, 0, count)
                    }
                }
                val text = bytes.toString("UTF-8")
                val root = try {
                    if (text.trimStart().startsWith("[")) JSONObject().put("data", JSONArray(text)).put("status", 0) else JSONObject(text)
                } catch (_: Exception) {
                    ReplyDiagnostics.response(url, if (modernReplies) 2609291 else 2604201, response.code, null, "", false)
                    throw ApiException(when (response.code) { 401 -> "登录状态已失效，请重新登录"; 403 -> "暂时拒绝了请求，可能触发了访问限制"; else -> "服务器返回了无法识别的响应" })
                }
                if (owner != session()) throw ApiException("账号或设备已变更，已忽略旧请求")
                val code = (root.opt("status") ?: root.opt("code"))?.toString()?.toIntOrNull()
                val parsedChallenge = CaptchaChallenge.parse(root)
                ReplyDiagnostics.response(url, if (modernReplies) 2609291 else 2604201, response.code, code, root.optString("messageStatus"), parsedChallenge != null)
                parsedChallenge?.let { challenge ->
                    readSessions.challenged(owner, sentSession)
                    val commentRequest = if (rememberSession && owner == requestSession && method.equals("GET", true) &&
                        body == null && extraBody == null && ApiRules.commentRead(url))
                        CommentCaptchaRequest(verification?.request?.url ?: url, modernReplies, verificationIssuer) else null
                    throw CaptchaRequired(challenge, responseContext, root.optString("message").ifBlank { "当前访问需要验证码" }, commentRequest)
                }
                val message = root.optString("message")
                if (root.optString("messageStatus") == "err_request_captcha_v2" || root.isNull("data") &&
                    (message.contains("验证码") || message.contains("captcha", ignoreCase = true))) {
                    readSessions.challenged(owner, sentSession)
                    throw UnsupportedCaptcha()
                }
                if (!response.isSuccessful || code != null && code !in setOf(0, 200)) {
                    throw ApiException(root.optString("message").ifBlank { "接口返回错误（${code ?: response.code}）" })
                }
                val installed = readSessions.succeeded(owner, url, sentSession, responseContext, verification != null, verification?.cookieProof)
                if (verification?.request != null) synchronized(this@ApiClient) {
                    if (installed == null || !readSessions.owns(installed)) {
                        throw ApiException("账号、设备或会话已变更，已忽略旧验证结果")
                    }
                    verifiedCommentResponse = VerifiedCommentResponse(verification.request, responseContext,
                        elapsedNanos() + TimeUnit.SECONDS.toNanos(30), root.toString())
                }
                root
            } catch (failure: Exception) {
                // A server cookie rotation/deletion must not leave an older resumable session on disk.
                withContext(NonCancellable) { readSessions.failed(owner, sentSession) }
                throw failure
            }
        }
    }

    private fun headers(owner: ApiSession, replyList: Boolean = false): Map<String, String> {
        // Upgrade only when the reply endpoint explicitly requires a newer client.
        val version = if (replyList) "16.6.4" else "16.2.0"
        val code = if (replyList) "2609291" else "2604201"
        return mapOf(
            "User-Agent" to "Dalvik/2.1.0 (Linux; U; Android 16) +CoolMarket/$version-$code-universal",
            "X-App-Id" to "com.coolapk.market", "X-App-Version" to version, "X-App-Code" to code,
            "X-App-Supported" to code, "X-Api-Version" to "16", "X-App-Device" to owner.device,
            "X-Dark-Mode" to "0", "X-App-Mode" to "universal", "X-App-Channel" to "coolapk",
            "X-Sdk-Int" to "36", "X-Sdk-Locale" to "zh-CN", "X-Requested-With" to "XMLHttpRequest",
        )
    }

    companion object {
        internal fun withCookie(cookie: String, name: String, value: String) =
            (cookie.split(';').map(String::trim).filter { it.isNotEmpty() && it.substringBefore('=') != name } +
                listOfNotNull("$name=$value".takeIf { value.isNotEmpty() })).joinToString("; ")
    }
}

internal suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) { if (!continuation.isCancelled) continuation.resumeWithException(e) }
        override fun onResponse(call: Call, response: Response) {
            continuation.resume(response) { _, resource, _ -> resource.close() }
        }
    })
}
