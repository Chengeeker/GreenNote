package com.green.note.settings

import com.green.note.account.AccountRepository
import com.green.note.account.LocalAccounts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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

    fun backupUrl(config: WebDavConfig): HttpUrl = normalize(config.url).newBuilder().apply {
        segments(config.directory).forEach { addPathSegment(it) }
        addPathSegment("greennote_settings_latest.json")
    }.build()
}

class WebDavService(private val client: OkHttpClient = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
    .readTimeout(20, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()) {
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
        client.newCall(Request.Builder().url(WebDavAddress.backupUrl(config))
            .header("Authorization", Credentials.basic(config.username, password, Charsets.UTF_8)).build()).execute().use { response ->
            if (response.code != 200) return@withContext null
            val body = response.body ?: return@withContext null
            require(body.contentLength() <= MAX_BACKUP_BYTES) { "备份超过 20 MB，无法恢复" }
            val output = ByteArrayOutputStream()
            body.byteStream().use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size().toLong() + count <= MAX_BACKUP_BYTES) { "备份超过 20 MB，无法恢复" }
                    output.write(buffer, 0, count)
                }
            }
            JSONObject(output.toString("UTF-8"))
        }
    }

    companion object { const val MAX_BACKUP_BYTES = 20L * 1024 * 1024 }
}

data class CheckedBackup(val settings: AppPreferences, val config: WebDavConfig, val local: JSONObject?, val credentials: Pair<String, String>?)

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
        return CheckedBackup(settings, config, local, credentials)
    }
}

class WebDavBackups(private val settings: SettingsStore, private val accounts: AccountRepository, private val validateCookie: suspend (String) -> JSONObject) {
    suspend fun export(config: WebDavConfig, includeCredentials: Boolean): JSONObject {
        val preferences = JSONObject(settings.state.value.asMap()).put("webDavUrl", config.url).put("webDavUsername", config.username).put("webDavDirectory", config.directory)
        return JSONObject().put("app", "Greennote").put("version", if (includeCredentials) 3 else 2)
            .put("preferences", preferences).put("localAccount", LocalAccounts.validate(accounts.exportLocal()))
            .put("exported_at", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.ROOT).format(Date()))
            .apply { if (includeCredentials) put("credentials", JSONObject().put("cookie", accounts.state.value.cookie)
                .put("webDavPassword", accounts.readSecret(PASSWORD_KEY).orEmpty())) }
    }

    suspend fun restore(backup: JSONObject): Pair<WebDavConfig, String> = restoreMutex.withLock {
        val checked = BackupFormat.validate(backup)
        val before=settings.backupSnapshot()
        val oldSettings=before.preferences;val oldConfig=before.config
        val oldAccount=accounts.state.value
        val oldPassword = accounts.readSecret(PASSWORD_KEY)
        var appliedSettings:SettingsBackupSnapshot?=null
        var appliedAccount:AccountState?=null
        var appliedPassword:String?=null;var passwordWritten=false
        BackupRestoreWrites(
            writePreferences = { preferences, config -> withContext(NonCancellable){appliedSettings=settings.replaceBackup(before,preferences,config)} },
            writeLocal = { local -> withContext(NonCancellable){appliedAccount=accounts.restoreLocalFromBackup(local,oldAccount)} },
            rollbackLocal = { appliedAccount?.let{accounts.restoreLocalBackupIfUnchanged(oldAccount.localJson,it)} },
            writePassword = { next -> withContext(NonCancellable){check(accounts.compareAndSetSecret(PASSWORD_KEY,oldPassword,next)){"WebDAV 密码已改变，请重新恢复备份"};appliedPassword=next;passwordWritten=true} },
            rollbackPreferences = { appliedSettings?.let{settings.replaceBackup(it,before.preferences,before.config)} },
            rollbackPassword = { if(passwordWritten)check(accounts.compareAndSetSecret(PASSWORD_KEY,appliedPassword,oldPassword)){"WebDAV 密码已改变，已保留最新密码"} },
        ).apply(checked, oldSettings, oldConfig, oldPassword)
        val message = if (checked.credentials != null && checked.credentials.first.isNotEmpty()) {
            try {
                accounts.acceptCookie(checked.credentials.first) { cookie ->
                    com.green.note.account.requireLocalRestoreOwnership(appliedAccount ?: oldAccount,accounts.state.value)
                    validateCookie(cookie)
                }
                "全量备份已恢复。酷安登录凭据已验证并恢复。"
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { "全量备份已恢复。酷安登录凭据验证失败，当前登录态未替换；可稍后重新恢复。" }
        } else if (checked.credentials != null) "全量备份已恢复。备份未包含酷安登录凭据。"
        else if (oldConfig.url != checked.config.url || oldConfig.username != checked.config.username) "设置已恢复；服务器或用户名已更改，请重新输入 WebDAV 密码。"
        else "备份已恢复；匿名数据副本可在匿名账户页找回。"
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
