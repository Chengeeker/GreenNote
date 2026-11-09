package com.green.note.content

import org.junit.Assert.*
import org.junit.Test

class ActivityNavigationTest {
    @Test fun documentAndSubframeStayInWebView() {
        assertEquals(ActivityNavigationKind.WEB, activityNavigation("https://m.coolapk.com/activity/123", true).kind)
        assertEquals(ActivityNavigationKind.WEB, activityNavigation("https://outside.test/frame", false).kind)
        assertEquals(ActivityNavigationKind.EXTERNAL, activityNavigation("https://outside.test/frame", true).kind)
    }
    @Test fun ratingWriterIsExternalButRegularWriterKeepsNativeRoute() {
        assertEquals(ActivityNavigationKind.EXTERNAL, activityNavigation("https://www.coolapk.com/feed/writer?type=rating&tag=x", true).kind)
        assertEquals(ActivityNavigationKind.EXTERNAL, activityNavigation("https://www.coolapk.com/feed/writer?type=%72ating", true).kind)
        val writer = "https://www.coolapk.com/feed/writer?tag=hello"
        assertEquals(ActivityNavigation(ActivityNavigationKind.WRITER, writer), activityNavigation(writer, true))
        assertEquals(ActivityNavigationKind.EXTERNAL, activityNavigation("https://evil.test/feed/writer", true).kind)
    }
    @Test fun nativeRoutesKeepQueriesAndUnrecognizedSchemesAreBlocked() {
        assertEquals(ActivityNavigationKind.NATIVE, activityNavigation("https://www.coolapk.com/product/42", true).kind)
        assertEquals(ActivityNavigation(ActivityNavigationKind.NATIVE, "/feed/create?tag=a%20b"), activityNavigation("coolmarket://feed/create?tag=a%20b", true))
        assertEquals(ActivityNavigationKind.BLOCK, activityNavigation("coolmarket://unknown/1", true).kind)
        assertEquals(ActivityNavigationKind.BLOCK, activityNavigation("javascript:alert(1)", true).kind)
        assertEquals(ActivityNavigationKind.BLOCK, activityNavigation("https://a:b@m.coolapk.com/activity/1", true).kind)
        assertEquals(ActivityNavigationKind.EXTERNAL, activityNavigation("https://coolapk.com.evil.test/product/42", true).kind)
    }
}
