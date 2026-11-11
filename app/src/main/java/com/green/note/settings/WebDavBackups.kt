package com.green.note.settings

import com.green.note.account.AccountRepository
import com.green.note.account.AccountMode
import com.green.note.account.LocalAccounts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.NonCancellable
import com.green.note.account.AccountState
import okhttp3.Credentials
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

object WebDavAddress {
    fun normalize(value: String): HttpUrl {
        var input = value.trim()
        require(input.isNotEmpty()) { "请输入 WebDAV 服务器地址" }
        if (!input.startsWith("http://") && !input.startsWith("https://")) input = "https://$input"
        val url = input.toHttpUrlOrNull() ?: throw IllegalArgumentException("WebDAV 地址无效")
        require(url.username.isEmpty() && url.password.isEmpty() && url.query == null && url.fragment == null) { "WebDAV 地址无效" }
        val loopback = url.host == "localhost" || url.host == "::1" || url.host.matches(Regex("127\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"))
        require(url.isHttps || loopback) { "WebDAV 必须使用 HTTPS；HTTP 仅允许本机回环地址" }
        return if (url.encodedPath.endsWith('/')) url else url.newBuilder().addPathSegment("").build()
    }

    fun segments(value: String): List<String> {
        val parts = value.trim().split('/').filter { it.isNotEmpty() }
        require(parts.isNotEmpty() && parts.none { it == "." || it == ".." || '\\' in it || it.any { char -> char.code < 32 } }) { "备份目录无效" }
        return parts
    }

    fun backupUrl(config: WebDavConfig, legacyFlutter: Boolean = false): HttpUrl {
        val base = normalize(config.url)
        return base.newBuilder().apply {
            // Flutter's Uri.pathSegments retained a trailing empty segment below a non-root base.
            if (legacyFlutter && base.encodedPath != "/") encodedPath(base.encodedPath + "/")
            segments(config.directory).forEach { addPathSegment(it) }
            addPathSegment("greennote_settings_latest.json")
        }.build()
    }
}

