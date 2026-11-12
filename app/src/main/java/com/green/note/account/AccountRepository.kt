package com.green.note.account

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.AEADBadTagException
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

enum class AccountMode { GUEST, ANONYMOUS, COOKIE }
data class AccountState(
    val mode: AccountMode = AccountMode.GUEST,
    val cookie: String = "",
    val uid: String = "",
    val username: String = "",
    val avatar: String = "",
    val localJson: String = LocalAccounts.empty().toString(),
    val revision: Long = 0,
    val sessionRevision: Long = 0,
) {
    val anonymous get() = mode == AccountMode.ANONYMOUS
    val authenticated get() = mode == AccountMode.COOKIE && cookie.isNotEmpty()
    val hasAccount get() = anonymous || authenticated
    val requestCookie get() = if (authenticated) cookie else ""
    override fun toString() = "AccountState(mode=$mode, revision=$revision)"
}

enum class AccountKeyFailure { MISSING_OR_UNUSABLE, AUTHENTICATION }
class AccountKeyUnavailableException(val reason: AccountKeyFailure = AccountKeyFailure.MISSING_OR_UNUSABLE) : IllegalStateException(
    if(reason==AccountKeyFailure.AUTHENTICATION) "密文认证失败，可能是密钥不匹配或文件损坏；原文件已保留"
    else "此设备缺少可用的账号密钥，请重试或从原手机恢复应用内备份")

/** Independent encrypted state; existing Flutter preferences and keys are never modified. */
class AccountRepository internal constructor(context: Context, private val accountKey: (Boolean) -> SecretKey) {
    constructor(context: Context) : this(context, ::loadAccountKey)
    private val app = context.applicationContext
    private val file = AtomicFile(File(app.filesDir, "greennote-compose-account-v1.bin"))
    private val mutex = Mutex()
    private val mutable = MutableStateFlow(AccountState())
    val state = mutable.asStateFlow()
    private val membership = LocalMembershipIndex()
    private var rollback: String? = null
    private var secrets = JSONObject()
    private var initialized = false
    private var recoveryAvailable = false

