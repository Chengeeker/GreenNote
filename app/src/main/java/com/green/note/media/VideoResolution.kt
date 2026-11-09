package com.green.note.media

/** A missing resolved address is a resolver failure, never a playable media item. */
sealed interface VideoResolution {
    data object Loading : VideoResolution
    data class Ready(val url: String, val qualities: Map<String, String> = emptyMap()) : VideoResolution
    data class Failed(val message: String) : VideoResolution

    companion object {
        fun resolved(url: String, qualities: Map<String, String> = emptyMap()): VideoResolution = if (url.isBlank())
            Failed("Exception: 无法解析视频播放地址") else Ready(url, qualities)
    }
}

internal fun videoFailureMessage(failure: Throwable): String =
    listOfNotNull(failure.message?.takeIf(String::isNotBlank), failure.cause?.message?.takeIf(String::isNotBlank))
        .distinct().joinToString(": ").ifEmpty { failure.toString() }
