package com.green.note

import org.junit.Assert.*
import org.junit.Test

class IncomingLinksTest {
    @Test fun consecutiveIdenticalLinksRemainDistinctAndOldCallbacksCannotConsumeNewerOnes() {
        val inbox = IncomingLinks()
        inbox.offer("coolmarket://search?searchValue=%E6%B5%8B%E8%AF%95")
        val first = inbox.first!!
        inbox.offer(first.url)
        inbox.consume(first)
        val second = inbox.first!!
        assertEquals(first.url, second.url)
        assertNotEquals(first.sequence, second.sequence)
        inbox.consume(first)
        assertEquals(second, inbox.first)
        inbox.consume(second)
        assertNull(inbox.first)
    }

    @Test fun recreationRetainsPendingOrderAndConsumedLaunchIsNotReplayed() {
        val inbox = IncomingLinks(listOf("coolmarket://feed/42", "coolmarket://feed/43"))
        inbox.consume(inbox.first!!)
        val restored = IncomingLinks(inbox.snapshot())
        assertEquals("coolmarket://feed/43", restored.first!!.url)
        restored.consume(restored.first!!)
        assertNull(IncomingLinks(restored.snapshot()).first)
    }

    @Test fun externalInputIsBounded() {
        val inbox = IncomingLinks()
        listOf(null, "", " ", "x".repeat(8193), "coolmarket://search?q=\n").forEach(inbox::offer)
        assertNull(inbox.first)
        repeat(40) { inbox.offer("coolmarket://feed/${it + 1}") }
        assertEquals(32, inbox.snapshot().size)
    }
}
