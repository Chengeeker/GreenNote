package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONObject
import kotlin.math.roundToInt

internal fun contentVivoOsName(display: String, name: String, version: String): String? {
    val explicit = Regex("(?i)^(OriginOS|Funtouch(?:\\s*OS)?)\\s*(\\d+(?:\\.\\d+)*)(?:\\s|$)").find(display.trim())
    val number = explicit?.groupValues?.get(2) ?: version.trim().takeIf { Regex("\\d+(?:\\.\\d+)*").matches(it) } ?: return null
    val family = if (explicit != null) if (explicit.groupValues[1].startsWith("Origin", true)) "OriginOS" else "Funtouch OS" else if (name.contains("funtouch", true)) "Funtouch OS" else "OriginOS"
    return "$family ${if ('.' in number) number else "$number.0"}"
}

internal fun readContentDeviceProfile(context: Context): Pair<String, String> {
    val getter = runCatching { Class.forName("android.os.SystemProperties").getMethod("get", String::class.java) }.getOrNull()
    var fallback: Map<String, String>? = null
    fun prop(key: String): String {
        val value = runCatching { getter?.invoke(null, key) as? String }.getOrNull().orEmpty().trim()
        if (value.isNotEmpty()) return value
        if (fallback == null) fallback = runCatching {
            val process = ProcessBuilder("getprop").redirectErrorStream(true).start()
            try { process.inputStream.bufferedReader().useLines { lines -> lines.take(4096).mapNotNull { Regex("^\\[([^]]+)]: \\[(.*)]$").matchEntire(it)?.groupValues?.let { values -> values[1] to values[2] } }.toMap() } } finally { process.destroy() }
        }.getOrDefault(emptyMap())
        return fallback?.get(key).orEmpty()
    }
    val market = listOf("ro.vivo.market.name", "ro.product.marketname", "ro.oppo.market.name", "ro.oplus.market.name", "ro.realme.market.name", "ro.config.marketing_name", "ro.product.vendor.marketname", "ro.product.odm.marketname", "ro.vivo.internet.name")
        .firstNotNullOfOrNull { prop(it).takeIf(String::isNotBlank) }
        ?: runCatching { Settings.Secure.getString(context.contentResolver, "bluetooth_name")?.trim()?.takeIf(String::isNotEmpty) }.getOrNull()
        ?: runCatching { Settings.Global.getString(context.contentResolver, "device_name")?.trim()?.takeIf { it.isNotEmpty() && !it.equals(Build.MODEL, true) } }.getOrNull()
        ?: listOf(Build.MANUFACTURER.orEmpty(), Build.MODEL.orEmpty()).filter(String::isNotBlank).distinct().joinToString(" ")
    val vivo = contentVivoOsName(prop("ro.vivo.os.build.display.id"), prop("ro.vivo.os.name"), prop("ro.vivo.os.version"))
    val os = vivo ?: listOf("ro.mi.os.version.name" to "HyperOS", "ro.miui.ui.version.name" to "MIUI", "ro.build.version.coloros" to "ColorOS", "ro.build.version.opporom" to "ColorOS", "ro.build.version.oplusrom" to "ColorOS", "hw_sc.build.platform.version" to "HarmonyOS", "ro.build.version.emui" to "EMUI", "ro.build.version.magic" to "MagicOS")
        .firstNotNullOfOrNull { (key, label) -> prop(key).takeIf(String::isNotBlank)?.let { "$label $it" } }
        ?: prop("ro.flyme.version.id").takeIf(String::isNotBlank)
        ?: Build.DISPLAY.takeIf { it.startsWith("Flyme", true) }
        ?: runCatching { val value = Build.VERSION::class.java.getDeclaredField("SEM_PLATFORM_INT").getInt(null); val major = (value - 90000) / 10000; if (major > 0) "One UI $major.${((value - 90000) % 10000) / 100}" else null }.getOrNull()
        ?: "Android ${Build.VERSION.RELEASE}"
    return market to os
}

