package com.green.note.settings

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

data class AppPreferences(
    val themeMode: Int = 0,
    val dynamicColor: Boolean = false,
    val themeSeedArgb: Long = 0xFF2E7D32,
    val haptics: Boolean = true,
    val floatingNavBar: Boolean = true,
    val liquidGlassNavBar: Boolean = true,
    val pureBlackDark: Boolean = false,
    val useCustomFontWeight: Boolean = false,
    val customFontWeightDelta: Int = 0,
    val fontScale: Float = 1f,
    val autoClearCacheThresholdMb: Int = 200,
    val imageSavePathType: Int = 0,
    val videoSavePathType: Int = 0,
    val translucentNavigationGlass: Boolean = false,
) {
    fun asMap(): Map<String, Any> = linkedMapOf(
        "themeMode" to themeMode, "dynamicColor" to dynamicColor, "themeSeedArgb" to themeSeedArgb,
        "enableHaptics" to haptics, "floatingNavBar" to floatingNavBar, "liquidGlassNavBar" to liquidGlassNavBar, "translucentNavigationGlass" to translucentNavigationGlass,
        "pureBlackDark" to pureBlackDark, "useCustomFontWeight" to useCustomFontWeight,
        "customFontWeightDelta" to customFontWeightDelta, "fontScale" to fontScale,
        "autoClearCacheThresholdMb" to autoClearCacheThresholdMb,
        "imageSavePathType" to imageSavePathType, "videoSavePathType" to videoSavePathType,
    )

    companion object {
        val weightDeltas = listOf(-300, -200, -100, 0, 100, 200, 300)
        val thresholds = listOf(0, 50, 100, 200, 500, 1024, 2048)
        val themeSeeds = listOf(0xFFFA2F3A, 0xFFFF8200, 0xFF1976D2, 0xFF2E7D32, 0xFF7B1FA2, 0xFFE91E63, 0xFF00897B, 0xFF455A64)
        val themeNames = listOf("经典红", "活力橙", "极光蓝", "翡翠绿", "优雅紫", "樱花粉", "青碧色", "经典黑灰")

        fun fromMap(values: Map<String, *>): AppPreferences {
            fun bool(key: String, fallback: Boolean) = values[key] as? Boolean ?: fallback
            fun int(key: String, fallback: Int) = (values[key] as? Number)?.toInt() ?: fallback
            val oldMode = when (values["theme_mode"]) { "LIGHT" -> 1; "DARK" -> 2; else -> 0 }
            return AppPreferences(
                themeMode = int("themeMode", oldMode).takeIf { it in 0..2 } ?: 0,
                dynamicColor = bool("dynamicColor", bool("dynamic_color", false)),
                themeSeedArgb = (values["themeSeedArgb"] as? Number)?.toLong()?.takeIf { it in 0..0xFFFFFFFF } ?: 0xFF2E7D32,
                haptics = bool("enableHaptics", true), floatingNavBar = bool("floatingNavBar", true),
                translucentNavigationGlass = bool("translucentNavigationGlass", false),
                liquidGlassNavBar = bool("liquidGlassNavBar", true), pureBlackDark = bool("pureBlackDark", bool("pure_black", false)),
                useCustomFontWeight = bool("useCustomFontWeight", false),
                customFontWeightDelta = int("customFontWeightDelta", 0).takeIf { it in weightDeltas } ?: 0,
                fontScale = (values["fontScale"] as? Number)?.toFloat()?.takeIf { it.isFinite() && it in 0.8f..1.5f } ?: 1f,
                autoClearCacheThresholdMb = int("autoClearCacheThresholdMb", 200).coerceAtLeast(0),
                imageSavePathType = int("imageSavePathType", 0).takeIf { it in 0..2 } ?: 0,
                videoSavePathType = int("videoSavePathType", 0).takeIf { it in 0..2 } ?: 0,
            )
        }
    }
}

