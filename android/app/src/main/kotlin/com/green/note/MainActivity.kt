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
    private var pickingMessageImage = false
    private var mediaChannel: MethodChannel? = null
    private val mediaExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var uiChannel: MethodChannel? = null
    private var appManagerChannel: MethodChannel? = null
    private var cacheChannel: MethodChannel? = null
    private var linksChannel: MethodChannel? = null
    private var initialLink: String? = null
    private var appDownloads: AppDownloads? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val data = intent?.dataString
        if (!data.isNullOrEmpty()) {
            initialLink = data
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val data = intent.dataString
        if (!data.isNullOrEmpty()) {
            linksChannel?.invokeMethod("onLink", data)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val loginCookies = CoolapkLoginCookies()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.green.note/login_cookies")
            .setMethodCallHandler { call, result -> loginCookies.handle(call, result) }
        appDownloads = AppDownloads(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.green.note/downloads")
            .setMethodCallHandler { call, result -> appDownloads?.handle(call.method, call.arguments as? Map<*, *>, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.green.note/avatar")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick" && call.method != "pickImage") { result.notImplemented(); return@setMethodCallHandler }
                if (avatarResult != null) { result.error("busy", "Picker is open", null); return@setMethodCallHandler }
                avatarResult = result
                pickingMessageImage = call.method == "pickImage"
                try {
                    val action = if (pickingMessageImage && Build.VERSION.SDK_INT >= 33)
                        android.provider.MediaStore.ACTION_PICK_IMAGES else android.content.Intent.ACTION_GET_CONTENT
                    startActivityForResult(android.content.Intent(action).apply {
                        type = "image/*"
                        if (action == android.content.Intent.ACTION_GET_CONTENT) addCategory(android.content.Intent.CATEGORY_OPENABLE)
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
                        "brand" to Build.BRAND.orEmpty(),
                        "model" to Build.MODEL.orEmpty(),
                        "device" to Build.DEVICE.orEmpty(),
                        "display" to Build.DISPLAY.orEmpty(),
                        "androidVersion" to Build.VERSION.RELEASE.orEmpty(),
                        "sdkInt" to Build.VERSION.SDK_INT,
                    )
                )
                "openOfficialIdSettings" -> {
                    try {
                        packageManager.getApplicationInfo("com.coolapk.market", 0)
                        startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,
                            android.net.Uri.parse("coolmarket://www.coolapk.com/native/testSettings"))
                            .setPackage("com.coolapk.market"))
                        result.success(true)
                    } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                        result.error("official_not_installed", "Official Coolapk is not installed", null)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        appManagerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.green.note/app_manager",
        )
        appManagerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> mediaExecutor.execute {
                    try {
                        val apps = getInstalledApps()
                        runOnUiThread { result.success(apps) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("APP_LIST_FAILED", error.message, null)
                        }
                    }
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    val intent = packageName?.let {
                        packageManager.getLaunchIntentForPackage(it)
                    }
                    if (intent == null) {
                        result.success(false)
                    } else {
                        try {
                            startActivity(intent)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("APP_LAUNCH_FAILED", error.message, null)
                        }
                    }
                }
                "showAppInfo" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.error("INVALID_PACKAGE", "Missing package name", null)
                    } else {
                        try {
                            startActivity(android.content.Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"),
                            ))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("APP_INFO_FAILED", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        cacheChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.green.note/cache",
        )
        cacheChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheStats" -> mediaExecutor.execute {
                    try {
                        val stats = getCacheStatistics()
                        runOnUiThread { result.success(stats) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("CACHE_STATS_FAILED", error.message, null)
                        }
                    }
                }
                "clearCache" -> mediaExecutor.execute {
                    try {
                        val cleared = clearAppCache()
                        runOnUiThread {
                            result.success(mapOf("cleared" to cleared, "success" to true))
                        }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("CACHE_CLEAR_FAILED", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        linksChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.green.note/links",
        )
        linksChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    val link = initialLink
                    initialLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val applications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(
                android.content.pm.PackageManager.ApplicationInfoFlags.of(
                    android.content.pm.PackageManager.GET_META_DATA.toLong(),
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(android.content.pm.PackageManager.GET_META_DATA)
        }
        return applications.mapNotNull { app ->
            try {
                val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getPackageInfo(
                        app.packageName,
                        android.content.pm.PackageManager.PackageInfoFlags.of(0),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(app.packageName, 0)
                }
                val bitmap = android.graphics.Bitmap.createBitmap(
                    96,
                    96,
                    android.graphics.Bitmap.Config.ARGB_8888,
                )
                val iconBytes = try {
                    val icon = pm.getApplicationIcon(app)
                    icon.setBounds(0, 0, 96, 96)
                    icon.draw(android.graphics.Canvas(bitmap))
                    java.io.ByteArrayOutputStream().use { output ->
                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
                        output.toByteArray()
                    }
                } catch (_: Exception) {
                    byteArrayOf()
                } finally {
                    bitmap.recycle()
                }
                val apkFiles = (listOfNotNull(app.sourceDir) + app.splitSourceDirs.orEmpty())
                    .distinct()
                    .map { java.io.File(it) }
                mapOf(
                    "packageName" to app.packageName,
                    "label" to pm.getApplicationLabel(app).toString(),
                    "version" to (packageInfo.versionName ?: ""),
                    "versionCode" to (if (Build.VERSION.SDK_INT >= 28) packageInfo.longVersionCode else @Suppress("DEPRECATION") packageInfo.versionCode.toLong()),
                    "sizeBytes" to apkFiles.sumOf { if (it.isFile) it.length() else 0L },
                    "updatedAt" to packageInfo.lastUpdateTime,
                    "isSystem" to (
                        (app.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0 ||
                            (app.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                    ),
                    "canLaunch" to (pm.getLaunchIntentForPackage(app.packageName) != null),
                    "icon" to iconBytes,
                )
            } catch (_: Exception) {
                null
            }
        }
    }

    @Deprecated("Activity result bridge for Flutter avatar picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7401) return
        val result = avatarResult ?: return
        avatarResult = null
        val isMessageImage = pickingMessageImage
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
                val maxEdge = if (isMessageImage) 2048 else 512
                while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > maxEdge) options.inSampleSize *= 2
                val source = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                    ?: throw IllegalArgumentException("Invalid image")
                if (isMessageImage) {
                    val output = java.io.ByteArrayOutputStream()
                    val matrix = android.graphics.Matrix()
                    val orientation = try {
                        android.media.ExifInterface(java.io.ByteArrayInputStream(bytes))
                            .getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)
                    } catch (_: Exception) { 1 }
                    when (orientation) {
                        2 -> matrix.setScale(-1f, 1f)
                        3 -> matrix.setRotate(180f)
                        4 -> matrix.setScale(1f, -1f)
                        5 -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                        6 -> matrix.setRotate(90f)
                        7 -> { matrix.setRotate(270f); matrix.postScale(-1f, 1f) }
                        8 -> matrix.setRotate(270f)
                    }
                    val oriented = if (matrix.isIdentity) source else android.graphics.Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
                    oriented.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
                    if (oriented !== source) oriented.recycle()
                    source.recycle()
                    val png = output.toByteArray()
                    if (png.size > 16 * 1024 * 1024) throw IllegalArgumentException("Image is too large")
                    runOnUiThread { result.success(png) }
                    return@execute
                }
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
                    val relativeSubDir = call.argument<String>("relativeSubDir") ?: "GreenNote"
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    val validMediaName = Regex("gn_[0-9]+.*\\.(jpg|png|gif|webp|avif|mp4|mov|mkv|webm)", RegexOption.IGNORE_CASE).matches(name)
                    val validMime = mime.startsWith("image/") || mime.startsWith("video/")
                    if (bytes == null || bytes.isEmpty() || !validMediaName || !validMime) {
                        result.error("INVALID_ARGS", "Invalid media parameters", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT < 29 && checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 1002)
                        result.error("PERMISSION_DENIED", "请允许相册权限后重新保存", null)
                        return@setMethodCallHandler
                    }
                    mediaExecutor.execute {
                        try {
                            val baseDir = if (isVideo) android.os.Environment.DIRECTORY_MOVIES else android.os.Environment.DIRECTORY_PICTURES
                            val sanitizedSub = relativeSubDir.trim('/').replace(Regex("[\\\\:*?\"<>|]"), "_")
                            val targetRelativePath = if (sanitizedSub.isNotEmpty()) "$baseDir/$sanitizedSub" else "$baseDir/GreenNote"

                            val saved = if (Build.VERSION.SDK_INT >= 29) {
                                val values = android.content.ContentValues().apply {
                                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name)
                                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
                                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, targetRelativePath)
                                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                                val collection = if (isVideo) {
                                    android.provider.MediaStore.Video.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                } else {
                                    android.provider.MediaStore.Images.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                }
                                val uri = contentResolver.insert(collection, values) ?: error("Cannot create media store entry")
                                try {
                                    val output = contentResolver.openOutputStream(uri) ?: error("Cannot open media output stream")
                                    output.use { it.write(bytes) }
                                    values.clear()
                                    values.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                                    contentResolver.update(uri, values, null, null)
                                } catch (e: Exception) {
                                    contentResolver.delete(uri, null, null)
                                    throw e
                                }
                                "$targetRelativePath/$name"
                            } else {
                                val basePublicDir = if (isVideo) {
                                    android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_MOVIES)
                                } else {
                                    android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES)
                                }
                                val directory = if (sanitizedSub.isNotEmpty()) java.io.File(basePublicDir, sanitizedSub) else java.io.File(basePublicDir, "GreenNote")
                                if (!directory.isDirectory && !directory.mkdirs()) error("Cannot create directory")
                                val file = java.io.File(directory, name)
                                try { file.outputStream().use { it.write(bytes) } }
                                catch (e: Exception) { file.delete(); throw e }
                                android.media.MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime), null)
                                file.absolutePath
                            }
                            runOnUiThread { result.success(saved) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SAVE_FAILED", "无法保存媒体: ${e.message}", null) }
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
        appDownloads?.close()
        avatarResult?.error("cancelled", "Activity closed", null)
        avatarResult = null
        mediaExecutor.shutdown()
        super.onDestroy()
    }
    private fun getFolderSize(file: java.io.File?): Long {
        if (file == null || !file.exists()) return 0L
        if (file.isFile) return file.length()
        var size = 0L
        val stack = java.util.ArrayDeque<java.io.File>()
        stack.push(file)
        while (stack.isNotEmpty()) {
            val current = stack.pop()
            val files = current.listFiles() ?: continue
            for (f in files) {
                if (f.isDirectory) {
                    stack.push(f)
                } else if (f.isFile) {
                    size += f.length()
                }
            }
        }
        return size
    }

    private fun getCacheStatistics(): Map<String, Long> {
        val cacheRoots = mutableListOf<java.io.File>()
        cacheDir?.let { cacheRoots.add(it) }
        codeCacheDir?.let { cacheRoots.add(it) }
        externalCacheDirs?.filterNotNull()?.let { cacheRoots.addAll(it) }

        var total = 0L
        var images = 0L
        var network = 0L
        var system = 0L

        val stack = java.util.ArrayDeque<java.io.File>()
        for (root in cacheRoots) {
            if (root.exists()) stack.push(root)
        }

        while (stack.isNotEmpty()) {
            val current = stack.pop()
            val files = current.listFiles() ?: continue
            for (file in files) {
                if (file.isDirectory) {
                    stack.push(file)
                } else if (file.isFile) {
                    val len = file.length()
                    total += len
                    val path = file.absolutePath.lowercase()
                    if (path.contains("image") || path.endsWith(".png") || path.endsWith(".jpg") ||
                        path.endsWith(".jpeg") || path.endsWith(".webp") || path.endsWith(".gif")) {
                        images += len
                    } else if (path.contains("http") || path.contains("webview") || path.contains("dio") || path.endsWith(".tmp")) {
                        network += len
                    } else {
                        system += len
                    }
                }
            }
        }

        return mapOf(
            "total" to total,
            "images" to images,
            "network" to network,
            "system" to system,
        )
    }

    private fun clearAppCache(): Long {
        val cacheRoots = mutableListOf<java.io.File>()
        cacheDir?.let { cacheRoots.add(it) }
        codeCacheDir?.let { cacheRoots.add(it) }
        externalCacheDirs?.filterNotNull()?.let { cacheRoots.addAll(it) }

        var clearedBytes = 0L
        for (root in cacheRoots) {
            if (root.exists()) {
                val files = root.listFiles() ?: continue
                for (file in files) {
                    clearedBytes += getFolderSize(file)
                    file.deleteRecursively()
                }
            }
        }
        return clearedBytes
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaChannel?.setMethodCallHandler(null)
        mediaChannel = null
        uiChannel?.setMethodCallHandler(null)
        uiChannel = null
        appManagerChannel?.setMethodCallHandler(null)
        appManagerChannel = null
        cacheChannel?.setMethodCallHandler(null)
        cacheChannel = null
        linksChannel?.setMethodCallHandler(null)
        linksChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
