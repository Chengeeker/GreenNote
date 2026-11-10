package com.green.note.content

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.util.AtomicFile
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import com.green.note.network.await
import com.green.note.network.normalizeNetworkImageUrl
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

private val brandId = Regex("[0-9]{1,8}")
private const val MAX_LOGOS = 512
private const val LOGO_EDGE = 192
private const val MAX_LOGO_BYTES = 32 * 1024
private const val MAX_RESPONSE_BYTES = 2 * 1024 * 1024
private const val RETRY_MS = 60L * 60L * 1000L

internal fun officialBrandLogoUrl(value: String): String? =
    normalizeNetworkImageUrl(value).toHttpUrlOrNull()?.takeIf {
        it.host == "image.coolapk.com" && it.port == 443 && it.encodedPath.startsWith("/product_logo/") &&
            it.fragment == null && value.length <= 512
    }?.toString()

private val uploadDate = Regex("/product_logo/([0-9]{4})/([0-9]{4})/([0-9]{2})/")

private fun isOlderLogo(candidate: String, current: String): Boolean {
    val a = uploadDate.find(candidate)?.value ?: return false
    val b = uploadDate.find(current)?.value ?: return false
    return a < b
}

internal class DigitalBrandAssets(
    private val context: Context,
    private val directory: File = File(context.noBackupFilesDir, "public-brand-logos"),
    private val download: suspend (String) -> ByteArray? = ::downloadBrandLogo,
) {
    private data class SavedLogo(val url: String, val bytes: ByteArray)
    private data class Attempt(val url: String, val started: Long)

    private val catalog by lazy {
        try {
            context.assets.open("digital_brand_catalog.json").bufferedReader().use { JSONObject(it.readText()) }
        } catch (_: IOException) {
            JSONObject()
        }
    }
    private val seeds by lazy {
        buildMap {
            for (category in catalog.keys()) for (row in rows(category)) {
                val id = row.text("id")
                if (id in this) continue
                officialBrandLogoUrl(row.text("logo"))?.let { put(id, it) }
            }
        }
    }
    private val attempts = LruCache<String, Attempt>(MAX_LOGOS)
    private val slots = Semaphore(3)
    private val saved by lazy {
        mutableStateMapOf<String, SavedLogo>().apply {
            directory.list().orEmpty().asSequence().map { it.removeSuffix(".bak") }
                .filter { it.endsWith(".logo") }.map { it.removeSuffix(".logo") }
                .filter(brandId::matches).distinct().take(MAX_LOGOS).forEach { id ->
                    read(id)?.let { logo ->
                        if (seeds[id]?.let { isOlderLogo(logo.url, it) } != true) put(id, logo)
                    }
                }
        }
    }

    fun warm() {
        seeds.size
        saved.size
    }

    fun rows(category: String): List<JSONObject> = catalog.optJSONArray(category).objects()

    fun drawable(id: String): Int =
        if (id in seeds) context.resources.getIdentifier("coolapk_brand_$id", "drawable", context.packageName) else 0

    fun savedBytes(id: String): ByteArray? = saved[id]?.bytes

    fun needsRefresh(id: String, url: String): Boolean {
        val current = saved[id]?.url ?: seeds[id]
        return url != seeds[id] && url != current && (current == null || !isOlderLogo(url, current))
    }

    suspend fun refresh(id: String, rawUrl: String) = withContext(Dispatchers.IO) {
        if (!brandId.matches(id)) return@withContext
        val url = officialBrandLogoUrl(rawUrl) ?: return@withContext
        val attempt = synchronized(attempts) {
            if (!needsRefresh(id, url)) return@withContext
            val now = SystemClock.elapsedRealtime()
            val previous = attempts.get(id)
            if (previous != null && now - previous.started < RETRY_MS &&
                (previous.url == url || isOlderLogo(url, previous.url))) return@withContext
            Attempt(url, now).also { attempts.put(id, it) }
        }
        try {
            slots.withPermit {
                if (attempts.get(id) !== attempt) return@withPermit
                val bytes = download(url)?.let(::compactBrandLogo) ?: return@withPermit
                ensureActive()
                synchronized(attempts) {
                    if (attempts.get(id) !== attempt || id !in saved && saved.size >= MAX_LOGOS) return@synchronized
                    write(id, url, bytes)
                    saved[id] = SavedLogo(url, bytes)
                }
            }
        } catch (cancelled: CancellationException) {
            synchronized(attempts) { if (attempts.get(id) === attempt) attempts.remove(id) }
            throw cancelled
        } catch (_: IOException) {
            // The previous local logo stays visible while the server or storage is unavailable.
        }
    }

    private fun file(id: String) = AtomicFile(File(directory, "$id.logo"))

    private fun read(id: String): SavedLogo? {
        return try {
            DataInputStream(file(id).openRead()).use { input ->
                val url = officialBrandLogoUrl(input.readUTF()) ?: return null
                val length = input.readInt().takeIf { it in 1..MAX_LOGO_BYTES } ?: return null
                val bytes = ByteArray(length).also(input::readFully)
                SavedLogo(url, bytes)
            }
        } catch (_: IOException) {
            null
        }
    }

    private fun write(id: String, url: String, bytes: ByteArray) {
        val target = file(id)
        val output = target.startWrite()
        try {
            DataOutputStream(output).apply { writeUTF(url); writeInt(bytes.size); write(bytes); flush() }
            target.finishWrite(output)
        } catch (error: IOException) {
            target.failWrite(output)
            throw error
        }
    }

    companion object {
        @Volatile private var instance: DigitalBrandAssets? = null
        fun get(context: Context): DigitalBrandAssets = instance ?: synchronized(this) {
            instance ?: DigitalBrandAssets(context.applicationContext).also { instance = it }
        }
    }
}

