package com.green.note

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var avatarResult: MethodChannel.Result? = null
    private var mediaChannel: MethodChannel? = null
    private val mediaExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var uiChannel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.green.note/avatar")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick") { result.notImplemented(); return@setMethodCallHandler }
                if (avatarResult != null) { result.error("busy", "Picker is open", null); return@setMethodCallHandler }
                avatarResult = result
                try {
                    startActivityForResult(android.content.Intent(android.content.Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(android.content.Intent.CATEGORY_OPENABLE)
                    }, 7401)
                } catch (_: Exception) {
                    avatarResult = null
                    result.error("picker", "Cannot open image picker", null)
                }
            }
        configureMediaChannel(flutterEngine)
        uiChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.green.note/ui")
        uiChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getFontWeightAdjustment" -> result.success(getSystemFontWeightAdjustment())
                "getDeviceProfile" -> result.success(
                    mapOf(
                        "marketName" to getMarketDeviceName(),
                        "osName" to getCustomOsName(),
                        "manufacturer" to Build.MANUFACTURER.orEmpty(),
                        "model" to Build.MODEL.orEmpty(),
                        "device" to Build.DEVICE.orEmpty(),
                        "display" to Build.DISPLAY.orEmpty(),
                        "androidVersion" to Build.VERSION.RELEASE.orEmpty(),
                        "sdkInt" to Build.VERSION.SDK_INT,
                    )
                )
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Activity result bridge for Flutter avatar picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7401) return
        val result = avatarResult ?: return
        avatarResult = null
        val uri = data?.data
        if (resultCode != android.app.Activity.RESULT_OK || uri == null) { result.success(null); return }
        mediaExecutor.execute {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    var count = input.read(buffer)
                    while (count != -1) {
                        if (output.size() + count > 16 * 1024 * 1024) throw IllegalArgumentException("Image is too large")
                        output.write(buffer, 0, count)
                        count = input.read(buffer)
                    }
                    output.toByteArray()
                } ?: throw IllegalArgumentException("Image unavailable")
                val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IllegalArgumentException("Invalid image")
                val options = android.graphics.BitmapFactory.Options().apply { inSampleSize = 1 }
                while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > 512) options.inSampleSize *= 2
                val source = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                    ?: throw IllegalArgumentException("Invalid image")
                val edge = minOf(source.width, source.height)
                val cropped = android.graphics.Bitmap.createBitmap(source, (source.width - edge) / 2, (source.height - edge) / 2, edge, edge)
                val scaled = android.graphics.Bitmap.createScaledBitmap(cropped, 192, 192, true)
                val output = java.io.ByteArrayOutputStream()
                scaled.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
                val png = output.toByteArray()
                if (scaled !== cropped) scaled.recycle()
                if (cropped !== source) cropped.recycle()
                source.recycle()
                runOnUiThread { result.success(png) }
            } catch (_: Exception) {
                runOnUiThread { result.error("image", "Cannot decode selected image", null) }
            }
        }
    }

    private fun getSystemProperty(key: String): String {
        try {
            val c = Class.forName("android.os.SystemProperties")
            val get = c.getMethod("get", String::class.java)
            val value = get.invoke(null, key) as? String
            if (!value.isNullOrBlank()) return value.trim()
        } catch (_: Throwable) {}
        try {
            val process = ProcessBuilder("getprop", key).redirectErrorStream(true).start()
            val prop = process.inputStream.bufferedReader().use { it.readLine() }
            process.destroy()
            if (!prop.isNullOrBlank()) return prop.trim()
        } catch (_: Throwable) {}
        return ""
    }

    private fun getMarketDeviceName(): String {
        val keys = arrayOf(
            "ro.vivo.market.name",
            "ro.product.marketname",
            "ro.oppo.market.name",
            "ro.oplus.market.name",
            "ro.realme.market.name",
            "ro.config.marketing_name",
            "ro.product.vendor.marketname",
            "ro.product.odm.marketname",
            "ro.vivo.internet.name",
        )
        for (k in keys) {
            val v = getSystemProperty(k)
            if (v.isNotBlank()) return v
        }
        try {
            val secureBt = Settings.Secure.getString(contentResolver, "bluetooth_name")
            if (!secureBt.isNullOrBlank()) return secureBt.trim()
        } catch (_: Throwable) {}
        try {
            val globalName = Settings.Global.getString(contentResolver, "device_name")
            if (!globalName.isNullOrBlank() && !globalName.equals(Build.MODEL, ignoreCase = true)) {
                return globalName.trim()
            }
        } catch (_: Throwable) {}
        return listOf(Build.MANUFACTURER.orEmpty(), Build.MODEL.orEmpty())
            .filter { it.isNotBlank() }
            .distinct()
            .joinToString(" ")
    }

    private fun getCustomOsName(): String {
        // Vivo / iQOO (OriginOS / Funtouch OS)
        val vivoDisplay = getSystemProperty("ro.vivo.os.build.display.id")
        if (vivoDisplay.isNotBlank()) return vivoDisplay
        val vivoVer = getSystemProperty("ro.vivo.os.version")
        val vivoName = getSystemProperty("ro.vivo.os.name")
        if (vivoVer.isNotBlank()) {
            val prefix = if (vivoName.contains("funtouch", ignoreCase = true)) "Funtouch OS" else "OriginOS"
            return "$prefix $vivoVer"
        }

        // Xiaomi / Redmi (HyperOS / MIUI)
        val hyperOs = getSystemProperty("ro.mi.os.version.name")
        if (hyperOs.isNotBlank()) return "HyperOS $hyperOs"
        val miui = getSystemProperty("ro.miui.ui.version.name")
        if (miui.isNotBlank()) return "MIUI $miui"

        // OPPO / OnePlus / Realme (ColorOS)
        val colorOs = getSystemProperty("ro.build.version.coloros")
            .ifBlank { getSystemProperty("ro.build.version.opporom") }
            .ifBlank { getSystemProperty("ro.build.version.oplusrom") }
        if (colorOs.isNotBlank()) return "ColorOS $colorOs"

        // Huawei (HarmonyOS / EMUI)
        val harmony = getSystemProperty("hw_sc.build.platform.version")
        if (harmony.isNotBlank()) return "HarmonyOS $harmony"
        val emui = getSystemProperty("ro.build.version.emui")
        if (emui.isNotBlank()) return "EMUI $emui"

        // Honor (MagicOS)
        val magic = getSystemProperty("ro.build.version.magic")
        if (magic.isNotBlank()) return "MagicOS $magic"

        // Meizu (Flyme)
        val flyme = getSystemProperty("ro.flyme.version.id")
        if (flyme.isNotBlank()) return flyme
        if (Build.DISPLAY.orEmpty().startsWith("Flyme", ignoreCase = true)) {
            return Build.DISPLAY.orEmpty()
        }

        // Samsung (One UI)
        try {
            val semField = Build.VERSION::class.java.getDeclaredField("SEM_PLATFORM_INT")
            val semVal = semField.getInt(null)
            val major = (semVal - 90000) / 10000
            val minor = ((semVal - 90000) % 10000) / 100
            if (major > 0) return "One UI $major.$minor"
        } catch (_: Throwable) {}

        val display = Build.DISPLAY.orEmpty()
        val android = Build.VERSION.RELEASE.orEmpty()
        return if (android.isNotBlank()) "Android $android" else display
    }
    private fun setWindowHdr(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                window.colorMode = if (enabled) ActivityInfo.COLOR_MODE_HDR else ActivityInfo.COLOR_MODE_DEFAULT
                if (Build.VERSION.SDK_INT >= 35) {
                    window.setDesiredHdrHeadroom(0.0f)
                }
            } catch (_: Throwable) {}
        }
    }
    private fun setImageGalleryStatusBarVisible(visible: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (visible) show(android.view.WindowInsets.Type.statusBars())
                else hide(android.view.WindowInsets.Type.statusBars())
            }
        } else {
            val decor = window.decorView
            decor.systemUiVisibility = if (visible) decor.systemUiVisibility and android.view.View.SYSTEM_UI_FLAG_FULLSCREEN.inv()
                else decor.systemUiVisibility or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
        }
    }
    private fun configureMediaChannel(flutterEngine: FlutterEngine) {
        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.green.note/media")
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.green.note/hdrImage",
            HdrImageViewFactory(mediaChannel!!),
        )
        mediaChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setWindowHdr" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setWindowHdr(enabled)
                    result.success(null)
                }
                "isHdrDisplaySupported" -> {
                    val isSupported = if (Build.VERSION.SDK_INT >= 34) {
                        try {
                            display?.isHdr ?: false
                        } catch (_: Throwable) {
                            false
                        }
                    } else false
                    result.success(isSupported)
                }
                "setImageGalleryStatusBarVisible" -> {
                    setImageGalleryStatusBarVisible(call.argument<Boolean>("visible") ?: true)
                    result.success(null)
                }
                "saveMediaToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("fileName") ?: ""
                    val mime = call.argument<String>("mimeType") ?: ""
                    if (bytes == null || bytes.isEmpty() || !Regex("gn_[0-9]+\\.(jpg|png|gif|webp|avif)").matches(name) || !mime.startsWith("image/")) {
                        result.error("INVALID_ARGS", "Invalid image", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT < 29 && checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 1002)
                        result.error("PERMISSION_DENIED", "请允许相册权限后重新保存", null)
                        return@setMethodCallHandler
                    }
                    mediaExecutor.execute {
                        try {
                            val saved = if (Build.VERSION.SDK_INT >= 29) {
                                val values = android.content.ContentValues().apply {
                                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name)
                                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
                                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Greennote")
                                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                                val collection = android.provider.MediaStore.Images.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                val uri = contentResolver.insert(collection, values) ?: error("Cannot create image")
                                try {
                                    val output = contentResolver.openOutputStream(uri) ?: error("Cannot open image")
                                    output.use { it.write(bytes) }
                                    values.clear()
                                    values.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                                    contentResolver.update(uri, values, null, null)
                                } catch (e: Exception) {
                                    contentResolver.delete(uri, null, null)
                                    throw e
                                }
                                "Pictures/Greennote/$name"
                            } else {
                                val directory = java.io.File(android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES), "Greennote")
                                if (!directory.isDirectory && !directory.mkdirs()) error("Cannot create directory")
                                val image = java.io.File(directory, name)
                                try { image.outputStream().use { it.write(bytes) } }
                                catch (e: Exception) { image.delete(); throw e }
                                android.media.MediaScannerConnection.scanFile(this, arrayOf(image.absolutePath), arrayOf(mime), null)
                                image.absolutePath
                            }
                            runOnUiThread { result.success(saved) }
                        } catch (_: Exception) {
                            runOnUiThread { result.error("SAVE_FAILED", "无法保存图片", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun getSystemFontWeightAdjustment(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val adj = resources.configuration.fontWeightAdjustment
            if (adj != Configuration.FONT_WEIGHT_ADJUSTMENT_UNDEFINED) return adj
        }
        try {
            if (Settings.Secure.getInt(contentResolver, "accessibility_display_bold_text_enabled", 0) == 1) return 300
        } catch (_: Exception) {}
        return 0
    }
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        uiChannel?.invokeMethod("onFontWeightAdjustmentChanged", getSystemFontWeightAdjustment())
    }
    override fun onDestroy() {
        avatarResult?.error("cancelled", "Activity closed", null)
        avatarResult = null
        mediaExecutor.shutdown()
        super.onDestroy()
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaChannel?.setMethodCallHandler(null)
        mediaChannel = null
        uiChannel?.setMethodCallHandler(null)
        uiChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
