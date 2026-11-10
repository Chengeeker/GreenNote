package com.green.note

import android.content.Context
import coil.Coil
import coil.ImageLoader
import coil.disk.DiskCache
import com.green.note.account.AccountRepository
import com.green.note.content.DigitalBrandAssets
import com.green.note.network.ApiClient
import com.green.note.network.ApiSession
import com.green.note.network.OfficialDeviceIdentity
import com.green.note.network.RequestSigner
import com.green.note.network.ContentActions
import com.green.note.network.CaptchaCoordinator
import com.green.note.settings.SettingsStore
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.decodeBase64

class AppGraph private constructor(val context: Context) {
    val accounts = AccountRepository(context)
    val settings = SettingsStore(context)
    val captcha = CaptchaCoordinator()
    private val initialization = Mutex()
    private var initialized = false
    @Volatile private var device = ""
    lateinit var api: ApiClient
        private set
    lateinit var contentApi: ContentActions
        private set

    fun session(): ApiSession = accounts.state.value.let { ApiSession(device, it.requestCookie, it.anonymous, it.sessionRevision) }

    suspend fun initialize() = initialization.withLock {
        if (initialized) return@withLock
        withContext(Dispatchers.IO) {
            accounts.initialize()
            settings.initialize()
            DigitalBrandAssets.get(context).warm()
            val guest = accounts.readSecret("guest_device_code") ?: run {
                val legacy = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .all["flutter.guest_device_code"] as? String
                val value = legacy?.takeIf { it.isNotBlank() && it.length <= 16384 } ?: UUID.randomUUID().toString()
                accounts.writeSecret("guest_device_code", value)
                value
            }
            val official = accounts.readSecret("official_device_code")
            device = official?.takeIf { OfficialDeviceIdentity.fields(it) != null } ?: guest
            val blob = try { context.assets.open("coolapk_auth_blob.b64").bufferedReader().use { it.readText().trim() }.decodeBase64()?.toByteArray() ?: byteArrayOf() }
            catch (_: java.io.FileNotFoundException) { byteArrayOf() }
            api = ApiClient(::session, RequestSigner(blob))
            contentApi = ContentActions(api, accounts, ::session, captcha::solve)
            Coil.setImageLoader(ImageLoader.Builder(context).okHttpClient(api.imageHttpClient())
                .components { if (android.os.Build.VERSION.SDK_INT >= 28) add(coil.decode.ImageDecoderDecoder.Factory()) else add(coil.decode.GifDecoder.Factory()) }
                .diskCache { DiskCache.Builder().directory(File(context.cacheDir, "compose_images")).maxSizeBytes(200L * 1024 * 1024).build() }.build())
            initialized = true
        }
    }

    suspend fun importDevice(text: String) {
        val id = OfficialDeviceIdentity.parse(text)
        val code = OfficialDeviceIdentity.encode(id, device, mapOf(
            "manufacturer" to android.os.Build.MANUFACTURER, "brand" to android.os.Build.BRAND,
            "model" to android.os.Build.MODEL, "display" to android.os.Build.DISPLAY,
        ))
        accounts.writeSecret("official_device_code", code)
        device = code
    }

    suspend fun restoreDevice() {
        val guest = accounts.readSecret("guest_device_code") ?: error("原始设备标识不可用")
        accounts.writeSecret("official_device_code", null)
        device = guest
    }

    companion object {
        @Volatile private var instance: AppGraph? = null
        fun get(context: Context): AppGraph = instance ?: synchronized(this) {
            instance ?: AppGraph(context.applicationContext).also { instance = it }
        }
    }
}