class WebDavService(client: OkHttpClient = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
    .readTimeout(20, TimeUnit.SECONDS).build()) {
    private val client = client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    suspend fun test(config: WebDavConfig, password: String): Boolean = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(WebDavAddress.normalize(config.url)).header("Authorization", Credentials.basic(config.username, password, Charsets.UTF_8))
            .header("Depth", "0").method("PROPFIND", ByteArray(0).toRequestBody()).build()
        client.newCall(request).execute().use { it.code == 200 || it.code == 207 }
    }

    suspend fun upload(config: WebDavConfig, password: String, data: JSONObject): Boolean = withContext(Dispatchers.IO) {
        val authorization = Credentials.basic(config.username, password, Charsets.UTF_8)
        var directory = WebDavAddress.normalize(config.url)
        for (segment in WebDavAddress.segments(config.directory)) {
            directory = directory.newBuilder().addPathSegment(segment).addPathSegment("").build()
            client.newCall(Request.Builder().url(directory).header("Authorization", authorization)
                .method("MKCOL", ByteArray(0).toRequestBody()).build()).execute().use {
                if (it.code !in listOf(200, 201, 405)) return@withContext false
            }
        }
        client.newCall(Request.Builder().url(WebDavAddress.backupUrl(config)).header("Authorization", authorization)
            .put(data.toString(2).toRequestBody("application/json; charset=utf-8".toMediaType())).build()).execute().use {
            it.code in listOf(200, 201, 204)
        }
    }

    suspend fun download(config: WebDavConfig, password: String): JSONObject? = withContext(Dispatchers.IO) {
        val locations = listOf(WebDavAddress.backupUrl(config), WebDavAddress.backupUrl(config, legacyFlutter = true)).distinct()
        for (location in locations) {
            val backup = downloadResponse(location, Credentials.basic(config.username, password, Charsets.UTF_8)).use { response ->
                when (response.code) {
                    200 -> Unit
                    404 -> return@use null
                    401 -> error("WebDAV 身份验证失败（401），请检查账号和应用密码 / Token")
                    403 -> error("WebDAV 拒绝读取备份（403），请检查文件读取权限")
                    in 300..399 -> error("WebDAV 返回不支持的下载响应（${response.code}），未恢复任何资料")
                    429 -> error("WebDAV 请求过于频繁（429），请稍后重试")
                    else -> error("WebDAV 读取失败（HTTP ${response.code}），请检查服务状态后重试")
                }
                val body = response.body ?: error("WebDAV 返回空内容，未恢复任何资料")
                require(body.contentLength() <= MAX_BACKUP_BYTES) { "备份超过 20 MB，无法恢复" }
                val output = ByteArrayOutputStream()
                body.byteStream().use { input ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        coroutineContext.ensureActive()
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size().toLong() + count <= MAX_BACKUP_BYTES) { "备份超过 20 MB，无法恢复" }
                        output.write(buffer, 0, count)
                    }
                }
                try { JSONObject(output.toString("UTF-8")) }
                catch (_: org.json.JSONException) { error("下载内容不是有效的 JSON 备份，未恢复任何资料") }
            }
            if (backup != null) return@withContext backup
        }
        null
    }

    private suspend fun downloadResponse(location: HttpUrl, authorization: String): Response {
        var request = Request.Builder().url(location).header("Authorization", authorization).build()
        val visited = mutableSetOf<HttpUrl>()
        for (hop in 0..5) {
            coroutineContext.ensureActive()
            check(visited.add(request.url)) { "WebDAV 下载地址循环跳转，未恢复任何资料" }
            val response = client.newCall(request).execute()
            if (response.code !in listOf(301, 302, 303, 307, 308)) return response
            response.use {
                check(hop < 5) { "WebDAV 下载跳转次数过多，未恢复任何资料" }
                val target = response.header("Location")?.takeIf { it.isNotBlank() }?.let(request.url::resolve)
                    ?.newBuilder()?.fragment(null)?.build()
                    ?: error("WebDAV 下载跳转缺少有效地址（${response.code}），未恢复任何资料")
                check(target.username.isEmpty() && target.password.isEmpty()) { "WebDAV 下载跳转地址包含账号信息，已停止恢复" }
                val sameOrigin = target.scheme == request.url.scheme && target.host == request.url.host && target.port == request.url.port
                check(target.isHttps || sameOrigin) { "WebDAV 下载跳转未使用 HTTPS，已停止恢复" }
                // Signed CDN downloads need no DAV credentials; never reattach them after leaving the origin.
                val auth = request.header("Authorization").takeIf { sameOrigin }
                request = Request.Builder().url(target).apply { if (auth != null) header("Authorization", auth) }.build()
            }
        }
        error("WebDAV 下载跳转次数过多，未恢复任何资料")
    }

    companion object { const val MAX_BACKUP_BYTES = 20L * 1024 * 1024 }
}

data class CheckedBackup(val settings: AppPreferences, val config: WebDavConfig, val local: JSONObject?, val credentials: Pair<String, String>?, val accountMode: AccountMode? = null)

