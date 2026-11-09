package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class StackedRoutesTest {
    @Test fun exitUsesFlutterReverseControllerDirection() {
        val elapsed = listOf(0f, .25f, .5f, .75f, 1f)
        val sourceProgress = listOf(1f, .446686f, .145268f, .038683f, 0f)
        elapsed.zip(sourceProgress).forEach { (time, expected) ->
            assertEquals(expected, 1f - routeExitEasing.transform(time), .001f)
        }
    }
    @Test fun pageOwnershipIncludesTheWholeStackSoRepeatedRoutesDoNotCollide() {
        assertTrue(retainsRoute(listOf("settings"), listOf("settings", "cache")))
        assertTrue(retainsRoute(listOf("user", "feed", "user"), listOf("user", "feed", "user")))
        assertFalse(retainsRoute(listOf("user", "feed"), listOf("feed")))
        assertFalse(retainsRoute(listOf("settings", "cache"), listOf("settings")))
        assertFalse(retainsRoute(emptyList(), emptyList()))
    }
}
