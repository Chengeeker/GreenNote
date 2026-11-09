package com.green.note.media

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class VideoResolverTest {
    @Test fun nestedSourcesAndProtocolRelativeUrlsAreSupported() {
        val source = JSONObject().put("data", JSONObject().put("urls", JSONObject().put("high", JSONObject().put("src", "//media.example/video.mp4"))))
        assertEquals("https://media.example/video.mp4", VideoResolver.extractStream(source))
        assertEquals("", VideoResolver.normalize("javascript:alert(1)"))
        assertEquals("", VideoResolver.normalize("https://username:password@example.com/video.mp4"))
    }
    @Test fun preferredResolutionAndObjectIdMatchBaseline() {
        val info = JSONObject().put("urls", JSONObject().put("ld", "https://example.com/ld.mp4").put("1080", "https://example.com/hd.mp4"))
        assertEquals("https://example.com/hd.mp4", VideoResolver.preferredStream(JSONObject().put("Component_Play_Playinfo", info)))
        assertEquals("1034:123", VideoResolver.objectId("https://weibo.com/tv/show/1034%3A123"))
        assertEquals("1034:456", VideoResolver.objectId("https://example.com/?fid=456"))
        assertNull(VideoResolver.objectId("https://example.com/?fid=bad"))
    }
    @Test fun playbackHeadersNeverContainAccountSecretsOrMatchLookalikeDomains() {
        assertFalse(VideoResolver.playbackHeaders("https://coolapk.com.evil.example/a").containsKey("Referer"))
        assertFalse(VideoResolver.playbackHeaders("https://video.coolapk.com/a").containsKey("Cookie"))
        assertEquals("https://www.coolapk.com/", VideoResolver.playbackHeaders("https://video.coolapk.com/a")["Referer"])
    }
    @Test fun onlyDistinctExplicitQualitySourcesAreOffered() {
        val response = org.json.JSONObject("""{"data":{"Component_Play_Playinfo":{"urls":{
          "1080P":"https://media.example/high.mp4","720P":"https://media.example/medium.mp4",
          "480P":"https://media.example/medium.mp4","360P":"https://user:secret@media.example/low.mp4",
          "备用":"https://media.example/backup.mp4"}}}}""")
        assertEquals(linkedMapOf("1080P" to "https://media.example/high.mp4", "720P" to "https://media.example/medium.mp4"),
            VideoResolver.resolvedQualityUrls(response))
        assertEquals(emptyMap<String, String>(), VideoResolver.resolvedQualityUrls(
            org.json.JSONObject("""{"urls":{"1080P":"https://media.example/one.mp4","720P":"https://media.example/one.mp4"}}""")))
    }
}
