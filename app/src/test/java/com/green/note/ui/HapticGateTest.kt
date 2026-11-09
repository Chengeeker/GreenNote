package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class HapticGateTest {
    @Test fun nestedCallbacksShareOnePulseWithoutSuppressingLaterActions() {
        val gate = HapticGate()
        assertTrue(gate.claim(100))
        assertFalse(gate.claim(100))
        assertTrue(gate.claim(140))
        assertFalse(gate.claim(150, tick = true))
        assertTrue(gate.claim(152, tick = true))
    }
}
