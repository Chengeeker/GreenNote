package com.green.note.media

import android.net.Uri
import android.view.LayoutInflater
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import coil.imageLoader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.awaitCancellation
import java.io.File
import java.io.RandomAccessFile

internal fun isLivePhoto(url: String) = url.contains("-livepic", ignoreCase = true)

// The MP4 is appended to the original image; scan in bounded chunks instead of loading it into memory.
internal fun embeddedLiveVideoOffset(file: File): Long? {
    if (!file.isFile || file.length() !in 16..(64L * 1024 * 1024)) return null
    RandomAccessFile(file, "r").use { input ->
        val buffer = ByteArray(65536 + 7)
        var previous = 0
        var position = 0L
        while (true) {
            val count = input.read(buffer, previous, 65536)
            if (count <= 0) break
            val end = previous + count
            for (i in 4 until end - 3) {
                if (buffer[i] == 102.toByte() && buffer[i + 1] == 116.toByte() && buffer[i + 2] == 121.toByte() && buffer[i + 3] == 112.toByte()) {
                    val size = ((buffer[i - 4].toInt() and 255) shl 24) or ((buffer[i - 3].toInt() and 255) shl 16) or ((buffer[i - 2].toInt() and 255) shl 8) or (buffer[i - 1].toInt() and 255)
                    val offset = position - previous + i - 4
                    if (offset > 0 && size in 8..4096 && offset + size <= file.length()) return offset
                }
            }
            previous = minOf(7, end)
            System.arraycopy(buffer, end - previous, buffer, 0, previous)
            position += count
        }
    }
    return null
}

@Composable
internal fun LivePhoto(url: String, cacheScope: String, loaded: Boolean, active: Boolean, playing: Boolean, retry: Int, scale: Float, offsetX: Float, offsetY: Float,
    resolve: suspend (String) -> String, onError: () -> Unit, onStopped: () -> Unit) {
    if (!isLivePhoto(url) || !loaded || !active) return
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    var source by remember(url, cacheScope) { mutableStateOf<String?>(null) }
    var file by remember(url, cacheScope) { mutableStateOf<File?>(null) }
    var forceRemote by remember(url, cacheScope) { mutableStateOf(false) }
    val currentError by rememberUpdatedState(onError)
    val currentStopped by rememberUpdatedState(onStopped)
    LaunchedEffect(url, cacheScope, retry, forceRemote) {
        source = null
        file = null
        var temporary: File? = null
        try {
            val extracted = withContext(Dispatchers.IO) {
                if (forceRemote) null else context.imageLoader.diskCache?.openSnapshot("$cacheScope|$url")?.use { snapshot ->
                    val original = snapshot.data.toFile()
                    val start = embeddedLiveVideoOffset(original) ?: return@use null
                    val target = File.createTempFile("live-photo-", ".mp4", context.cacheDir)
                    temporary = target
                    try {
                        original.inputStream().use { input ->
                            var remaining = start
                            while (remaining > 0) { val skipped = input.skip(remaining); if (skipped <= 0) error("图片数据不完整"); remaining -= skipped }
                            target.outputStream().use { input.copyTo(it) }
                        }
                        target
                    } catch (error: Throwable) { target.delete(); throw error }
                }
            }
            file = extracted
            source = extracted?.let { Uri.fromFile(it).toString() } ?: resolve(url)
            awaitCancellation()
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { currentError() }
        finally { temporary?.delete() }
    }
    val player = remember(source) { source?.let { ExoPlayer.Builder(context).build().apply { repeatMode = Player.REPEAT_MODE_ONE; setMediaItem(MediaItem.fromUri(it)); prepare() } } }
    var frame by remember(player) { mutableStateOf(false) }
    DisposableEffect(player, owner) {
        val listener = object : Player.Listener {
            override fun onRenderedFirstFrame() { frame = true }
            override fun onPlayerError(error: PlaybackException) { frame = false; if (file != null && !forceRemote) { source = null; file = null; forceRemote = true } else currentError() }
        }
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) { player?.pause(); currentStopped() } }
        player?.addListener(listener); owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); player?.removeListener(listener); player?.release() }
    }
    LaunchedEffect(player, playing) { player?.playWhenReady = playing && owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) }
    if (player != null) AndroidView(factory = { ctx ->
        (LayoutInflater.from(ctx).inflate(com.green.note.R.layout.live_photo_player, null, false) as PlayerView).apply {
            useController = false; isClickable = false; isFocusable = false; this.player = player
        }
    }, modifier = Modifier.fillMaxSize().graphicsLayer { alpha = if (playing && frame) 1f else 0f; scaleX = scale; scaleY = scale; translationX = offsetX; translationY = offsetY },
        onRelease = { it.player = null })
}
