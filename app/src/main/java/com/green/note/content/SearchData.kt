package com.green.note.content

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.decodeBase64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.DataInputStream

internal data class SearchHotGroup(val title: String, val items: List<JSONObject>)
internal object SearchData {
    private val childKeys = listOf("entities", "entityList", "list", "items", "children", "data")
    fun title(row: JSONObject) = row.text("title", "searchValue", "keyword", "word", "name").trim()
    private fun children(row: JSONObject) = childKeys.firstNotNullOfOrNull { row.optJSONArray(it)?.takeIf { list -> list.length() > 0 } }
    private fun sponsor(row: JSONObject): Boolean {
        val markers = listOf("entityType", "entity_type", "entityTemplate", "entity_template", "template").joinToString(" ") { row.optString(it) }.lowercase()
        val type = row.opt("sponsorType")?.takeUnless { it == JSONObject.NULL } ?: row.opt("sponsor_type")?.takeUnless { it == JSONObject.NULL }
        return "sponsor" in markers || when (type) { is Boolean -> type; is Number -> type.toDouble() != 0.0; null -> false; else -> type.toString().isNotEmpty() }
    }
    fun groups(value: Any?): List<SearchHotGroup> {
        val result = mutableListOf<SearchHotGroup>()
        fun visit(item: Any?, depth: Int) {
            if (depth > 64 || result.size >= 100) return
            when (item) {
                is JSONArray -> for (index in 0 until item.length()) visit(item.opt(index), depth + 1)
                is JSONObject -> if (!sponsor(item)) {
                    val rows = children(item)?.objects().orEmpty().filter { !sponsor(it) && title(it).isNotEmpty() }
                    if (rows.isNotEmpty() && title(item).isNotEmpty()) result += SearchHotGroup(title(item), rows)
                    else childKeys.forEach { visit(item.opt(it), depth + 1) }
                }
            }
        }
        visit(value, 0); return result
    }
    fun keywords(value: Any?): List<String> {
        val result = linkedSetOf<String>()
        fun visit(item: Any?, depth: Int) {
            if (depth > 64 || result.size >= 100) return
            when (item) {
                is String -> item.trim().takeIf { it.isNotEmpty() }?.let(result::add)
                is JSONArray -> for (index in 0 until item.length()) visit(item.opt(index), depth + 1)
                is JSONObject -> if (!sponsor(item)) { val list = children(item); if (list != null) visit(list, depth + 1) else visit(title(item), depth + 1) }
            }
        }
        visit(value, 0); return result.toList()
    }
    fun suggestions(value: Any?): List<String> {
        val result = linkedSetOf<String>()
        fun visit(item: Any?, depth: Int) {
            if (depth > 64 || result.size >= 100) return
            when (item) {
                is String -> item.trim().takeIf(String::isNotEmpty)?.let(result::add)
                is JSONObject -> visit(item.text("keyword", "key", "title", "name", "text", "word"), depth + 1)
                is JSONArray -> for (index in 0 until item.length()) visit(item.opt(index), depth + 1)
            }
        }
        visit(value, 0); return result.toList()
    }
}

internal object SearchHistory {
    private const val prefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
    private val mutex = Mutex()
    private fun preferences(context: Context) = context.getSharedPreferences("greennote_compose_content", Context.MODE_PRIVATE)
    suspend fun read(context: Context): List<String> = withContext(Dispatchers.IO) { mutex.withLock { readLocked(context) } }
    private fun readLocked(context: Context): List<String> {
        val prefs = preferences(context)
        if (!prefs.contains("search_history")) {
            val raw = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).all["flutter.greennote_search_history"]
            val old = decodeLegacy(raw)
            check(prefs.edit().putString("search_history", JSONArray(old).toString()).commit()) { "搜索历史保存失败" }
        }
        return runCatching { SearchData.suggestions(JSONArray(prefs.getString("search_history", "[]"))).take(20) }.getOrDefault(emptyList())
    }
    suspend fun save(context: Context, query: String): List<String> = withContext(Dispatchers.IO) { mutex.withLock {
        val next = (listOf(query.trim()) + readLocked(context)).filter(String::isNotEmpty).distinct().take(20)
        check(preferences(context).edit().putString("search_history", JSONArray(next).toString()).commit()) { "搜索历史保存失败" }
        next
    } }
    suspend fun clear(context: Context) = withContext(Dispatchers.IO) { mutex.withLock {
        check(preferences(context).edit().putString("search_history", "[]").commit()) { "搜索历史清除失败" }
    } }
    fun decodeLegacy(raw: Any?, maxItems: Int = 20): List<String> {
        require(maxItems in 1..256)
        if (raw == null) return emptyList()
        if (raw is Set<*>) return raw.filterIsInstance<String>().take(maxItems)
        require(raw is String && raw.length <= 256 * 1024)
        if (raw.startsWith("$prefix!")) return SearchData.suggestions(JSONArray(raw.removePrefix("$prefix!"))).take(maxItems)
        require(raw.startsWith(prefix))
        val bytes = requireNotNull(raw.removePrefix(prefix).decodeBase64()).toByteArray()
        // Parse only the original ArrayList<String> wire shape, never deserialize arbitrary Java objects.
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == 0xaced0005.toInt() && input.readUnsignedShort() == 0x7372)
            require(input.readUTF() == "java.util.ArrayList")
            input.readLong()
            require(input.readUnsignedByte() == 3 && input.readUnsignedShort() == 1 && input.readUnsignedByte() == 'I'.code && input.readUTF() == "size")
            require(input.readUnsignedShort() == 0x7870)
            val size = input.readInt(); require(size in 0..maxItems)
            require(input.readUnsignedShort() == 0x7704 && input.readInt() == size)
            val strings = mutableListOf<String>()
            val handles = mutableListOf<String>()
            repeat(size) {
                val item = when (input.readUnsignedByte()) {
                    0x74 -> input.readUTF().also(handles::add)
                    0x71 -> handles[input.readInt() - 0x7e0002]
                    else -> error("搜索历史格式无效")
                }
                require(item.length <= 8192); strings += item
            }
            require(input.readUnsignedByte() == 0x78 && input.available() == 0)
            strings
        }
    }
}
