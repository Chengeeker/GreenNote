package com.green.note.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GlassCaptureGateTest {
    @Test fun outstandingCaptureCoalescesUpdatesAndReleasesTheLastScene() {
        val gate = GlassCaptureGate()
        assertTrue(gate.begin())
        repeat(10) { assertFalse(gate.begin()) }
        assertTrue(gate.finish())
        assertTrue(gate.begin())
        assertFalse(gate.finish())
        assertFalse(gate.finish())
    }
}
