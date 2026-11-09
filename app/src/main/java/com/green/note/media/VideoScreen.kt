package com.green.note.media

import com.green.note.ui.ReviewText as Text

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import com.green.note.ui.MaterialGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

private fun Context.activity(): Activity? = when (this) { is Activity -> this; is ContextWrapper -> baseContext.activity(); else -> null }

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun VideoScreen(url: String, headers: Map<String, String>, onBack: () -> Unit, title: String = "", author: String = "", saveDirectory: String = "GreenNote",
    resolution: VideoResolution? = null, onRetryResolution: (() -> Unit)? = null) {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val activity = context.activity()
    val owner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { com.green.note.ui.AppToastState() }
    val transport = remember(url, headers) {
        // Playback follows CDN redirects; account credentials never belong on this transport.
        val publicHeaders = headers.filterKeys { val key = it.lowercase(); key !in listOf("cookie", "authorization") && !key.startsWith("x-app-") && !key.startsWith("x-green") }
        DefaultHttpDataSource.Factory().setDefaultRequestProperties(publicHeaders).setConnectTimeoutMs(15000).setReadTimeoutMs(20000)
    }
    val player = remember(url, transport) {
        ExoPlayer.Builder(context).setMediaSourceFactory(DefaultMediaSourceFactory(transport)).build().apply {
            // Flutter rejects an empty resolved address before creating a source.
            if (url.isNotBlank()) { setMediaItem(MediaItem.fromUri(url)); prepare(); playWhenReady = true }
        }
    }
    var playing by remember(player) { mutableStateOf(false) }
    var initialized by remember(player) { mutableStateOf(false) }
    var error by remember(player) { mutableStateOf<String?>(if (url.isBlank()) "Exception: 无法解析视频播放地址" else null) }
    val visibleError = when (resolution) {
        VideoResolution.Loading -> null
        is VideoResolution.Failed -> resolution.message
        else -> error
    }
    var position by remember(player) { mutableLongStateOf(0L) }
    var duration by remember(player) { mutableLongStateOf(0L) }
    var controls by remember { mutableStateOf(true) }
    var touchRevision by remember { mutableIntStateOf(0) }
    var speedPicker by remember { mutableStateOf(false) }
    var qualityPicker by remember { mutableStateOf(false) }
    val qualityOptions = (resolution as? VideoResolution.Ready)?.qualities.orEmpty().takeIf { it.values.distinct().size > 1 }.orEmpty()
    var activeUrl by remember(player) { mutableStateOf(url) }
    val currentQuality = qualityOptions.entries.firstOrNull { it.value == activeUrl }?.key ?: "画质"
    var speed by remember { mutableFloatStateOf(1f) }
    var landscape by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var hud by remember { mutableStateOf<String?>(null) }
    var hudRevision by remember { mutableIntStateOf(0) }
    var retriedPublic by remember(url) { mutableStateOf(false) }
    var bounds by remember { mutableStateOf(IntSize.Zero) }
    var brightness by remember { mutableFloatStateOf(.5f) }
    var leftDrag by remember { mutableStateOf(false) }
    var longPress by remember { mutableStateOf(false) }
    var seekPreview by remember { mutableStateOf<Float?>(null) }
    var volume by remember { mutableFloatStateOf(.7f) }
    DisposableEffect(activity) {
        val orientation = activity?.requestedOrientation
        onDispose {
            orientation?.let { activity.requestedOrientation = it }
            activity?.window?.let { WindowCompat.getInsetsController(it, it.decorView).show(WindowInsetsCompat.Type.systemBars()) }
        }
    }
    DisposableEffect(player, owner) {
        player.volume = volume
        // Speed can be selected while URL resolution is still in progress.
        player.setPlaybackSpeed(speed)
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(value: Boolean) { playing = value }
            override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_READY) initialized = true; duration = player.duration.coerceAtLeast(0) }
            override fun onPlayerError(failure: PlaybackException) {
                val currentHeaders = if (activeUrl == url) headers else VideoResolver.playbackHeaders(activeUrl)
                if (!retriedPublic && currentHeaders.keys.any { it.equals("Referer", true) }) {
                    retriedPublic = true
                    transport.setDefaultRequestProperties(currentHeaders.filterKeys { val key = it.lowercase(); key !in listOf("cookie", "authorization", "referer", "origin") && !key.startsWith("x-app-") && !key.startsWith("x-green") })
                    player.setMediaItem(MediaItem.fromUri(activeUrl), player.currentPosition); player.prepare(); player.playWhenReady = owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) && player.playWhenReady
                } else {
                    error = videoFailureMessage(failure)
                    initialized = false
                }
            }
        }
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_PAUSE) player.pause() }
        player.addListener(listener); owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); player.removeListener(listener); player.release() }
    }
    LaunchedEffect(landscape) { activity?.window?.let { window ->
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (landscape) { controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE; controller.hide(WindowInsetsCompat.Type.systemBars()) }
        else controller.show(WindowInsetsCompat.Type.systemBars())
    } }
    LaunchedEffect(playing, player) { while (playing) { position = player.currentPosition; duration = player.duration.coerceAtLeast(0); delay(400) } }
    LaunchedEffect(touchRevision, playing, controls, speedPicker, qualityPicker) { if (playing && controls && !speedPicker && !qualityPicker) { delay(3500); controls = false } }
    LaunchedEffect(hud, hudRevision) { if (hud != null) { delay(900); hud = null } }
    fun togglePlayback() {
        if (!initialized) return
        if (player.isPlaying) { player.pause(); controls = true } else { player.play(); touchRevision++ }
    }
    fun save() {
        if (url.isBlank()) { snackbar.showSnackbar("无法获取视频地址"); return }
        if (!saving) scope.launch {
        saving = true
        try { val path = MediaFiles.save(context, activeUrl, true, if (activeUrl == url) headers else VideoResolver.playbackHeaders(activeUrl), saveDirectory); snackbar.showSnackbar("视频已保存至相册：$path") }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { snackbar.showSnackbar(failure.message ?: "保存视频失败，请重试") }
        finally { saving = false }
    } }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { if (it) save() else scope.launch { snackbar.showSnackbar("未获得保存相册权限") } }
    val tapFeedback by rememberUpdatedState(com.green.note.ui.rememberHapticClick {})
    Box(Modifier.fillMaxSize().background(Color.Black).onSizeChanged { bounds = it }) {
        AndroidView(factory = { PlayerView(it).apply { if (Build.VERSION.SDK_INT >= 29) isForceDarkAllowed = false; useController = false; this.player = player } }, modifier = Modifier.fillMaxSize(), update = { it.player = player })
        Box(Modifier.fillMaxSize().pointerInput(player, initialized) {
            if (!initialized) return@pointerInput
            detectTapGestures(onTap = { tapFeedback(); controls = !controls; touchRevision++ }, onDoubleTap = { point ->
                tapFeedback()
                val seconds = videoDoubleTapSeconds(point.x, bounds.width.toFloat())
                if (seconds == 0) togglePlayback() else {
                    val target = (player.currentPosition + seconds * 1000L).coerceIn(0L, player.duration.coerceAtLeast(0L))
                    player.seekTo(target)
                    position = target; hud = "${if (seconds < 0) "-10" else "+10"}s (${time(target)})"
                    hudRevision++
                }
            }, onPress = {
                val oldSpeed = player.playbackParameters.speed
                val delayed = scope.launch { delay(500); longPress = true; player.setPlaybackSpeed(2f); hud = "2.0X 快进中" }
                try { awaitRelease() } finally { delayed.cancel(); if (longPress) { player.setPlaybackSpeed(oldSpeed); longPress = false; hud = null } }
            })
        }.pointerInput(player, initialized) {
            if (!initialized) return@pointerInput
            detectVerticalDragGestures(onDragStart = { leftDrag = it.x < bounds.width / 2f }) { change, amount ->
                change.consume()
                hudRevision++
                val delta = -amount / density / 200f
                if (leftDrag) { brightness = (brightness + delta).coerceIn(.1f, 1f); hud = "亮度 ${(brightness * 100).toInt()}%" }
                else { volume = (volume + delta).coerceIn(0f, 1f); player.volume = volume; hud = "音量" }
            }
        })
        if (!initialized && visibleError == null) com.green.note.ui.ReviewCircularProgress(Modifier.align(Alignment.Center), color = Color.White.copy(alpha = .7f))
        visibleError?.let { Column(Modifier.align(Alignment.Center).padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            MaterialGlyph("error_outline_rounded", size = 48.dp, color = Color.White.copy(alpha = .7f))
            Spacer(Modifier.height(12.dp))
            Text(it, color = Color.White.copy(alpha = .7f), textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
            com.green.note.ui.ReviewFilledTonalButton(iconPadding = true, onClick = {
                if (onRetryResolution != null) onRetryResolution()
                else if (url.isBlank()) error = "Exception: 无法解析视频播放地址"
                else { error = null; initialized = false; player.prepare(); player.play() }
            }) { MaterialGlyph("refresh_rounded"); com.green.note.ui.ReviewButtonIconGap(); Text("重试加载") }
        } }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = (1f - brightness) * .75f)))
        AnimatedVisibility(visible = controls, enter = fadeIn(tween(220)), exit = fadeOut(tween(220)), modifier = Modifier.fillMaxSize()) { Box(Modifier.fillMaxSize()) {
            ReviewVideoTop(Modifier.align(Alignment.TopCenter), title, author, landscape, close = onBack) {
                ReviewVideoAction("download", "保存视频", enabled = !saving, busy = saving) {
                    if (activeUrl.isNotBlank() && Build.VERSION.SDK_INT < 29) permission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE) else save()
                }
            }
            ReviewVideoBottom(Modifier.align(Alignment.BottomCenter), position, duration, player.bufferedPosition.coerceAtLeast(0),
                playing, speed, landscape, enabled = initialized, quality = currentQuality.takeIf { qualityOptions.isNotEmpty() },
                onPlay = ::togglePlayback, onSpeed = { speedPicker = true; touchRevision++ }, onQuality = { qualityPicker = true; touchRevision++ },
                onFullscreen = {
                    landscape = !landscape
                    activity?.requestedOrientation = if (landscape) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    touchRevision++
                }, onSeek = { player.seekTo(it); position = it; touchRevision++ })
        } }
        hud?.let { value -> Row(Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = .54f), RoundedCornerShape(10.dp)).padding(horizontal = 18.dp, vertical = if (value.startsWith("亮度") || value == "音量") 12.dp else 10.dp), verticalAlignment = Alignment.CenterVertically) {
            val level = value.startsWith("亮度") || value == "音量"
            MaterialGlyph(when { value.startsWith("亮度") -> "brightness_6_rounded"; value == "音量" -> if (volume > 0) "volume_up_rounded" else "volume_off_rounded"; value.startsWith("-") -> "fast_rewind_rounded"; else -> "fast_forward_rounded" }, color = Color.White)
            Spacer(Modifier.width(if (level) 10.dp else 8.dp))
            if (level) com.green.note.ui.ReviewLinearProgress(progress = { if (value.startsWith("亮度")) brightness else volume }, modifier = Modifier.width(80.dp), color = Color(0xff2e7d32), trackColor = Color.White.copy(alpha = .24f))
            else Text(value, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        } }
        com.green.note.ui.AppToastSink(snackbar, Modifier.align(Alignment.BottomCenter).navigationBarsPadding())
    }
    if (speedPicker) ReviewVideoChoices("播放倍速", standardVideoSpeeds.map { "${it}X" }, "${speed}X", { speedPicker = false; touchRevision++ }) {
        speed = it.removeSuffix("X").toFloat(); player.setPlaybackSpeed(speed)
    }
    if (qualityPicker && qualityOptions.isNotEmpty())
        ReviewVideoChoices("清晰度选择", qualityOptions.keys.toList(), currentQuality, { qualityPicker = false; touchRevision++ }) { choice ->
            qualityOptions[choice]?.takeIf { it != activeUrl }?.let { target ->
                val at = player.currentPosition
                val resume = player.playWhenReady
                activeUrl = target; retriedPublic = false; initialized = false; error = null
                transport.setDefaultRequestProperties(VideoResolver.playbackHeaders(target))
                player.setMediaItem(MediaItem.fromUri(target), at)
                player.prepare(); player.setPlaybackSpeed(speed)
                player.playWhenReady = resume && owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            }
        }
}

private fun time(milliseconds: Long): String = if (milliseconds >= 3600000) String.format(Locale.ROOT, "%d:%02d:%02d", milliseconds / 3600000, milliseconds / 60000 % 60, milliseconds / 1000 % 60) else String.format(Locale.ROOT, "%02d:%02d", milliseconds / 60000, milliseconds / 1000 % 60)
