package com.green.note.account

import android.content.Context
import okio.ByteString.Companion.decodeBase64
import org.json.JSONObject
import java.security.Key
import java.security.KeyStore
import java.security.spec.MGF1ParameterSpec
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource

/** Read-only compatibility with the baseline's default secure-storage 11.2.0 format. */
internal class FlutterAccountImport(private val context: Context) {
    data class Snapshot(val state: AccountState, val secrets: JSONObject, val backup: String?) {
        override fun toString() = "FlutterAccountImport.Snapshot(mode=${state.mode})"
    }

    fun read(): Snapshot? {
        val old = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val encrypted = context.getSharedPreferences("FlutterSecureStorage", Context.MODE_PRIVATE)
        if (old.all.isEmpty() && encrypted.all.isEmpty()) return null
        val prefix = "flutter."
        val local = old.getString(prefix + "greennote.local.account", null)?.let { raw ->
            require(raw.length <= 32 * 1024 * 1024) { "旧账户资料超过大小限制，原数据已保留" }
            LocalAccounts.validate(JSONObject(raw))
        } ?: LocalAccounts.empty()
        val selected = old.getString(prefix + "greennote.local.active_profile_id", null)
        if (selected != null) {
            val profiles = local.getJSONArray("profiles")
            val all = (0 until profiles.length()).map { profiles.getJSONObject(it) }
            if (all.any { it.getString("id") == selected }) {
                val adjusted = LocalAccounts.canonical(all, selected)
                for (key in adjusted.keys()) local.put(key, adjusted.get(key))
            }
        }
        val cookie = readSecure("coolapk_cookie").orEmpty()
        require(cookie.isEmpty() || OfficialLoginSession.hasAccountCookie(cookie)) { "旧账号凭据格式无效，原数据已保留" }
        val anonymous = old.getBoolean(prefix + "greennote.local.active", false)
        val enabled = old.getBoolean(prefix + "greennote.cookie.enabled", true)
        val mode = when { anonymous -> AccountMode.ANONYMOUS; enabled && cookie.isNotEmpty() -> AccountMode.COOKIE; else -> AccountMode.GUEST }
        val uid = cookie.split(';').firstOrNull { it.trim().startsWith("uid=") }?.trim()?.substringAfter('=').orEmpty()
        val secrets = JSONObject()
        readSecure("greennote.webdav.password")?.let { secrets.put("greennote.webdav.password", it) }
        old.getString(prefix + "guest_device_code", null)?.let { secrets.put("guest_device_code", it) }
        old.getString(prefix + "greennote.official_device_code", null)?.let { secrets.put("official_device_code", it) }
        val backup = old.getString(prefix + "greennote.local.account.before_restore", null)?.let {
            LocalAccounts.validate(JSONObject(it)).toString()
        }
        return Snapshot(AccountState(mode = mode, cookie = cookie, uid = old.getString(prefix + "cached_user_uid", null) ?: uid,
            username = old.getString(prefix + "cached_user_nickname", "").orEmpty(),
            avatar = old.getString(prefix + "cached_user_avatar", "").orEmpty(), localJson = local.toString()), secrets, backup)
    }

    private fun readSecure(name: String): String? {
        val prefs = context.getSharedPreferences("FlutterSecureStorage", Context.MODE_PRIVATE)
        val ciphertext = prefs.getString("${KEY_PREFIX}_$name", null) ?: return null
        require(ciphertext.length <= 1024 * 1024) { "旧安全存储值超过大小限制" }
        val config = context.getSharedPreferences("FlutterSecureStorageConfiguration:FlutterSecureStorage", Context.MODE_PRIVATE)
        val fallback = context.getSharedPreferences("FlutterSecureStorageConfiguration", Context.MODE_PRIVATE)
        fun marker(key: String, default: String) = config.getString(key, null) ?: fallback.getString(key, default) ?: default
        require(marker("FlutterSecureSAlgorithmKey", "RSA_ECB_OAEPwithSHA_256andMGF1Padding") == "RSA_ECB_OAEPwithSHA_256andMGF1Padding" &&
            marker("FlutterSecureSAlgorithmStorage", "AES_GCM_NoPadding") == "AES_GCM_NoPadding") {
            "旧安全存储加密格式不匹配，原数据和密钥均已保留"
        }
        val wrapped = context.getSharedPreferences("FlutterSecureKeyStorage", Context.MODE_PRIVATE).getString(WRAPPED_KEY, null)
            ?: error("旧安全存储密钥缺失，原数据已保留")
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val privateKey = store.getKey("${context.packageName}.FlutterSecureStoragePluginKeyOAEP", null)
            ?: throw AccountKeyUnavailableException()
        val rsa = Cipher.getInstance("RSA/ECB/OAEPPadding", "AndroidKeyStoreBCWorkaround")
        rsa.init(Cipher.UNWRAP_MODE, privateKey, OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT))
        val key = rsa.unwrap(wrapped.decodeBase64()?.toByteArray() ?: error("旧密钥编码无效"), "AES", Cipher.SECRET_KEY)
        return decryptValue(ciphertext, key)
    }

    companion object {
        private const val KEY_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
        private const val WRAPPED_KEY = "AESVGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
        internal fun decryptValue(encoded: String, key: Key): String {
            val combined = encoded.decodeBase64()?.toByteArray() ?: error("旧安全存储编码无效")
            require(combined.size >= 28) { "旧安全存储长度无效" }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, combined.copyOfRange(0, 12)))
            return String(cipher.doFinal(combined.copyOfRange(12, combined.size)), Charsets.UTF_8)
        }
    }
}
