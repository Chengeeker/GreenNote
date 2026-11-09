package com.green.note.nativebridge

import android.content.Context
import android.os.Build
import android.provider.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Original local device labels, read once off the UI thread; no identifier or clipboard access. */
object DeviceProfile {
    @Volatile private var commandUnavailable = false
    private val properties = java.util.concurrent.ConcurrentHashMap<String, String>()
    private fun property(key: String): String = properties.computeIfAbsent(key) {
        val reflected = runCatching { (Class.forName("android.os.SystemProperties").getMethod("get", String::class.java).invoke(null, key) as? String).orEmpty().trim() }.getOrDefault("")
        if (reflected.isNotEmpty()) reflected else if (commandUnavailable) "" else try {
            val process = ProcessBuilder("/system/bin/getprop", key).redirectErrorStream(true).start()
            try {
                val deadline = android.os.SystemClock.elapsedRealtime() + 2000
                var complete = false
                while (!complete && android.os.SystemClock.elapsedRealtime() < deadline) {
                    complete = try { process.exitValue(); true } catch (_: IllegalThreadStateException) { false }
                    if (!complete) Thread.sleep(5)
                }
                if (!complete) { commandUnavailable = true; "" } else process.inputStream.bufferedReader().use { reader -> reader.readLine().orEmpty().take(1024).trim() }
            } finally { process.destroy() }
        } catch (_: Exception) { commandUnavailable = true; "" }
    }
    suspend fun read(context: Context): Map<String, String> = withContext(Dispatchers.IO) {
        val market = listOf("ro.vivo.market.name", "ro.product.marketname", "ro.oppo.market.name", "ro.oplus.market.name", "ro.realme.market.name", "ro.config.marketing_name", "ro.product.vendor.marketname", "ro.product.odm.marketname", "ro.vivo.internet.name")
            .firstNotNullOfOrNull { property(it).takeIf(String::isNotBlank) }
            ?: runCatching { Settings.Secure.getString(context.contentResolver, "bluetooth_name")?.trim()?.takeIf(String::isNotBlank) }.getOrNull()
            ?: runCatching { Settings.Global.getString(context.contentResolver, "device_name")?.trim()?.takeIf { it.isNotBlank() && !it.equals(Build.MODEL, true) } }.getOrNull()
            ?: listOf(Build.MANUFACTURER.orEmpty(), Build.MODEL.orEmpty()).filter(String::isNotBlank).distinct().joinToString(" ")
        mapOf("我的机型" to market, "我的系统" to osName())
    }
    private fun osName(): String {
        vivoOsName(property("ro.vivo.os.build.display.id"), property("ro.vivo.os.name"), property("ro.vivo.os.version"))?.let { return it }
        listOf("ro.mi.os.version.name" to "HyperOS", "ro.miui.ui.version.name" to "MIUI").forEach { (key, name) -> property(key).takeIf(String::isNotBlank)?.let { return "$name $it" } }
        listOf("ro.build.version.coloros", "ro.build.version.opporom", "ro.build.version.oplusrom").firstNotNullOfOrNull { property(it).takeIf(String::isNotBlank) }?.let { return "ColorOS $it" }
        listOf("hw_sc.build.platform.version" to "HarmonyOS", "ro.build.version.emui" to "EMUI", "ro.build.version.magic" to "MagicOS").forEach { (key, name) -> property(key).takeIf(String::isNotBlank)?.let { return "$name $it" } }
        property("ro.flyme.version.id").takeIf(String::isNotBlank)?.let { return it }
        if (Build.DISPLAY.orEmpty().startsWith("Flyme", true)) return Build.DISPLAY.orEmpty()
        runCatching { Build.VERSION::class.java.getDeclaredField("SEM_PLATFORM_INT").getInt(null) }.getOrNull()?.let { value ->
            val major = (value - 90000) / 10000; val minor = (value - 90000) % 10000 / 100
            if (major > 0) return "One UI $major.$minor"
        }
        return Build.VERSION.RELEASE.orEmpty().let { if (it.isNotBlank()) "Android $it" else Build.DISPLAY.orEmpty() }
    }
}