    suspend fun initialize() = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (initialized) return@withLock
            recoveryAvailable = false
            try {
                if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) {
                    val recoverable = File(file.baseFile.path + ".bak").takeIf { it.exists() } ?: file.baseFile
                    require(recoverable.length() in 30..(80L * 1024 * 1024)) { "账户存储格式无效，原文件已保留" }
                    val encrypted = file.readFully()
                    require(encrypted.size in 30..(80 * 1024 * 1024)) { "账户存储格式无效，原文件已保留" }
                    require(encrypted[0] == 1.toByte()) { "账户存储版本无效" }
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, accountKey(false), GCMParameterSpec(128, encrypted.copyOfRange(1, 13)))
                    val saved = JSONObject(String(cipher.doFinal(encrypted.copyOfRange(13, encrypted.size)), Charsets.UTF_8))
                    val local = LocalAccounts.validate(saved.getJSONObject("local"))
                    rollback = saved.optJSONObject("rollback")?.let { LocalAccounts.validate(it).toString() }
                    secrets = saved.optJSONObject("secrets") ?: JSONObject()
                    val mode = AccountMode.valueOf(saved.getString("mode"))
                    val cookie = saved.optString("cookie")
                    require(mode != AccountMode.COOKIE || OfficialLoginSession.hasAccountCookie(cookie)) { "保存的账号凭据无效" }
                    mutable.value = AccountState(mode, cookie, saved.optString("uid"), saved.optString("username"), saved.optString("avatar"), local.toString())
                } else {
                    val legacy = FlutterAccountImport(app).read()
                    if (legacy != null) {
                        initialized = true
                        try { persist(legacy.state, legacy.backup ?: legacy.state.localJson, legacy.secrets) }
                        catch (failure: Exception) { initialized = false; throw failure }
                    }
                }
                initialized = true
            } catch (failure: AccountKeyUnavailableException) {
                recoveryAvailable = true
                throw failure
            } catch (_: AEADBadTagException) {
                recoveryAvailable = true
                throw AccountKeyUnavailableException(AccountKeyFailure.AUTHENTICATION)
            }
        }
    }

    suspend fun recoverAfterTransfer() {
        try { initialize(); return } catch (_: AccountKeyUnavailableException) { }
        withContext(Dispatchers.IO) { mutex.withLock {
            if (initialized) return@withLock
            check(recoveryAvailable) { "请先重新读取账号资料" }
            if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) {
                val encrypted = file.readFully()
                val directory = File(app.noBackupFilesDir, "account-recovery")
                check(directory.isDirectory || directory.mkdirs()) { "无法保留旧账号文件，请检查存储空间" }
                val archive = AtomicFile(File(directory, "account-${UUID.randomUUID()}.bin"))
                val stream = archive.startWrite()
                try { stream.write(encrypted); archive.finishWrite(stream) }
                catch (failure: Exception) { archive.failWrite(stream); throw failure }
                check(archive.readFully().contentEquals(encrypted)) { "旧账号文件备份校验失败" }
            }
            initialized = true
            try {
                persist(AccountState(), backup = null, secretValues = JSONObject())
                recoveryAvailable = false
            } catch (failure: Exception) { initialized = false; throw failure }
        } }
    }

    private fun persist(next: AccountState, backup: String? = rollback, secretValues: JSONObject = secrets) {
        check(initialized) { "账户尚未读取完成" }
        val root = JSONObject().put("mode", next.mode.name).put("cookie", next.cookie).put("uid", next.uid)
            .put("username", next.username).put("avatar", next.avatar).put("local", JSONObject(next.localJson)).put("secrets", secretValues)
        backup?.let { root.put("rollback", JSONObject(it)) }
        val plain = root.toString().toByteArray(Charsets.UTF_8)
        require(plain.size <= 80 * 1024 * 1024 - 29) { "账户资料超过存储限制" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, accountKey(true))
        val bytes = byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) } catch (error: Exception) { file.failWrite(stream); throw error }
        rollback = backup
        secrets = secretValues
        val previous = mutable.value
        mutable.value = next.copy(revision = previous.revision + 1, sessionRevision = nextSessionRevision(previous, next))
    }

    suspend fun acceptCookie(candidate: String, validate: suspend (String) -> JSONObject) {
        require(OfficialLoginSession.hasAccountCookie(candidate)) { "Cookie 缺少有效账号凭据" }
        val generation = state.value.revision
        val result = validate(candidate)
        val user = result.optJSONObject("data") ?: result
        val nested = user.optJSONObject("userInfo") ?: user.optJSONObject("user_info")
        fun field(vararg names: String): String = names.firstNotNullOfOrNull { name ->
            user.optString(name).takeIf(String::isNotBlank) ?: nested?.optString(name)?.takeIf(String::isNotBlank)
        }.orEmpty()
        val uid = field("uid", "userId", "id")
        require(Regex("^[0-9]{1,30}$").matches(uid) && uid != "0" && uid != "10000") { "账号校验未返回有效 UID" }
        withContext(Dispatchers.IO) { mutex.withLock {
            check(generation == state.value.revision) { "账号已变更，已取消此次登录" }
            persist(state.value.copy(mode = AccountMode.COOKIE, cookie = candidate, uid = uid,
                username = field("username", "userName"), avatar = field("userAvatar", "avatar")))
        } }
    }

    suspend fun activateAnonymous() = change { it.copy(mode = AccountMode.ANONYMOUS) }
    suspend fun activateRestoredAnonymous(expected: AccountState) = change {
        check(it.revision==expected.revision && it.mode==AccountMode.GUEST && it.localJson==expected.localJson) { "资料或账号已改变，请从匿名账户管理重新选择" }
        it.copy(mode=AccountMode.ANONYMOUS)
    }
    suspend fun refreshOfficialProfile(profile: JSONObject, expectedCookie: String, expectedUid: String) = change { current ->
        check(current.authenticated && current.requestCookie == expectedCookie && current.uid == expectedUid) { "账号已变更，已取消资料更新" }
        current.copy(username = profile.optString("username").ifBlank { current.username }, avatar = profile.optString("userAvatar").ifBlank { profile.optString("avatar").ifBlank { current.avatar } })
    }
    suspend fun logout() = change {
        if (it.anonymous) it.copy(mode = AccountMode.GUEST)
        else it.copy(mode = AccountMode.GUEST, cookie = "", uid = "", username = "", avatar = "")
    }
    private suspend fun change(transform: (AccountState) -> AccountState) = withContext(Dispatchers.IO) {
        mutex.withLock { persist(transform(state.value)) }
    }
    fun exportLocal(): JSONObject = JSONObject(state.value.localJson)
    fun localContains(field: String, id: String): Boolean = membership.contains(state.value, field, id)
    val canRollback get() = rollback != null

    suspend fun readSecret(key: String): String? = withContext(Dispatchers.IO) {
        mutex.withLock { check(initialized); secrets.opt(key) as? String }
    }
    suspend fun writeSecret(key: String, value: String?) = withContext(Dispatchers.IO) {
        require(Regex("^[A-Za-z0-9_.-]{1,128}$").matches(key) && (value == null || value.length <= 32768))
        mutex.withLock {
            val next = JSONObject(secrets.toString())
            if (value == null) next.remove(key) else next.put(key, value)
            persist(state.value, secretValues = next)
        }
    }
    suspend fun compareAndSetSecret(key: String, expected: String?, replacement: String?): Boolean = withContext(Dispatchers.IO) {
        require(Regex("^[A-Za-z0-9_.-]{1,128}$").matches(key) && (replacement == null || replacement.length <= 32768))
        mutex.withLock {
            check(initialized)
            if ((secrets.opt(key) as? String) != expected) return@withLock false
            val next = JSONObject(secrets.toString())
            if (replacement == null) next.remove(key) else next.put(key, replacement)
            persist(state.value, secretValues = next)
            true
        }
    }

    suspend fun restoreLocal(raw: JSONObject) {
        restoreLocalFromBackup(raw, state.value)
    }
    suspend fun restoreLocalFromBackup(raw: JSONObject, expected: AccountState, activateAnonymous: Boolean = false): AccountState = withContext(Dispatchers.IO) {
        val candidate = LocalAccounts.validate(raw).toString()
        mutex.withLock {
            requireAccountGeneration(expected, state.value)
            persist(state.value.copy(localJson = candidate, mode = if (activateAnonymous) AccountMode.ANONYMOUS else state.value.mode), state.value.localJson)
            state.value
        }
    }
    suspend fun restoreLocalBackupIfUnchanged(previous: AccountState, applied: AccountState) = withContext(Dispatchers.IO) {
        val candidate = LocalAccounts.validate(JSONObject(previous.localJson)).toString()
        mutex.withLock {
            requireLocalRestoreOwnership(applied, state.value)
            persist(state.value.copy(localJson = candidate, mode = previous.mode), state.value.localJson)
        }
    }
    suspend fun rollbackLocal() {
        val expected = state.value
        withContext(Dispatchers.IO) { mutex.withLock {
            requireAccountGeneration(expected, state.value)
            val previous = rollback ?: error("没有恢复前副本")
            persist(state.value.copy(localJson = LocalAccounts.validate(JSONObject(previous)).toString()), state.value.localJson)
        } }
    }
    suspend fun importFlutterLocal() {
        val expected = state.value
        val local = withContext(Dispatchers.IO) {
            app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.greennote.local.account", null) ?: error("没有找到旧版本的本地账户资料")
        }
        restoreLocalFromBackup(JSONObject(local), expected)
    }

    private suspend fun updateProfiles(activate: Boolean = false, expectedRevision: Long? = null, action: (MutableList<JSONObject>, String) -> String) {
        val expected = state.value
        change { state ->
        check(expectedRevision == null || expectedRevision == state.revision) { "账号已变更，已取消此次操作" }
        requireAccountGeneration(expected, state)
        val root = JSONObject(state.localJson)
        val array = root.getJSONArray("profiles")
        val profiles = (0 until array.length()).map { array.getJSONObject(it) }.toMutableList()
        val activeId = action(profiles, root.getString("activeProfileId"))
        val next = LocalAccounts.validate(LocalAccounts.canonical(profiles, activeId))
        state.copy(localJson = next.toString(), mode = if (activate) AccountMode.ANONYMOUS else state.mode)
        }
    }
    suspend fun createProfile(name: String, avatar: String = "", publicIdentity: JSONObject? = null, expectedRevision: Long? = null) {
        val id = "anon_${UUID.randomUUID()}"
        updateProfiles(activate = true, expectedRevision = expectedRevision) { profiles, _ ->
            profiles.add(LocalAccounts.emptyProfile(id, name.trim().ifBlank { "匿名账户${profiles.size + 1}" }).put("avatar", avatar).apply {
                publicIdentity?.let { put("publicIdentity", it) }
            })
            id
        }
    }
    suspend fun switchProfile(id: String) {
        updateProfiles(activate = true) { profiles, _ -> require(profiles.any { it.getString("id") == id }) { "不存在该匿名账户" }; id }
    }
    suspend fun deleteProfile(id: String) = updateProfiles { profiles, active ->
        require(profiles.any { it.getString("id") == id }) { "不存在该匿名账户" }
        profiles.removeAll { it.getString("id") == id }
        if (profiles.isEmpty()) profiles.add(LocalAccounts.emptyProfile())
        if (active == id) profiles.first().getString("id") else active
    }
    suspend fun updateProfile(id: String, name: String, avatar: String, publicIdentity: JSONObject?, activate: Boolean = false, expectedRevision: Long? = null) = updateProfiles(activate, expectedRevision) { profiles, active ->
        val index = profiles.indexOfFirst { it.getString("id") == id }
        require(index >= 0) { "不存在该匿名账户" }
        profiles[index].put("name", name.trim().ifBlank { profiles[index].getString("name") }).put("avatar", avatar).remove("publicIdentity")
        if (publicIdentity != null) profiles[index].put("publicIdentity", publicIdentity)
        active
    }
    suspend fun toggleLocal(field: String, id: String, item: JSONObject, expectedRevision: Long? = null) = updateProfiles(expectedRevision = expectedRevision) { profiles, active ->
        check(state.value.anonymous) { "匿名账户已退出，已取消此次操作" }
        require(field in listOf("follows", "productFollows", "favorites")) { "匿名列表类型无效" }
        val entries = profiles.first { it.getString("id") == active }.getJSONObject(field)
        if (entries.has(id)) entries.remove(id) else entries.put(id, item)
        active
    }
}

