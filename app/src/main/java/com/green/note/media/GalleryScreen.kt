package com.green.note.media

import com.green.note.ui.ReviewText as Text

import android.Manifest
import android.os.Build
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.platform.LocalDensity
import com.green.note.ui.tapClickable as clickable
import com.green.note.ui.tapCombinedClickable as combinedClickable
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.ScrollableDefaults
import androidx.compose.foundation.gestures.ScrollScope
import androidx.compose.foundation.gestures.TargetedFlingBehavior
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.imageLoader
import coil.request.CachePolicy
import coil.request.ImageRequest
import com.green.note.ui.AppHaptics
import com.green.note.ui.MaterialGlyph
import com.green.note.ui.GlassBackdropHost
import com.green.note.ui.GlassSurface
import com.green.note.ui.LocalAppPreferences
import com.green.note.ui.rememberGlassBackdropInvalidator
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import okhttp3.Headers.Companion.toHeaders
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject
import kotlin.math.abs

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun GalleryScreen(inputUrls: List<String>, initialIndex: Int, onBack: () -> Unit, headersForUrl: (String) -> Map<String, String> = { emptyMap() }, cacheScope: String = "guest",
                  feed: JSONObject? = null, showPostChrome: Boolean = false, onFeedAction: (String) -> Unit = {}, saveDirectory: String = "GreenNote") {
    val post = feed.takeIf { showPostChrome }
    val previewText = remember(post) {
        post?.optString("message")?.let { html ->
            android.text.Html.fromHtml(html, android.text.Html.FROM_HTML_MODE_LEGACY).toString().trim()
        }.orEmpty()
    }
    val urls = remember(inputUrls) { inputUrls.map { com.green.note.network.normalizeNetworkImageUrl(it) } }
    val context = LocalContext.current
    val view = LocalView.current
    val haptics by rememberUpdatedState(LocalAppPreferences.current.haptics)
    val pixelDensity = LocalDensity.current.density
    val tapFeedback by rememberUpdatedState(com.green.note.ui.rememberHapticClick {})
    val scope = rememberCoroutineScope()
    val baseImageLoader = context.imageLoader
    // Original ExtendedImage(cache:true) retains encoded media independently of HTTP freshness.
    // Reuse the application's account-scoped caches and transport, not Flutter storage.
    val galleryImageLoader = remember(baseImageLoader) { baseImageLoader.newBuilder().respectCacheHeaders(false).build() }
    val previewPool = remember(galleryImageLoader) { GalleryRequestPool<GalleryRequestIdentity, android.graphics.drawable.Drawable>(scope) }
    val snackbar = remember { com.green.note.ui.AppToastState() }
    val pager = rememberPagerState(initialPage = initialIndex.coerceIn(0, (urls.size - 1).coerceAtLeast(0)), pageCount = { urls.size.coerceAtLeast(1) })
    val thumbnails = rememberPagerState(initialPage = pager.currentPage, pageCount = { urls.size.coerceAtLeast(1) })
    val reelDecay = ScrollableDefaults.flingBehavior()
    val reelFling = remember(reelDecay) {
        object : TargetedFlingBehavior {
            override suspend fun ScrollScope.performFling(initialVelocity: Float, onRemainingDistanceUpdated: (Float) -> Unit): Float {
                // Flutter's reel disables page snapping. Let inertia end at a fractional
                // page; the existing ownership-aware 120 ms settle handles alignment.
                val remaining = with(reelDecay) { performFling(initialVelocity) }
                onRemainingDistanceUpdated(0f)
                return remaining
            }
        }
    }
    val thumbnailDragged by thumbnails.interactionSource.collectIsDraggedAsState()
    var thumbnailUserScroll by remember { mutableStateOf(false) }
    LaunchedEffect(thumbnailDragged) { if (thumbnailDragged) thumbnailUserScroll = true }
    LaunchedEffect(thumbnails) { snapshotFlow { Triple(thumbnails.currentPage, thumbnails.currentPageOffsetFraction, thumbnails.isScrollInProgress) }.distinctUntilChanged().collect { (page, fraction, scrolling) ->
        if (thumbnailUserScroll) {
            val previousPage = pager.currentPage
            pager.scrollToPage(page, fraction)
            if (thumbnailUserScroll && pager.currentPage != previousPage) {
                AppHaptics.selection(view, haptics, tick = true)
            }
            if (!scrolling && !thumbnailDragged) { thumbnailUserScroll = false; launch { thumbnails.animateScrollToPage(page, animationSpec = tween(120, easing = CubicBezierEasing(.215f, .61f, .355f, 1f))) }; pager.animateScrollToPage(page, animationSpec = tween(120, easing = CubicBezierEasing(.215f, .61f, .355f, 1f))) }
        }
    } }
    LaunchedEffect(pager) { snapshotFlow { pager.currentPage to pager.currentPageOffsetFraction }.distinctUntilChanged().collect { (page, fraction) -> if (!thumbnailUserScroll) thumbnails.scrollToPage(page, fraction) } }
    var chrome by remember { mutableStateOf(true) }
    val knownHdr by HdrImageRegistry.known.collectAsState()
    val activity = remember(context) { generateSequence(context) { (it as? android.content.ContextWrapper)?.baseContext }.filterIsInstance<android.app.Activity>().firstOrNull() }
    LaunchedEffect(chrome) { activity?.window?.let { window -> val controls = WindowCompat.getInsetsController(window, window.decorView); controls.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE; if (chrome) controls.show(WindowInsetsCompat.Type.statusBars()) else controls.hide(WindowInsetsCompat.Type.statusBars()) } }
    DisposableEffect(activity) { onDispose { activity?.window?.let { WindowCompat.getInsetsController(it, it.decorView).show(WindowInsetsCompat.Type.statusBars()) } } }
    var busy by remember { mutableStateOf(false) }
    var saveAll by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    var zoomed by remember { mutableStateOf(false) }
    var viewport by remember { mutableStateOf(Rect.Zero) }
    var closing by remember { mutableStateOf(false) }
    var currentScale by remember { mutableFloatStateOf(1f) }
    var currentOffset by remember { mutableStateOf(Offset.Zero) }
    var exitScale by remember { mutableFloatStateOf(1f) }
    var exitOffset by remember { mutableStateOf(Offset.Zero) }
    var flightSource by remember { mutableStateOf(GalleryHeroRegistry.source(urls.getOrNull(initialIndex).orEmpty(), initial = true)) }
    var flightBitmap by remember { mutableStateOf<Pair<String, Bitmap>?>(null) }
    var exitBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var returnStart by remember { mutableFloatStateOf(1f) }
    val flight = remember { Animatable(0f) }
    var entering by remember { mutableStateOf(true) }
    LaunchedEffect(viewport.isEmpty) {
        if (!viewport.isEmpty && entering && !closing) {
            flight.animateTo(1f, tween(330, easing = LinearEasing))
            entering = false
        }
    }
    fun dismiss() {
        if (closing) return
        closing = true
        returnStart = flight.value
        exitScale = currentScale; exitOffset = currentOffset
        val url = urls.getOrNull(pager.currentPage).orEmpty()
        flightSource = GalleryHeroRegistry.source(url, initial = pager.currentPage == initialIndex)
            ?.takeIf { it.bounds.overlaps(viewport) }
        exitBitmap = flightBitmap?.takeIf { it.first == url }?.second
        scope.launch {
            flight.animateTo(0f, tween((200 * returnStart).toInt().coerceAtLeast(1), easing = LinearEasing))
            onBack()
        }
    }
    BackHandler { dismiss() }
    val liquid = LocalAppPreferences.current.liquidGlassNavBar
    val systemBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val feedChromeExtent = if (post == null) 0.dp else (90 + 16 * LocalDensity.current.fontScale * if (previewText.isEmpty()) 1 else 4).dp
    val thumbnailBottom = systemBottom + if (post == null) 32.dp else feedChromeExtent + 16.dp
    val badgeBottom = if (urls.size > 1) thumbnailBottom + 78.dp else systemBottom + if (post == null) 24.dp else feedChromeExtent + 18.dp
    fun save() { if (!busy && urls.isNotEmpty()) scope.launch {
        busy = true
        try { val selected = if (saveAll) urls else listOf(urls[pager.currentPage]); var completed = 0; for (url in selected) { MediaFiles.save(context, url, false, headersForUrl(url), saveDirectory); completed++ }; snackbar.showSnackbar("已保存 $completed 张原图到相册") }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { snackbar.showSnackbar(failure.message ?: "保存图片失败，请重试") }
        finally { busy = false }
    } }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) save() else scope.launch { snackbar.showSnackbar("未获得保存相册权限") } }
    fun requestSave(all: Boolean = false) { saveAll = all; if (Build.VERSION.SDK_INT < 29) permission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE) else save() }
    LaunchedEffect(pager.currentPage) { zoomed = false }
    val heroFlying = (entering || closing) && flightSource != null
    Box(Modifier.fillMaxSize().onGloballyPositioned { viewport = it.boundsInRoot() }) {
    GlassBackdropHost(Modifier.fillMaxSize().graphicsLayer { alpha = flight.value }, content = { Box(Modifier.fillMaxSize().background(Color.Black)) {
        val invalidateGlass = rememberGlassBackdropInvalidator()
        HorizontalPager(pager, Modifier.fillMaxSize().graphicsLayer { alpha = if (heroFlying) 0f else 1f }, userScrollEnabled = !zoomed && !entering && !closing, beyondViewportPageCount = 1) { page ->
            val url = urls.getOrNull(page)
            if (url == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("图片不可用", color = Color.White) }
            else {
                var scale by remember(url) { mutableFloatStateOf(1f) }
                var offset by remember(url) { mutableStateOf(Offset.Zero) }
                var bounds by remember { mutableStateOf(IntSize.Zero) }
                var failed by remember(url) { mutableStateOf(false) }
                var retry by remember(url) { mutableIntStateOf(0) }
                var upgradeNetworkAllowed by remember(url, retry) { mutableStateOf(false) }
                var loading by remember(url) { mutableStateOf(true) }
                val openingPreview = remember(url, cacheScope) { GalleryHeroRegistry.source(url, initial = page == initialIndex)?.bitmap }
                var zoomJob by remember(url) { mutableStateOf<Job?>(null) }
                var imageSize by remember(url) { mutableStateOf(IntSize.Zero) }
                var decodedBitmap by remember(url) { mutableStateOf<Bitmap?>(null) }
                var hdr by remember(url) { mutableStateOf(false) }
                LaunchedEffect(decodedBitmap, pager.currentPage) { if (page == pager.currentPage && !closing) flightBitmap = decodedBitmap?.let { url to it } }
                fun clampOffset(value: Offset, zoom: Float): Offset {
                    if (imageSize.width <= 0 || imageSize.height <= 0) return value
                    val fit = minOf(bounds.width.toFloat() / imageSize.width, bounds.height.toFloat() / imageSize.height)
                    val maxX = ((imageSize.width * fit * zoom - bounds.width) / 2).coerceAtLeast(0f)
                    val maxY = ((imageSize.height * fit * zoom - bounds.height) / 2).coerceAtLeast(0f)
                    return Offset(value.x.coerceIn(-maxX, maxX), value.y.coerceIn(-maxY, maxY))
                }
                LaunchedEffect(scale, offset, pager.currentPage) { if (page == pager.currentPage) { currentScale = scale; currentOffset = offset; invalidateGlass() } }
                val host = url.toHttpUrlOrNull()
                val safeHeaders = headersForUrl(url).filterKeys { name ->
                    val key = name.lowercase()
                    (host?.scheme == "https" && host.port == 443 && (host.host == "coolapk.com" || host.host.endsWith(".coolapk.com"))) ||
                        key !in listOf("cookie", "authorization") && !key.startsWith("x-app-") && !key.startsWith("x-green")
                }
                val preview by galleryPreview(url, cacheScope, safeHeaders, retry, galleryImageLoader, previewPool,
                    enabled = openingPreview == null || page != pager.currentPage)
                val previewDrawable = remember(preview.drawable) { preview.drawable?.constantState?.newDrawable(context.resources)?.mutate() ?: preview.drawable }
                LaunchedEffect(preview.error) { if (preview.error != null) { failed = true; loading = false } }
                val displayLimit = if (page == pager.currentPage) 4096 else 1280
                val request = remember(url, retry, cacheScope, displayLimit, upgradeNetworkAllowed) { ImageRequest.Builder(context).data(url).size(displayLimit, displayLimit).headers(safeHeaders.toHeaders())
                    .apply { if (!url.contains(".gif", true)) addHeader("Accept", "image/jpeg,image/*;q=0.8,*/*;q=0.5") }
                    .memoryCacheKey("$cacheScope:$url").placeholderMemoryCacheKey("$cacheScope:$url").networkCachePolicy(if (openingPreview != null || upgradeNetworkAllowed) CachePolicy.ENABLED else CachePolicy.DISABLED).diskCacheKey("$cacheScope|$url").crossfade(false).build() }
                Box(Modifier.fillMaxSize().onSizeChanged { bounds = it }
                    .pointerInput(url) {
                        detectTapGestures(onTap = { point ->
                            tapFeedback()
                            if (point.x >= bounds.width / 3f && point.x < bounds.width * 2f / 3f) chrome = !chrome else dismiss()
                        }, onDoubleTap = { point ->
                            tapFeedback()
                            zoomJob?.cancel()
                            val start = scale; val startOffset = offset
                            val long = imageSize.width > 0 && imageSize.height.toFloat() / imageSize.width > 2f
                            val target = if (start <= 1.05f) { if (long) 3.5f else 2.5f } else if (start <= 3.6f) 6f else 1f
                            zoomJob = scope.launch { Animatable(start).animateTo(target, tween(260, easing = CubicBezierEasing(.215f, .61f, .355f, 1f))) {
                                scale = value; val ratio = value / start
                                offset = clampOffset(startOffset * ratio + Offset(bounds.width / 2f - point.x, bounds.height / 2f - point.y) * (ratio - 1), value)
                                zoomed = value > 1.01f
                            } }
                        })
                    }.pointerInput(url) {
                        awaitEachGesture {
                            val first = awaitFirstDown(requireUnconsumed = false)
                            zoomJob?.cancel()
                            val velocityTracker = VelocityTracker().apply { addPosition(first.uptimeMillis, first.position) }
                            var panOnly = true
                            do {
                                val event = awaitPointerEvent()
                                event.changes.firstOrNull { it.id == first.id }?.let { velocityTracker.addPosition(it.uptimeMillis, it.position) }
                                val zoom = event.calculateZoom()
                                val pan = event.calculatePan()
                                if (zoom != 1f || event.changes.count { it.pressed } > 1) panOnly = false
                                // The last UP has no centroid; applying it would turn translation into NaN.
                                if (event.changes.any { it.pressed } && (scale > 1.01f || zoom != 1f || event.changes.count { it.pressed } > 1)) {
                                    if (zoom != 1f || pan.getDistance() > 0) zoomJob?.cancel()
                                    val before = scale
                                    scale = (scale * zoom).coerceIn(1f, 9f)
                                    val pivot = event.calculateCentroid(useCurrent = false)
                                    val ratio = scale / before
                                    offset = clampOffset(offset * ratio + Offset(bounds.width / 2f - pivot.x, bounds.height / 2f - pivot.y) * (ratio - 1) + pan, scale)
                                    zoomed = scale > 1.01f
                                    event.changes.forEach { it.consume() }
                                }
                            } while (event.changes.any { it.pressed })
                            if (scale > 8f) {
                                val start = scale; val startOffset = offset
                                zoomJob = scope.launch {
                                    animateGallerySpring((start - 8f) / 8f) { fraction ->
                                        scale = start + (8f - start) * fraction
                                        offset = clampOffset(startOffset * (scale / start), scale)
                                    }
                                }
                            } else if (panOnly && scale > 1.01f) {
                                val velocity = velocityTracker.calculateVelocity()
                                val delta = galleryInertiaDelta(velocity.x, velocity.y, pixelDensity)
                                if (delta.first != 0f || delta.second != 0f) {
                                    val startOffset = offset; val distance = Offset(delta.first, delta.second)
                                    zoomJob = scope.launch { animateGallerySpring { fraction -> offset = clampOffset(startOffset + distance * fraction, scale) } }
                                }
                            }
                        }
                    }, contentAlignment = Alignment.Center) {
                    if (loading && openingPreview != null && !openingPreview.isRecycled) Image(openingPreview.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                    if (loading && openingPreview == null && previewDrawable != null) AsyncImage(previewDrawable, null, modifier = Modifier.fillMaxSize(), imageLoader = galleryImageLoader, contentScale = ContentScale.Fit)
                    if (openingPreview != null || previewDrawable != null) AsyncImage(request, "图片 ${page + 1}", modifier = Modifier.fillMaxSize().graphicsLayer {
                        scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y
                    }, imageLoader = galleryImageLoader, contentScale = ContentScale.Fit, onLoading = { loading = true; failed = false },
                        onSuccess = { result -> loading = false; failed = false; imageSize = IntSize(result.result.drawable.intrinsicWidth, result.result.drawable.intrinsicHeight); decodedBitmap = (result.result.drawable as? BitmapDrawable)?.bitmap }, onError = { if (!upgradeNetworkAllowed) { upgradeNetworkAllowed = true; loading = true; failed = false } else { loading = false; failed = true } })
                    TiledOriginalImage(url, cacheScope, !loading && !failed, page == pager.currentPage && !hdr && !entering && !closing, bounds, scale, offset, Modifier.fillMaxSize())
                    NativeHdrImage(url, cacheScope, !loading && !failed, page == pager.currentPage && !entering && !closing, Modifier.fillMaxSize().graphicsLayer {
                        scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y
                    }) { hdr = it }
                    val badge = galleryBadge(url, feed, hdr || url in knownHdr)
                    if (badge.isNotEmpty() && chrome) {
                        val badgeModifier = Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = badgeBottom)
                        if (badge == "HDR") HdrBadge(badgeModifier)
                        else Text(badge, badgeModifier.background(Color.Black.copy(alpha = .72f), RoundedCornerShape(6.dp))
                            .border(.6.dp, Color.White.copy(alpha = .25f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
                            color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = .6.sp)
                    }
                    if (loading && openingPreview == null && previewDrawable == null) com.green.note.ui.ReviewCircularProgress(color = Color.White)
                    if (failed) com.green.note.ui.ReviewTextButton(onClick = { retry++ }) { Text("图片加载失败，点击重试", color = Color.White) }
                }
            }
        }
    } }, overlay = { Box(Modifier.fillMaxSize()) {
        androidx.compose.animation.AnimatedVisibility(visible = chrome && !entering && !closing, modifier = Modifier.fillMaxSize(),
            enter = androidx.compose.animation.fadeIn(tween(140, easing = CubicBezierEasing(.215f, .61f, .355f, 1f))),
            exit = androidx.compose.animation.fadeOut(tween(if (liquid && closing) 0 else 140))) { Box(Modifier.fillMaxSize()) {
            Row(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                com.green.note.ui.GalleryTopControl("返回", liquid, onClick = ::dismiss) { MaterialGlyph("arrow_back_rounded", color = Color.White, size = 22.dp, contentDescription = "返回") }
                if (post != null) {
                    Spacer(Modifier.width(10.dp))
                    val avatar = remember(post) { com.green.note.network.normalizeNetworkImageUrl(post.optString("userAvatar")) }
                    val avatarRequest = remember(avatar, cacheScope) { ImageRequest.Builder(context).data(avatar).headers(headersForUrl(avatar).toHeaders()).memoryCacheKey("$cacheScope|$avatar").diskCacheKey("$cacheScope|$avatar").build() }
                    var avatarFallback by remember(avatar, cacheScope) { mutableStateOf(true) }
                    Box(Modifier.size(48.dp).clip(CircleShape).clickable(enabled = post.optString("uid").isNotBlank()) { onFeedAction("author") }, contentAlignment = Alignment.Center) {
                        if (avatarFallback) Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { MaterialGlyph("person_rounded", size = 26.4.dp, color = MaterialTheme.colorScheme.onPrimaryContainer) }
                        if (avatar.isNotBlank()) AsyncImage(avatarRequest, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, onSuccess = { avatarFallback = false }, onError = { avatarFallback = true })
                    }
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f).clickable { onFeedAction("author") }) {
                        Text(post.optString("username"), color = Color.White, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(post.optString("date").ifEmpty { com.green.note.content.relativeTime(post.optString("dateline")) }, color = Color.White.copy(alpha = .7f), fontSize = 12.sp, maxLines = 1)
                    }
                    if (post.optString("uid").isNotBlank()) {
                        val following = post.optInt("isFollow") == 1 || post.optJSONObject("userAction")?.optInt("follow") == 1
                        if (liquid) GlassSurface(Modifier.width((24 + 42 * androidx.compose.ui.platform.LocalDensity.current.fontScale).coerceIn(80f, 120f).dp).height(48.dp).clickable(enabled = !busy) { onFeedAction("follow") }) { Text(if (following) "已关注" else "关注", color = Color.White, fontSize = 14.sp) }
                        else com.green.note.ui.ReviewButton(onClick = { onFeedAction("follow") }, enabled = !busy) { Text(if (following) "已关注" else "关注") }
                        Spacer(Modifier.width(12.dp))
                    }
                } else Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text("${pager.currentPage + 1} / ${urls.size}", Modifier.clip(RoundedCornerShape(16.dp)).background(Color.Black.copy(alpha = .45f)).padding(horizontal = 14.dp, vertical = 6.dp), color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                }
                Box {
                    com.green.note.ui.GalleryTopControl(if (post == null) "保存高清大图到相册" else "更多", liquid, enabled = !busy, onClick = { if (post == null) requestSave() else more = true }) {
                        if (busy) com.green.note.ui.ReviewCircularProgress(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                        else MaterialGlyph(if (post == null) "download_rounded" else "more_vert", color = Color.White, size = 22.dp, contentDescription = if (post == null) "保存高清大图到相册" else "更多")
                    }
                }
            }
                if (urls.size > 1) BoxWithConstraints(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(bottom = thumbnailBottom)) {
                    val width = maxWidth * .16f
                    HorizontalPager(thumbnails, Modifier.fillMaxWidth().height(64.dp), pageSize = PageSize.Fixed(width), contentPadding = PaddingValues(horizontal = (maxWidth - width) / 2), beyondViewportPageCount = 4, flingBehavior = reelFling) { index ->
                        val url = urls[index]
                        val preview by galleryPreview(url, cacheScope, headersForUrl(url), 0, galleryImageLoader, previewPool)
                        val previewDrawable = remember(preview.drawable) { preview.drawable?.constantState?.newDrawable(context.resources)?.mutate() ?: preview.drawable }
                        Box(Modifier.fillMaxSize().padding(horizontal = 3.dp, vertical = 2.dp).clip(RoundedCornerShape(8.dp)).border(2.dp, if (index == pager.currentPage) Color.White else Color.Transparent, RoundedCornerShape(8.dp)).clickable { thumbnailUserScroll = false; scope.launch { thumbnails.scrollToPage(index); pager.scrollToPage(index) } }) {
                            if (previewDrawable != null) AsyncImage(previewDrawable, "第 ${index + 1} 张图片", modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(6.dp)), imageLoader = galleryImageLoader, contentScale = ContentScale.Crop)
                            val badge = galleryBadge(url, feed, url in knownHdr)
                            if (badge.isNotEmpty()) {
                                val badgeModifier = Modifier.align(Alignment.BottomEnd).padding(end = 2.dp, bottom = 2.dp)
                                if (badge == "HDR") HdrBadge(badgeModifier, description = "第 ${index + 1} 张 HDR 图片", compact = true)
                                else Text(badge, badgeModifier.background(Color.Black.copy(alpha = .75f), RoundedCornerShape(3.dp))
                                    .padding(horizontal = 3.dp, vertical = 1.dp), color = Color.White, fontSize = 7.5.sp, fontWeight = FontWeight.Bold)
                            }
                            if (index != pager.currentPage) Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = .5f)))
                        }
                    }
                }
            if (post != null) Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .54f)))).navigationBarsPadding()) {
                if (previewText.isNotEmpty()) Text(
                    previewText,
                    // Keep a tap on the preview from falling through to the image's dismiss gesture.
                    Modifier.fillMaxWidth().pointerInput(Unit) { detectTapGestures(onTap = {}) }
                        .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 12.dp),
                    color = Color.White, fontSize = 16.sp, maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
                    Row(Modifier.fillMaxWidth()) {
                        val liked = post.optJSONObject("userAction")?.optInt("like") == 1
                        val starred = post.optInt("isFavorite") == 1 || post.optJSONObject("userAction")?.optInt("favorite") == 1
                        listOf(Triple("like", if (liked) "thumb_up" else "thumb_up_outlined", post.optString("likenum", "0")), Triple("reply", "chat_bubble_outline_rounded", if (liquid) post.optString("replynum", "0") else "回复"),
                            Triple("favorite", if (starred) "star" else "star_border", post.optString("favnum", "0")), Triple("share", "ios_share_rounded", if (liquid) post.optString("forwardnum", post.optString("sharenum", "0")) else "分享")).forEach { (action, icon, label) ->
                            val active = action == "like" && liked || action == "favorite" && starred
                            val color = if (active) MaterialTheme.colorScheme.primary else Color.White
                            Column(Modifier.weight(1f).padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                val tap = Modifier.size(48.dp).combinedClickable(onClick = { onFeedAction(action) }, onLongClick = if (action == "favorite") ({ onFeedAction("collections") }) else null)
                                if (liquid) GlassSurface(tap) { MaterialGlyph(icon, color = color, size = 24.dp, contentDescription = action) }
                                else Box(tap, contentAlignment = Alignment.Center) { MaterialGlyph(icon, color = color, size = 29.dp, contentDescription = action) }
                                Spacer(Modifier.height(8.dp)); Text(label.ifEmpty { "0" }, color = color, maxLines = 1)
                            }
                        }
                    }
            }
        }
        }
        com.green.note.ui.AppToastSink(snackbar, Modifier.align(Alignment.BottomCenter).navigationBarsPadding())
    } })
    if (heroFlying && !viewport.isEmpty) flightSource?.let { source ->
        val image = if (closing) exitBitmap else flightBitmap?.takeIf { it.first == source.url }?.second
        GalleryHeroFlight(source, viewport, { galleryHeroProgress(flight.value, closing, returnStart) },
            Modifier.fillMaxSize(), image, if (closing) exitScale else 1f, if (closing) exitOffset else Offset.Zero)
    }
    }
    if (more && post != null) com.green.note.ui.ReviewModalBottomSheet(onDismissRequest = { more = false }) {
        listOf(Triple("share", "share_outlined", "分享图片"), Triple("save", "download_outlined", "保存原图"), Triple("saveAll", "download_for_offline_outlined", "保存全部原图"), Triple("wallpaper", "wallpaper_outlined", "设为壁纸")).forEach { (action, icon, title) ->
            com.green.note.ui.ReviewTileLayout(modifier = Modifier.clickable(enabled = !busy && urls.isNotEmpty()) {
                more = false
                if (action == "save" || action == "saveAll") requestSave(action == "saveAll")
                else scope.launch {
                    busy = true
                    try { val url = urls[pager.currentPage]; context.startActivity(if (action == "wallpaper") MediaFiles.wallpaper(context, url, headersForUrl(url)) else MediaFiles.share(context, url, headersForUrl(url))) }
                    catch (cancelled: CancellationException) { throw cancelled }
                    catch (_: Exception) { snackbar.showSnackbar("图片操作失败，请检查网络、权限或系统支持后重试") }
                    finally { busy = false }
                }
            }, horizontalPadding = 14.dp, leading = { MaterialGlyph(icon, color = MaterialTheme.colorScheme.onSurfaceVariant) }) {
                Text(title, fontSize = 13.sp, lineHeight = 1.35.em, fontWeight = com.green.note.ui.adjustedWeight(600), color = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

private suspend fun animateGallerySpring(velocity: Float = .4f, update: (Float) -> Unit) {
    val start = withFrameNanos { it }
    do {
        val fraction = withFrameNanos { gallerySpringFraction((it - start) / 1_000_000_000f, velocity) }
        update(fraction)
    } while (fraction < 1f)
}

internal fun galleryDeclaredHdr(url: String, feed: JSONObject?): Boolean {
    fun flag(value: JSONObject?) = listOf("is_hdr", "isHdr", "hdr").any { value?.opt(it)?.toString() in listOf("1", "true") }
    if (flag(feed) || listOf("is_hdr=1", "hdr=1", "ultrahdr", "ultra_hdr", "gainmap").any { url.contains(it, true) }) return true
    val normalized = com.green.note.network.normalizeNetworkImageUrl(url)
    if (normalized.isEmpty()) return false
    for (key in listOf("picArr", "imageUriList", "image_uri_list")) {
        val values = feed?.optJSONArray(key) ?: continue
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            if (flag(item) && listOf("url", "pic", "image").any {
                com.green.note.network.normalizeNetworkImageUrl(item.optString(it)) == normalized
            }) return true
        }
    }
    return false
}