object BackupFormat {
    fun validate(backup: JSONObject): CheckedBackup {
        require(backup.optString("app") == "Greennote" && backup.opt("version") in listOf(1, 2, 3)) { "这不是兼容的 Greennote 设置备份" }
        val version = backup.getInt("version")
        val values = backup.optJSONObject("preferences") ?: throw IllegalArgumentException("备份中缺少设置内容")
        listOf("themeMode", "dynamicColor", "themeSeedArgb", "enableHaptics", "webDavUrl", "webDavUsername", "webDavDirectory").forEach {
            require(values.has(it)) { "备份中的设置不完整" }
        }
        fun integer(key: String, default: Int, predicate: (Int) -> Boolean): Int {
            val value = values.opt(key) ?: default
            require(value is Int || value is Long) { "备份中的设置格式无效" }
            val number=(value as Number).toLong()
            require(number in Int.MIN_VALUE..Int.MAX_VALUE && predicate(number.toInt())) { "备份中的设置格式无效" }
            return number.toInt()
        }
        fun bool(key: String, default: Boolean): Boolean {
            val value = values.opt(key) ?: default
            require(value is Boolean) { "备份中的设置格式无效" }
            return value
        }
        fun string(key: String, limit: Int): String {
            val value = values.opt(key)
            require(value is String && value.length <= limit) { "备份中的设置格式无效" }
            return value
        }
        val seed = values.opt("themeSeedArgb")
        require((seed is Int || seed is Long) && (seed as Number).toLong() in 0..0xFFFFFFFF) { "备份中的设置格式无效" }
        val scale = values.opt("fontScale") ?: 1.0
        require(scale is Number && scale.toDouble().isFinite() && scale.toDouble() in .8..1.5) { "备份中的设置格式无效" }
        val settings = AppPreferences(
            integer("themeMode", 0) { it in 0..2 }, bool("dynamicColor", false), (seed as Number).toLong(),
            bool("enableHaptics", true), bool("floatingNavBar", true), bool("liquidGlassNavBar", true), bool("pureBlackDark", false),
            bool("useCustomFontWeight", false), integer("customFontWeightDelta", 0) { it in AppPreferences.weightDeltas }, scale.toFloat(),
            integer("autoClearCacheThresholdMb",200){it>=0},
            integer("imageSavePathType",0){it in 0..2},
            integer("videoSavePathType",0){it in 0..2},
            translucentNavigationGlass = bool("translucentNavigationGlass", false),
        )
        val config = WebDavConfig(string("webDavUrl", 2048), string("webDavUsername", 512), string("webDavDirectory", 256))
        val local = if (version == 1) null else LocalAccounts.validate(backup.getJSONObject("localAccount"))
        val credentials = if (version == 3) {
            val data = backup.optJSONObject("credentials") ?: throw IllegalArgumentException("备份中的账号凭据格式无效")
            val cookie = data.opt("cookie"); val password = data.opt("webDavPassword")
            require(cookie is String && cookie.length <= 65536 && cookie.none { it.code < 32 || it.code == 127 } && password is String && password.length <= 16384) { "备份中的账号凭据格式无效" }
            cookie to password
        } else null
        val mode = if (version >= 2 && backup.has("accountMode")) {
            AccountMode.entries.firstOrNull { it.name == backup.opt("accountMode") }
                ?: throw IllegalArgumentException("备份中的登录模式无效")
        } else null
        return CheckedBackup(settings, config, local, credentials, mode)
    }
}

