package com.green.note.network

import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.encodeUtf8

object OfficialDeviceIdentity {
    private val idPattern = Regex("[A-Za-z0-9_+/.=-]{8,4096}")
    private fun validId(value: String) = value.lowercase() !in setOf("null", "undefined") && value.matches(idPattern)
    private fun controls(value: String) = value.any { it.code < 32 || it.code == 127 }

    fun parse(text: String): String {
        require(text.length <= 32768) { "复制内容过长，请重新从官方酷安复制" }
        val matches = Regex("^[ \\t]*ShuzlmID[ \\t]*[:：][ \\t]*([^\\r\\n]*)$", setOf(RegexOption.MULTILINE, RegexOption.IGNORE_CASE))
            .findAll(text.replace("\uFEFF", "")).toList()
        require(matches.size == 1) { "未找到唯一的 ShuzlmID，请在官方同一页面累计点击“复制 OAID”5次，再复制完整内容" }
        return matches.single().groupValues[1].trim().also { require(validId(it)) { "数盟 ID 为空或格式不正确，请在官方酷安重新复制" } }
    }

    fun fields(code: String): List<String>? {
        if (code.isEmpty() || code.length > 16384) return null
        val values = code.reversed().decodeBase64()?.utf8()?.split(';') ?: return null
        return values.takeIf { it.size == 9 && validId(it.first()) && it.drop(1).all { v -> v.length <= 256 && !controls(v) } }
    }

    fun encode(id: String, previous: String, profile: Map<String, String>): String {
        require(validId(id)) { "数盟 ID 格式不正确" }
        fun property(name: String): String {
            val value = profile[name].orEmpty()
            require(value.isNotBlank() && value.length <= 256 && ';' !in value && !controls(value)) { "无法读取设备机型参数，未修改设备标识" }
            return " ${value.trim()}"
        }
        val values = (fields(previous) ?: listOf(id, " ", " ", " ", property("manufacturer"), property("brand"), property("model"), property("display"), " null")).toMutableList()
        values[0] = id
        return values.joinToString(";").encodeUtf8().base64().reversed().replace("=", "")
    }
}
