package com.green.note.content

import kotlinx.coroutines.CancellationException
import org.json.JSONObject

internal fun systemPresetLogo(name: String): String? {
    val key = name.lowercase().replace(" ", "").replace("-", "")
    val families = listOf(
        "originos" to listOf("originos", "funtouch", "vivo", "iqoo"),
        "hyperos" to listOf("hyperos", "澎湃", "miui", "xiaomi"),
        "coloros" to listOf("coloros", "oppo", "oneplus", "一加"),
        "harmonyos" to listOf("harmonyos", "鸿蒙", "emui", "huawei"),
        "magicos" to listOf("magicos", "magicui", "honor", "荣耀"),
        "oneui" to listOf("oneui", "samsung", "三星"), "realmeui" to listOf("realme", "真我"),
        "flyme" to listOf("flyme", "meizu", "魅族"), "ios" to listOf("ios", "ipados", "apple", "苹果"),
        "redmagic" to listOf("redmagic", "红魔", "nubia", "努比亚"), "rog" to listOf("rog", "asus", "华硕", "zenui"),
        "moto" to listOf("moto", "myui", "lenovo", "联想"), "android" to listOf("aosp", "原生", "pixel", "lineage", "android")
    )
    return families.firstOrNull { (_, aliases) -> aliases.any(key::contains) }?.first?.let(presetSystemLogos::get)
}

private val deviceProductCache = LinkedHashMap<Pair<String, String>, String>()
internal suspend fun resolveContentDeviceProduct(api: ContentApi, name: String): JSONObject? {
    val query = name.trim(); if (query.isEmpty()) return null
    val owner = api.imageCacheScope(); val key = owner to query
    synchronized(deviceProductCache) { deviceProductCache[key]?.let { return JSONObject(it) } }
    return try {
        val rows = extractEntities(api.request("/v6/search", query = mapOf("type" to "product", "searchValue" to query, "page" to "1")))
        if (owner != api.imageCacheScope()) throw CancellationException("Account changed")
        val row = rows.firstOrNull { it.text("id", "productId", "logo", "cover", "pic", "icon").isNotEmpty() } ?: return null
        val result = JSONObject(row.toString()).put("entityType", "product").put("id", row.text("id", "productId"))
        synchronized(deviceProductCache) { if (deviceProductCache.size >= 64) deviceProductCache.remove(deviceProductCache.keys.first()); deviceProductCache[key] = result.toString() }
        result
    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { null }
}

fun clearContentDeviceCache() = synchronized(deviceProductCache) { deviceProductCache.clear() }

private val presetSystemLogos = mapOf(
    "originos" to "http://image.coolapk.com/feed_tag/2026/0911/15/20260911-152643-127887-o_1k27lphhmdpnkrph8sms17071v-uid-658442@1080x1080.png",
    "hyperos" to "http://image.coolapk.com/feed_tag/2023/1026/16/20231026-161822-680482-o_1hd8e5gvi1qbb1l2e1kspk0c1q7g1a-uid-1060130@1080x1080.png",
    "coloros" to "http://image.coolapk.com/feed_tag/2023/1116/17/20231116-173629-873619-o_1hf77f24p171f11q91f3v100p10m81a-uid-453007@1080x1080.png",
    "harmonyos" to "http://image.coolapk.com/feed_tag/2024/0118/16/20240118-164741-943015-o_1hki865j51p1m131n1g9k165i1uon1a-uid-453007@1080x1080.png",
    "magicos" to "http://image.coolapk.com/feed_tag/2024/0111/16/20240111-164539-748439-o_1hk3o5k9v1v4u101u17s91q2j1j5v1a-uid-453007@1080x1080.png",
    "oneui" to "http://image.coolapk.com/feed_tag/2024/0118/16/20240118-163236-407632-o_1hki77jov1sqb13e91u5r173413861a-uid-453007@1080x1080.png",
    "realmeui" to "http://image.coolapk.com/feed_tag/2023/1208/17/20231208-171850-241517-o_1hhaek9a81e3s1e7q1i5r17091q421a-uid-453007@1080x1080.png",
    "flyme" to "http://image.coolapk.com/feed_tag/2023/1130/17/20231130-175231-866418-o_1hgh01fhn1v3i1g5g1bfl1l4b1l4c1a-uid-453007@1080x1080.png",
    "ios" to "http://image.coolapk.com/feed_tag/2024/0611/09/20240611-094132-841961-o_1i05q40j0109919f91a561g2c199k1a-uid-453007@1080x1080.png",
    "android" to "http://image.coolapk.com/feed_tag/2023/0511/10/20230511-100412-887714-o_1h04d3j5e1o161c6h1h9k1l1h1a-uid-453007@1080x1080.png",
    "redmagic" to "http://image.coolapk.com/feed_tag/2023/1124/15/20231124-152843-855734-o_1hfs9f7431e217vd1lre13g318261a-uid-453007@1080x1080.png",
    "rog" to "http://image.coolapk.com/feed_tag/2023/0414/15/20230414-153825-976451-o_1gu1evpfe1329b3c10cf17c1m191a-uid-453007@1080x1080.png",
    "moto" to "http://image.coolapk.com/feed_tag/2023/0602/15/20230602-152014-984443-o_1h1u9c6jh1s931j22b8214191s5j1a-uid-453007@1080x1080.png"
)
