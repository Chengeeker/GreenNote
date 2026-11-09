package com.green.note.network

import org.junit.Assert.assertEquals
import org.junit.Test

class ImageUrlsTest {
    @Test fun oldImageAddressesShareTheHttpsCacheIdentity() {
        val expected = "https://avatar.coolapk.com/data/example.jpg?size=64"
        listOf("http://avatar.coolapk.com", "https://avatar.coolapk.com", "//avatar.coolapk.com", "avatar.coolapk.com")
            .forEach { origin -> assertEquals(expected, normalizeNetworkImageUrl(" $origin/data/example.jpg?size=64 ")) }
        assertEquals("https://image.coolapk.com/feed/cover.jpg", normalizeNetworkImageUrl("/feed/cover.jpg"))
        assertEquals("https://api.coolapk.com/v6/message/image?mid=42", normalizeNetworkImageUrl("/v6/message/image?mid=42"))
    }

    @Test fun invalidNetworkImagesCannotFallThroughToAnotherCoilFetcher() {
        listOf("", "file:///data/secret.jpg", "content://documents/picture", "https://user:pass@image.coolapk.com/a.jpg", "https://")
            .forEach { assertEquals("", normalizeNetworkImageUrl(it)) }
    }
}
