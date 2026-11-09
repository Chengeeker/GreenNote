package com.green.note.account

import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.net.URI
import okio.ByteString.Companion.decodeBase64

/** The backup whitelist matches the existing local account format. */
object LocalAccounts {
    private val id = Regex("^[0-9]{1,30}$")
    private val fields = mapOf(
        "follows" to listOf("uid", "username", "userAvatar"),
        "productFollows" to listOf("id", "title", "pic", "logo", "cover", "hot_num", "votenum"),
        "favorites" to listOf("id", "uid", "username", "userAvatar", "message", "pic", "dateline", "entityType"),
    )
    fun emptyProfile(profileId: String = "anon_1", name: String = "匿名酷友") = JSONObject()
        .put("id", profileId).put("name", name).put("avatar", "").put("createdAt", System.currentTimeMillis())
        .put("follows", JSONObject()).put("productFollows", JSONObject()).put("favorites", JSONObject())

    fun empty(): JSONObject = canonical(listOf(emptyProfile()), "anon_1")

    fun canonical(profiles: List<JSONObject>, activeId: String): JSONObject {
        require(profiles.isNotEmpty() && profiles.size <= 50) { "匿名账户列表必须包含 1 至 50 个账户" }
        require(profiles.map { it.getString("id") }.distinct().size == profiles.size) { "匿名账户 ID 重复" }
        val active = profiles.firstOrNull { it.getString("id") == activeId } ?: profiles.first()
        val result = JSONObject().put("version", 2).put("activeProfileId", active.getString("id"))
            .put("profiles", JSONArray(profiles))
        for (key in listOf("name", "avatar", "publicIdentity", "follows", "productFollows", "favorites")) {
            if (active.has(key)) result.put(key, active.get(key))
        }
        return result
    }

    fun validate(raw: JSONObject): JSONObject {
        require(raw.toString().toByteArray(Charsets.UTF_8).size <= 32 * 1024 * 1024) { "匿名账户超过 32 MB" }
        val list = raw.optJSONArray("profiles")
        if (list == null) {
            require(!raw.has("version") || raw.optInt("version") == 1) { "匿名账户资料版本无效" }
            require(raw.toString().toByteArray(Charsets.UTF_8).size <= 16 * 1024 * 1024) { "匿名账户超过 16 MB" }
            val single = validateProfile(raw, "anon_1")
            return canonical(listOf(single), single.getString("id"))
        }
        require(list.length() in 1..50) { "匿名账户列表必须包含 1 至 50 个账户" }
        val profiles = (0 until list.length()).map { validateProfile(list.getJSONObject(it), "anon_${it + 1}") }.toMutableList()
        val activeId = raw.optString("activeProfileId", profiles.first().getString("id"))
        val index = profiles.indexOfFirst { it.getString("id") == activeId }.coerceAtLeast(0)
        val active = JSONObject(profiles[index].toString())
        for (key in listOf("name", "avatar", "publicIdentity", "follows", "productFollows", "favorites")) {
            if (raw.has(key)) active.put(key, raw.get(key))
        }
        profiles[index] = validateProfile(active, active.getString("id"))
        return canonical(profiles, profiles[index].getString("id"))
    }

    fun validateProfile(raw: JSONObject, defaultId: String): JSONObject {
        val name = raw.opt("name")
        val avatar = raw.opt("avatar")
        require(name is String && name.trim().isNotEmpty() && name.length <= 40 && avatar is String && avatar.length <= 400000) { "匿名账户资料无效" }
        if (avatar.isNotEmpty()) {
            val bytes = requireNotNull(avatar.decodeBase64()?.toByteArray()) { "匿名头像不是有效的 Base64" }
            require(bytes.size in 24..300000 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() && bytes[2] == 0x4e.toByte() && bytes[3] == 0x47.toByte()) { "匿名头像必须是压缩后的 PNG 图片" }
            val header = ByteBuffer.wrap(bytes)
            require(header.getInt(16) in 1..512 && header.getInt(20) in 1..512) { "备份头像尺寸无效" }
        }
        val profileId = raw.optString("id", defaultId)
        require(profileId.isNotBlank() && profileId.length <= 128) { "匿名账户 ID 无效" }
        val result = JSONObject().put("id", profileId).put("name", name.trim()).put("avatar", avatar)
            .put("createdAt", raw.optLong("createdAt", System.currentTimeMillis()))
        raw.opt("publicIdentity")?.takeUnless { it == JSONObject.NULL }?.let { value ->
            require(value is JSONObject) { "公开主页身份资料无效" }
            val uid = value.opt("uid")
            val username = value.opt("username")
            val url = value.opt("userAvatar")
            require(uid is String && id.matches(uid) && username is String && username.isNotBlank() && username.length <= 40 && url is String && url.length <= 2048) { "公开主页身份资料无效" }
            if (url.isNotEmpty()) {
                val uri = URI(url)
                require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrEmpty()) { "公开主页头像地址无效" }
            }
            result.put("publicIdentity", JSONObject().put("uid", uid).put("username", username.trim()).put("userAvatar", url))
        }
        fields.forEach { (field, allowed) ->
            val entries = raw.opt(field) ?: if (field == "productFollows") JSONObject() else null
            require(entries is JSONObject && entries.length() <= 10000) { "匿名账户列表无效或超过 10000 条" }
            val checked = JSONObject()
            for (key in entries.keys()) {
                require(id.matches(key)) { "匿名账户条目无效" }
                val item = entries.getJSONObject(key)
                val clean = JSONObject()
                for (nameKey in allowed) {
                    item.opt(nameKey)?.takeUnless { it == JSONObject.NULL }?.let { v ->
                        require(v is String && v.length <= 100000) { "匿名账户条目字段无效" }
                        clean.put(nameKey, v)
                    }
                }
                require(clean.optString(if (field == "follows") "uid" else "id") == key) { "匿名账户条目 ID 不匹配" }
                checked.put(key, clean)
            }
            result.put(field, checked)
        }
        return result
    }
}
