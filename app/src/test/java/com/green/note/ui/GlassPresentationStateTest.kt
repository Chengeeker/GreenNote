package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class GlassPresentationStateTest {
    @Test fun fallbackLastsUntilFirstPresentedTextureAndDoesNotNotifyEachFrame() {
        val state=GlassPresentationState();val session=Any()
        assertFalse(state.ready)
        assertFalse(state.begin(session))
        assertFalse(state.ready)
        val swap=state.startSwap(session)!!
        assertFalse(state.swapped(session,swap))
        assertTrue(state.presented(session))
        assertTrue(state.ready)
        assertFalse(state.presented(session))
    }

    @Test fun failedOrDestroyedSessionCannotBecomeReadyFromALateTextureCallback() {
        val state=GlassPresentationState();val session=Any()
        state.begin(session);state.swapped(session,state.startSwap(session)!!);state.presented(session)
        assertTrue(state.invalidate(session))
        assertFalse(state.ready)
        assertFalse(state.presented(session))
        assertFalse(state.invalidate(session))
    }

    @Test fun recreationRejectsPreviousSessionFramesAndCleanup() {
        val state=GlassPresentationState();val old=Any();val current=Any()
        state.begin(old);state.swapped(old,state.startSwap(old)!!);state.presented(old)
        assertTrue(state.begin(current))
        assertFalse(state.ready)
        assertFalse(state.presented(old))
        state.swapped(current,state.startSwap(current)!!)
        assertTrue(state.presented(current))
        assertFalse(state.invalidate(old))
        assertTrue(state.ready)
    }

    @Test fun resizeRequiresAnotherActualTextureUpdate() {
        val state=GlassPresentationState();val session=Any()
        state.begin(session);state.swapped(session,state.startSwap(session)!!);state.presented(session)
        assertTrue(state.begin(session))
        assertFalse(state.ready)
        assertFalse(state.presented(session))
        state.swapped(session,state.startSwap(session)!!)
        assertTrue(state.presented(session))
    }

    @Test fun initializationUpdatesCannotRetireFallbackBeforeARealSwap() {
        val state=GlassPresentationState();val session=Any()
        state.begin(session)
        repeat(3){assertFalse(state.presented(session))}
        val swap=state.startSwap(session)!!
        assertFalse(state.swapped(session,swap))
        assertFalse(state.ready)
        assertTrue(state.presented(session))
    }

    @Test fun updateDuringSwapWaitsForConfirmedSuccessRatherThanLosingTheOnlyFrame() {
        val state=GlassPresentationState();val session=Any()
        state.begin(session)
        val swap=state.startSwap(session)!!
        assertFalse(state.presented(session))
        assertFalse(state.ready)
        assertTrue(state.swapped(session,swap))
        assertTrue(state.ready)
    }

    @Test fun failedSwapDoesNotQualifyAnUpdateAndResizeRejectsAnOldCompletion() {
        val state=GlassPresentationState();val session=Any()
        state.begin(session)
        val failed=state.startSwap(session)!!
        assertFalse(state.presented(session))
        state.invalidate(session)
        assertFalse(state.swapped(session,failed))
        state.begin(session)
        val beforeResize=state.startSwap(session)!!
        state.begin(session)
        assertFalse(state.presented(session))
        assertFalse(state.swapped(session,beforeResize))
        val current=state.startSwap(session)!!
        assertFalse(state.swapped(session,current))
        assertTrue(state.presented(session))
    }
}