class SettingsStore(context: Context) {
    private val app = context.applicationContext
    private val preferences = context.applicationContext.getSharedPreferences("greennote_compose_settings", Context.MODE_PRIVATE)
    private val mutex = Mutex()
    private var revision=0L
    private val mutableState = MutableStateFlow(AppPreferences())
    val state: StateFlow<AppPreferences> = mutableState

    suspend fun initialize() = mutex.withLock {
        mutableState.value = withContext(Dispatchers.IO) {
            if (!preferences.getBoolean("flutter_settings_imported", false)) {
                // Read the old file without ever opening an editor on it.
                val migrated = FlutterPreferences.read(app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).all)
                val editor = preferences.edit()
                migrated.first.asMap().forEach { (key, value) -> if (!preferences.contains(key)) put(editor, key, value) }
                if (!preferences.contains("webDavUrl")) editor.putString("webDavUrl", migrated.second.url)
                if (!preferences.contains("webDavUsername")) editor.putString("webDavUsername", migrated.second.username)
                if (!preferences.contains("webDavDirectory")) editor.putString("webDavDirectory", migrated.second.directory)
                check(editor.putBoolean("flutter_settings_imported", true).commit()) { "原版设置迁入失败，请重试" }
            }
            AppPreferences.fromMap(preferences.all)
        }
    }

    suspend fun update(transform: (AppPreferences) -> AppPreferences) = mutex.withLock {
        val next = transform(mutableState.value)
        require(next == AppPreferences.fromMap(next.asMap())) { "设置格式无效" }
        withContext(Dispatchers.IO) {
            val editor = preferences.edit()
            next.asMap().forEach { (key, value) ->
                when (value) {
                    is Int -> editor.putInt(key, value)
                    is Long -> editor.putLong(key, value)
                    is Float -> editor.putFloat(key, value)
                    is Boolean -> editor.putBoolean(key, value)
                }
            }
            check(editor.commit()) { "设置保存失败，请重试" }
        }
        mutableState.value = next
        revision++
    }

    suspend fun readWebDavConfig(): WebDavConfig = withContext(Dispatchers.IO) {
        val values = preferences.all
        WebDavConfig(values["webDavUrl"] as? String ?: "", values["webDavUsername"] as? String ?: "", values["webDavDirectory"] as? String ?: "GreenNote")
    }

    suspend fun saveWebDavConfig(config: WebDavConfig) = mutex.withLock {
        withContext(Dispatchers.IO) {
            check(preferences.edit().putString("webDavUrl", config.url).putString("webDavUsername", config.username)
                .putString("webDavDirectory", config.directory).commit()) { "无法保存 WebDAV 配置。" }
        }
        revision++
    }

    internal suspend fun backupSnapshot():SettingsBackupSnapshot=mutex.withLock {
        SettingsBackupSnapshot(mutableState.value,readWebDavConfig(),revision)
    }

    /** Preferences and DAV destination commit together; concurrent user changes are never overwritten. */
    internal suspend fun replaceBackup(expected:SettingsBackupSnapshot,next:AppPreferences,config:WebDavConfig):SettingsBackupSnapshot=mutex.withLock {
        check(revision==expected.revision&&mutableState.value==expected.preferences&&readWebDavConfig()==expected.config){"设置已改变，请重新恢复备份"}
        require(next==AppPreferences.fromMap(next.asMap())){"设置格式无效"}
        withContext(kotlinx.coroutines.NonCancellable+Dispatchers.IO) {
            fun write(values:AppPreferences,dav:WebDavConfig):Boolean {
                val editor=preferences.edit();values.asMap().forEach{(key,value)->put(editor,key,value)}
                return editor.putString("webDavUrl",dav.url).putString("webDavUsername",dav.username).putString("webDavDirectory",dav.directory).commit()
            }
            if(!write(next,config)) {
                val error=IllegalStateException("设置保存失败，请重试")
                if(!write(expected.preferences,expected.config))error.addSuppressed(IllegalStateException("设置回退保存失败"))
                throw error
            }
            mutableState.value=next;revision++
            SettingsBackupSnapshot(next,config,revision)
        }
    }
}

