package com.green.note

import androidx.compose.runtime.*
import com.green.note.media.VideoResolver
import com.green.note.media.VideoResolution
import com.green.note.media.VideoScreen
import com.green.note.media.videoFailureMessage
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

@Composable
fun ResolvedVideoScreen(row: JSONObject, graph: AppGraph, onBack: () -> Unit, directory: String) {
    var resolution by remember(row) { mutableStateOf<VideoResolution>(VideoResolution.Loading) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(row, retry) {
        resolution = VideoResolution.Loading
        try {
            var qualities = emptyMap<String, String>()
            val url = VideoResolver.resolve(row.optString("url"), row.optString("requestParams"), graph.contentApi) { qualities = it }
            resolution = VideoResolution.resolved(url, qualities)
        }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { resolution = VideoResolution.Failed(videoFailureMessage(failure)) }
    }
    val url = (resolution as? VideoResolution.Ready)?.url.orEmpty()
    VideoScreen(url, VideoResolver.playbackHeaders(url), onBack, row.optString("title"), row.optString("author"), directory,
        resolution = resolution, onRetryResolution = { resolution = VideoResolution.Loading; retry++ })
}