@Composable
internal fun DigitalDeviceOverview(api: ContentApi, onOpen: (JSONObject) -> Unit, onPhones: () -> Unit, onSystems: () -> Unit) {
    val context = LocalContext.current
    var profile by remember { mutableStateOf<Pair<String, String>?>(null) }
    var device by remember { mutableStateOf<JSONObject?>(null) }; var system by remember { mutableStateOf<JSONObject?>(null) }
    LaunchedEffect(api) {
        val names = withContext(Dispatchers.IO) { readContentDeviceProfile(context) }; profile = names
        suspend fun find(query: String, os: Boolean): JSONObject? {
            for (type in if (os) listOf("product", "feedTopic") else listOf("product")) {
                try {
                    val rows = extractEntities(api.request("/v6/search", query = mapOf("type" to type, "searchValue" to query, "page" to "1")))
                    val identity = if (os) systemIdentity(query) else null
                    val match = rows.firstOrNull { item ->
                        if (os) identity != null && systemIdentity(item.text("title", "name"))?.let { it.first == identity.first && (it.second == null || identity.second == null || it.second == identity.second) } == true
                        else item.text("id", "productId", "logo", "pic").isNotEmpty()
                    }
                    if (match != null) return JSONObject(match.toString()).put("entityType", if (type == "product") "product" else "topic")
                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { }
            }; return null
        }
        coroutineScope { val phone = async { find(names.first, false) }; val os = async { find(names.second, true) }; device = phone.await(); system = os.await() }
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        OverviewCard(api, "我的机型", device?.text("title").orEmpty().ifEmpty { profile?.first ?: "读取中…" }, device, true, Modifier.weight(1f)) { if (device != null) onOpen(device!!) else onPhones() }
        OverviewCard(api, "我的系统", profile?.second ?: "读取中…", system, false, Modifier.weight(1f)) { if (system != null) onOpen(system!!) else onSystems() }
    }
}

@Composable
private fun OverviewCard(api: ContentApi, header: String, title: String, row: JSONObject?, phone: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme; val score = row?.text("star_average_score", "score", "star_score")?.toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 }
    val count = row?.text("feedCommentNumTxt", "feed_comment_num", "commentnum", "commentNum", "hot_num_txt").orEmpty().ifEmpty { "—" }
    val image = row?.text("logo", "cover", "pic", "icon").orEmpty().ifEmpty { if (phone) "" else systemPresetLogo(title).orEmpty() }
    var imageFailed by remember(image) { mutableStateOf(false) }
    val dark = colors.surface.luminance() < .5f
    val pureBlack = com.green.note.ui.LocalAppPreferences.current.pureBlackDark
    val cardColor = if (dark) if (pureBlack) Color(0xFF121212) else Color(0xFF1B1C20) else colors.surfaceContainerLowest
    val cardBorder = if (dark && pureBlack) Color.White.copy(alpha = .12f) else colors.outlineVariant.copy(alpha = if (dark) .2f else .25f)
    val cardShape = RoundedCornerShape(20.dp)
    val click = com.green.note.ui.rememberHapticClick(onClick)
    Column(modifier.shadow(1.dp, cardShape, clip = false).background(cardColor, cardShape).border(.8.dp, cardBorder, cardShape).clip(cardShape).clickable(onClick = click).padding(12.dp)) {
        Text(header, style = MaterialTheme.typography.labelMedium, color = colors.onSurfaceVariant); Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).background(colors.surfaceContainerHighest.copy(alpha = .45f)).border(.5.dp, colors.outlineVariant.copy(alpha = .25f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                if (image.isNotEmpty() && !imageFailed) ContentImage(api, image, null, Modifier.size(38.dp).clip(RoundedCornerShape(8.dp)), ContentScale.Fit, onError = { imageFailed = true })
                else MaterialGlyph(if (phone) "smartphone_rounded" else "system_update_alt_rounded", color = colors.primary, size = 24.dp)
            }
            Spacer(Modifier.width(8.dp)); Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontSize = 13.5.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis); Spacer(Modifier.height(3.dp))
                Row(verticalAlignment = Alignment.CenterVertically) { repeat(5) { index -> MaterialGlyph("star_rounded", size = 12.5.dp, color = if (score != null && index < (score / 2).roundToInt()) Color(0xFFFFB300) else colors.outlineVariant.copy(alpha = .4f)) }; Spacer(Modifier.width(4.dp)); Text(score?.let { String.format(java.util.Locale.US, "%.1f", it) } ?: "—", color = Color(0xFFFFB300), fontWeight = FontWeight.Bold, fontSize = 12.5.sp) }
            }
        }
        Spacer(Modifier.height(10.dp)); Box(Modifier.height(1.dp).fillMaxWidth(), contentAlignment = Alignment.Center) { HorizontalDivider(thickness = .5.dp, color = colors.outlineVariant.copy(alpha = .25f)) }; Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("$count${if (phone) "机主点评" else "人点评"}", Modifier.weight(1f), fontSize = 11.5.sp, color = colors.onSurfaceVariant, maxLines = 1); Text("去点评", fontSize = 11.5.sp, color = colors.onSurfaceVariant); MaterialGlyph("chevron_right_rounded", size = 14.dp, color = colors.onSurfaceVariant) }
    }
}
