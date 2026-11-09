package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class ReviewRefreshCycleTest {
    @Test fun initialAndProgrammaticLoadsNeverOwnTheHeader() {
        var cycle = ReviewRefreshCycle.Idle
        // First load, cache revalidation and later source replacement use the same busy flag.
        repeat(3) {
            cycle = cycle.release(armed = false, busy = true)
            assertFalse(cycle.holdsHeader)
            assertFalse(cycle.processing)
            cycle = cycle.complete()
            assertEquals(ReviewRefreshCycle.Idle, cycle)
        }
        assertEquals(ReviewRefreshCycle.Idle, cycle.release(armed = true, busy = true))
    }

    @Test fun releasedPullOwnsReadyRunningAndOneResult() {
        var cycle = ReviewRefreshCycle.Idle.release(armed = true, busy = false)
        assertEquals(ReviewRefreshCycle.Ready, cycle)
        assertTrue(cycle.processing)
        cycle = cycle.start(busy = false)
        assertTrue(cycle.holdsHeader)
        cycle = cycle.complete()
        assertEquals(ReviewRefreshCycle.Result, cycle)
        assertTrue(cycle.holdsHeader)
        assertFalse(cycle.processing)
        assertEquals(ReviewRefreshCycle.Idle, cycle.dismiss())
    }

    @Test fun immediateCompletionAndIgnoredCallbackCanStillRetract() {
        // A synchronous result need not expose a busy=true composition between these events.
        val cycle = ReviewRefreshCycle.Idle.release(true, false).start(false).complete().dismiss()
        assertFalse(cycle.holdsHeader)
        val end = ReviewPullPhysics.sample(70f, 0f, 0f, 2.0)
        assertTrue(end.settled(0f))
    }

    @Test fun readyInterruptionOrAnotherLoadBeforeTriggerNeverStartsRequest() {
        val ready = ReviewRefreshCycle.Idle.release(true, false)
        assertEquals(ReviewRefreshCycle.Idle, ready.interruptReady().start(false))
        assertEquals(ReviewRefreshCycle.Idle, ready.start(busy = true))
        assertEquals(ReviewRefreshCycle.Idle, ReviewRefreshCycle.Idle.release(false, false))
    }

    @Test fun reentryCannotReplaceRunningOrResultAndCancellationReleasesOwnership() {
        val running = ReviewRefreshCycle.Idle.release(true, false).start(false)
        assertEquals(running, running.release(true, false))
        assertEquals(running, running.interruptReady())
        val result = running.complete()
        assertEquals(result, result.release(true, false))
        assertEquals(result, result.complete())
        assertEquals(ReviewRefreshCycle.Idle, running.dismiss())
        assertEquals(ReviewRefreshCycle.Idle, result.dismiss())
        assertEquals(ReviewRefreshCycle.Ready, result.dismiss().release(true, false))
    }
}