class WebDavBackups(private val settings: SettingsStore, private val accounts: AccountRepository, private val validateCookie: suspend (String) -> JSONObject) {
    suspend fun export(config: WebDavConfig, includeCredentials: Boolean): JSONObject = withContext(Dispatchers.IO) {
        val account = accounts.state.value
        val password = if (includeCredentials) accounts.readSecret(PASSWORD_KEY).orEmpty() else null
        check(accounts.state.value.revision == account.revision) { "账号资料已改变，请重新备份" }
        val preferences = JSONObject(settings.state.value.asMap()).put("webDavUrl", config.url).put("webDavUsername", config.username).put("webDavDirectory", config.directory)
        JSONObject().put("app", "Greennote").put("version", if (includeCredentials) 3 else 2)
            .put("preferences", preferences).put("localAccount", LocalAccounts.validate(JSONObject(account.localJson)))
            .put("accountMode", account.mode.name)
            .put("exported_at", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.ROOT).format(Date()))
            .apply { if (includeCredentials) put("credentials", JSONObject().put("cookie", account.requestCookie)
                .put("webDavPassword", password)) }
    }

    suspend fun restore(backup: JSONObject): Pair<WebDavConfig, String> = restoreMutex.withLock {
        val checked = withContext(Dispatchers.IO) { BackupFormat.validate(backup) }
        val before=settings.backupSnapshot()
        val oldSettings=before.preferences;val oldConfig=before.config
        val oldAccount=accounts.state.value
        val oldPassword = accounts.readSecret(PASSWORD_KEY)
        var appliedSettings:SettingsBackupSnapshot?=null
        var appliedAccount:AccountState?=null
        var appliedPassword:String?=null;var passwordWritten=false
        BackupRestoreWrites(
            writePreferences = { preferences, config -> withContext(NonCancellable){appliedSettings=settings.replaceBackup(before,preferences,config)} },
            writeLocal = { local -> withContext(NonCancellable){appliedAccount=accounts.restoreLocalFromBackup(local,oldAccount,
                activateAnonymous = checked.accountMode == AccountMode.ANONYMOUS && (checked.credentials != null || !oldAccount.authenticated))} },
            rollbackLocal = { appliedAccount?.let{accounts.restoreLocalBackupIfUnchanged(oldAccount,it)} },
            writePassword = { next -> withContext(NonCancellable){check(accounts.compareAndSetSecret(PASSWORD_KEY,oldPassword,next)){"WebDAV 密码已改变，请重新恢复备份"};appliedPassword=next;passwordWritten=true} },
            rollbackPreferences = { appliedSettings?.let{settings.replaceBackup(it,before.preferences,before.config)} },
            rollbackPassword = { if(passwordWritten)check(accounts.compareAndSetSecret(PASSWORD_KEY,appliedPassword,oldPassword)){"WebDAV 密码已改变，已保留最新密码"} },
        ).apply(checked, oldSettings, oldConfig, oldPassword)
        val message = if (checked.accountMode == AccountMode.ANONYMOUS) {
            if (accounts.state.value.anonymous) "匿名账户及头像、用户名、UID、关注和收藏已恢复，已进入原匿名账户。"
            else "匿名账户资料已恢复，当前账号登录保持不变，可在匿名账户管理中切换。"
        } else if (checked.credentials != null && checked.credentials.first.isNotEmpty() && checked.accountMode != AccountMode.GUEST) {
            try {
                accounts.acceptCookie(checked.credentials.first) { cookie ->
                    com.green.note.account.requireLocalRestoreOwnership(appliedAccount ?: oldAccount,accounts.state.value)
                    validateCookie(cookie)
                }
                "全量备份已恢复。酷安登录凭据已验证并恢复。"
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { "设置和匿名资料已恢复，但账号登录未恢复：登录凭据未通过验证，请检查网络后重试或重新登录。" }
        } else if (checked.credentials != null) "设置和匿名资料已恢复。备份未包含有效的账号登录凭据，匿名资料可切换后使用。"
        else if (checked.accountMode == AccountMode.COOKIE) "设置和匿名资料已恢复。安全备份不包含登录凭据，请重新登录账号。"
        else if (oldConfig.url != checked.config.url || oldConfig.username != checked.config.username) "设置已恢复；服务器或用户名已更改，请重新输入 WebDAV 密码。"
        else "设置和匿名资料已恢复，匿名资料可切换后使用。"
        checked.config to message
    }

    companion object { const val PASSWORD_KEY = "greennote.webdav.password";private val restoreMutex=Mutex() }
}

internal class BackupRestoreWrites(
    private val writePreferences: suspend (AppPreferences, WebDavConfig) -> Unit,
    private val writeLocal: suspend (JSONObject) -> Unit,
    private val rollbackLocal: suspend () -> Unit,
    private val writePassword: suspend (String?) -> Unit,
    private val rollbackPreferences:(suspend ()->Unit)?=null,
    private val rollbackPassword:(suspend ()->Unit)?=null,
) {
    suspend fun apply(checked: CheckedBackup, oldSettings: AppPreferences, oldConfig: WebDavConfig, oldPassword: String?) {
        var restoredLocal = false
        try {
            checked.local?.let { restoredLocal = true;writeLocal(it) }
            writePreferences(checked.settings, checked.config)
            if (checked.credentials != null) writePassword(checked.credentials.second.ifEmpty { null })
            else if (oldConfig.url != checked.config.url || oldConfig.username != checked.config.username) writePassword(null)
        } catch (error: Exception) {
            // Every rollback is attempted even when another store also fails to roll back.
            withContext(kotlinx.coroutines.NonCancellable) {
                runCatching { if(rollbackPreferences!=null)rollbackPreferences.invoke()else writePreferences(oldSettings, oldConfig) }.exceptionOrNull()?.let(error::addSuppressed)
                runCatching { if(rollbackPassword!=null)rollbackPassword.invoke()else writePassword(oldPassword) }.exceptionOrNull()?.let(error::addSuppressed)
                if (restoredLocal) runCatching { rollbackLocal() }.exceptionOrNull()?.let(error::addSuppressed)
            }
            throw error
        }
    }
}