private fun loadAccountKey(create: Boolean): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    val alias = "greennote.compose.account.v1"
    (store.getKey(alias, null) as? SecretKey)?.let { return it }
    if (!create) throw AccountKeyUnavailableException()
    return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
        init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
    }.generateKey()
}

// Local list/profile edits retain navigation and in-flight reads; authentication/profile switches do not.
internal fun nextSessionRevision(previous: AccountState, next: AccountState): Long {
    fun anonymousIdentity(state: AccountState): Pair<String, String>? = if (!state.anonymous) null else JSONObject(state.localJson).let {
        it.optString("activeProfileId") to it.optJSONObject("publicIdentity")?.optString("uid").orEmpty()
    }
    val changed = previous.mode != next.mode || previous.requestCookie != next.requestCookie ||
        previous.authenticated && previous.uid != next.uid || anonymousIdentity(previous) != anonymousIdentity(next)
    return previous.sessionRevision + if (changed) 1 else 0
}

internal fun requireAccountGeneration(expected: AccountState, current: AccountState) {
    check(expected.revision == current.revision && expected.mode == current.mode &&
        JSONObject(expected.localJson).getString("activeProfileId") == JSONObject(current.localJson).getString("activeProfileId")) {
        "账号已变更，已取消此次操作"
    }
}

internal fun requireLocalRestoreOwnership(applied: AccountState, current: AccountState) {
    check(applied.localJson == current.localJson && applied.mode == current.mode && applied.cookie == current.cookie && applied.uid == current.uid) {
        "账户资料已被其他操作修改，已保留新资料并取消自动回退"
    }
}
