package com.green.note.media

import org.junit.Assert.*
import org.junit.Test

class VideoResolutionTest {
    @Test fun emptyResolverResultNeverBecomesAPlayableAddress() {
        for (url in listOf("", " ", "\n\t")) {
            val result = VideoResolution.resolved(url)
            assertTrue(result is VideoResolution.Failed)
            assertEquals("Exception: 无法解析视频播放地址", (result as VideoResolution.Failed).message)
        }
    }

    @Test fun successfulResolutionPreservesTheSignedAddressExactly() {
        val address = "https://cdn.example/video.m3u8?token=a%2Fb&part=1"
        assertEquals(address, (VideoResolution.resolved(address) as VideoResolution.Ready).url)
    }

    @Test fun realTransportFailureSurvivesInsteadOfBecomingGenericRetryText() {
        val failure = IllegalStateException("Source error", java.io.IOException("HTTP 403 Forbidden"))
        assertEquals("Source error: HTTP 403 Forbidden", videoFailureMessage(failure))
        assertEquals("连接已断开", videoFailureMessage(IllegalStateException("连接已断开", java.io.IOException("连接已断开"))))
        assertTrue(videoFailureMessage(java.io.IOException()).isNotBlank())
    }
}