internal data class SettingsBackupSnapshot(val preferences:AppPreferences,val config:WebDavConfig,val revision:Long)

internal object FlutterPreferences {
    private const val doublePrefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"
    fun read(old: Map<String, *>): Pair<AppPreferences, WebDavConfig> {
        fun value(key: String) = old["flutter.greennote.$key"]
        val result = AppPreferences().asMap().toMutableMap()
        val keys = mapOf("theme_mode" to "themeMode", "dynamic_color" to "dynamicColor", "enable_haptics" to "enableHaptics",
            "floating_nav" to "floatingNavBar", "liquid_glass_nav" to "liquidGlassNavBar", "pure_black" to "pureBlackDark",
            "custom_font" to "useCustomFontWeight", "font_delta" to "customFontWeightDelta", "auto_clear_cache_threshold_mb" to "autoClearCacheThresholdMb",
            "image_save_path_type" to "imageSavePathType", "video_save_path_type" to "videoSavePathType")
        keys.forEach { (legacy, current) -> value(legacy)?.let { raw ->
            val default = result.getValue(current)
            result[current] = if (default is Boolean) { require(raw is Boolean) { "原版设置格式无效：$legacy" }; raw }
            else { require(raw is Int || raw is Long) { "原版设置格式无效：$legacy" }; val number=(raw as Number).toLong(); require(number in Int.MIN_VALUE..Int.MAX_VALUE); number.toInt() }
        } }
        value("theme_seed_argb")?.let { require(it is String); result["themeSeedArgb"] = it.toLongOrNull(16) ?: error("原版主题色格式无效") }
        value("font_scale")?.let {
            val scale = if (it is Number) it.toFloat() else {
                require(it is String && it.startsWith(doublePrefix)) { "原版字体比例格式无效" }
                it.removePrefix(doublePrefix).toFloatOrNull() ?: error("原版字体比例格式无效")
            }
            result["fontScale"] = scale
        }
        val checked = AppPreferences.fromMap(result)
        require(checked.asMap() == result) { "原版设置包含无效范围，未改动原数据" }
        fun string(key: String, fallback: String): String { val raw=value(key) ?: return fallback; require(raw is String); return raw }
        return checked to WebDavConfig(string("webdav.url", ""), string("webdav.username", ""), string("webdav.directory", "GreenNote"))
    }
}

private fun put(editor: android.content.SharedPreferences.Editor, key: String, value: Any) {
    when (value) { is Int -> editor.putInt(key,value); is Long -> editor.putLong(key,value); is Float -> editor.putFloat(key,value); is Boolean -> editor.putBoolean(key,value) }
}

data class WebDavConfig(val url: String = "", val username: String = "", val directory: String = "GreenNote")

object StoragePaths {
    fun sanitize(value: String?, fallback: String = "User"): String {
        val clean = value.orEmpty().trim().replace(Regex("[\\\\/:*?\"<>|\\r\\n]"), "_").replace(Regex("_+"), "_").trim()
        return if (clean.isEmpty() || clean == "." || clean == "..") fallback else clean.take(50).trim()
    }

    fun summary(type: Int, nickname: String, video: Boolean): String {
        val base = if (video) "Movies" else "Picture"
        val suffix = when (type) { 1 -> nickname.trim().ifEmpty { "我的昵称" } + "/"; 2 -> "该条动态发布用户昵称/"; else -> "" }
        return "$base/GreenNote/$suffix"
    }

    fun subdirectory(type: Int, nickname: String?, author: String?): String = when (type) {
        1 -> "GreenNote/${sanitize(nickname, "MyProfile")}";
        2 -> "GreenNote/${sanitize(author, "Unknown")}";
        else -> "GreenNote"
    }
}
