package com.green.note.ui

import androidx.compose.foundation.MutatePriority
import androidx.compose.foundation.gestures.ScrollableState
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

class ScrollRequestsTest {
    @Test fun overlappingListsAndDisposalRestoreOnlyAfterTheLastScroller() {
        val calls = mutableListOf<Boolean>()
        val requests = ScrollRequests(calls::add)
        requests.update("one", true); requests.update("one", true); requests.update("two", true)
        requests.update("one", false); assertEquals(listOf(true), calls)
        requests.update("two", false); assertEquals(listOf(true, false), calls)
        requests.update("one", true); requests.clear(); requests.clear()
        assertEquals(listOf(true, false, true, false), calls)
    }

    @Test fun touchStopsFlingWithoutCancellingAUserDragOrCoveredPage() = runBlocking {
        val requests = ScrollRequests {}
        val flingState = ScrollableState { it }
        val dragState = ScrollableState { it }
        val coveredState = ScrollableState { it }
        requests.track("list", flingState)
        requests.track("drag", dragState)
        requests.track("covered", coveredState)
        val fling = launch(start = CoroutineStart.UNDISPATCHED) { flingState.scroll { awaitCancellation() } }
        val drag = launch(start = CoroutineStart.UNDISPATCHED) { dragState.scroll(MutatePriority.UserInput) { awaitCancellation() } }
        val covered = launch(start = CoroutineStart.UNDISPATCHED) { coveredState.scroll { awaitCancellation() } }
        try {
            requests.untrack("covered")
            requests.stopOnPress(this)
            withTimeout(2000) { fling.join() }
            assertFalse(flingState.isScrollInProgress)
            assertTrue(dragState.isScrollInProgress)
            assertTrue(coveredState.isScrollInProgress)
        } finally {
            fling.cancelAndJoin()
            drag.cancelAndJoin()
            covered.cancelAndJoin()
        }
    }

    @Test fun newDragTakesOverWhileTheCancelledFlingIsStillUnwinding() = runBlocking {
        val requests = ScrollRequests {}
        val state = ScrollableState { it }
        requests.track("list", state)
        val cleanupStarted = CompletableDeferred<Unit>()
        val releaseCleanup = CompletableDeferred<Unit>()
        val dragStarted = CompletableDeferred<Unit>()
        val fling = launch(start = CoroutineStart.UNDISPATCHED) {
            state.scroll(MutatePriority.Default) {
                try { awaitCancellation() }
                finally {
                    withContext(NonCancellable) {
                        cleanupStarted.complete(Unit)
                        releaseCleanup.await()
                    }
                }
            }
        }
        var drag: kotlinx.coroutines.Job? = null
        try {
            requests.stopOnPress(this)
            withTimeout(2000) { cleanupStarted.await() }
            val newDrag = launch(start = CoroutineStart.UNDISPATCHED) {
                state.scroll(MutatePriority.UserInput) {
                    dragStarted.complete(Unit)
                    awaitCancellation()
                }
            }
            drag = newDrag
            releaseCleanup.complete(Unit)
            withTimeout(2000) { dragStarted.await(); fling.join() }
            assertTrue("The queued stop must not cancel the new UserInput owner", newDrag.isActive)
            assertTrue(state.isScrollInProgress)
        } finally {
            releaseCleanup.complete(Unit)
            fling.cancelAndJoin()
            drag?.cancelAndJoin()
        }
    }
}