private val logoClient by lazy {
    OkHttpClient.Builder().followRedirects(false).callTimeout(12, TimeUnit.SECONDS).build()
}

private suspend fun downloadBrandLogo(url: String): ByteArray? {
    val request = Request.Builder().url(url)
        .header("Referer", "https://www.coolapk.com/")
        .header("Accept", "image/png,image/jpeg,image/webp").build()
    return logoClient.newCall(request).await().use { response ->
        val body = response.body ?: return null
        if (!response.isSuccessful || body.contentLength() > MAX_RESPONSE_BYTES) return null
        val source = body.source()
        if (source.request(MAX_RESPONSE_BYTES.toLong() + 1)) null else source.readByteArray()
    }
}

@Suppress("DEPRECATION")
private fun compactBrandLogo(bytes: ByteArray): ByteArray? {
    if (bytes.isEmpty() || bytes.size > MAX_RESPONSE_BYTES) return null
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    if (options.outMimeType !in setOf("image/png", "image/jpeg", "image/webp")) return null
    val edge = maxOf(options.outWidth, options.outHeight)
    if (options.outWidth < 1 || options.outHeight < 1 || edge > 4096) return null
    options.inJustDecodeBounds = false
    options.inSampleSize = Integer.highestOneBit((edge / LOGO_EDGE).coerceAtLeast(1))
    val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
    val scale = (LOGO_EDGE.toFloat() / maxOf(decoded.width, decoded.height)).coerceAtMost(1f)
    val bitmap = if (scale == 1f) decoded else Bitmap.createScaledBitmap(
        decoded, (decoded.width * scale).toInt().coerceAtLeast(1), (decoded.height * scale).toInt().coerceAtLeast(1), true,
    )
    return try {
        val output = ByteArrayOutputStream()
        if (bitmap.compress(Bitmap.CompressFormat.WEBP, 90, output) && output.size() <= MAX_LOGO_BYTES) {
            output.toByteArray()
        } else null
    } finally {
        if (bitmap !== decoded) bitmap.recycle()
        decoded.recycle()
    }
}

@Composable
internal fun DigitalBrandLogo(api: ContentApi, row: JSONObject, url: String, modifier: Modifier,
    fallback: @Composable () -> Unit) {
    val assets = DigitalBrandAssets.get(LocalContext.current)
    val id = row.text("id", "entityId")
    val drawable = remember(assets, id) { assets.drawable(id) }
    val bytes = assets.savedBytes(id)
    val bitmap = remember(bytes) { bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    val officialUrl = remember(id, url) { url.takeIf { brandId.matches(id) }?.let(::officialBrandLogoUrl) }
    if (officialUrl != null && assets.needsRefresh(id, officialUrl)) {
        LaunchedEffect(assets, id, officialUrl) { assets.refresh(id, officialUrl) }
    }
    when {
        bitmap != null -> Image(bitmap, null, modifier, contentScale = ContentScale.Fit)
        drawable != 0 -> Image(painterResource(drawable), null, modifier, contentScale = ContentScale.Fit)
        officialUrl != null -> Box(modifier, contentAlignment = Alignment.Center) { fallback() }
        else -> CardImage(api, url, modifier, ContentScale.Fit, fallback = fallback)
    }
}
