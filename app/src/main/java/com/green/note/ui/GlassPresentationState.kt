package com.green.note.ui

internal data class GlassSwapToken(val epoch: Long, val updatesBeforeSwap: Long)

/** GL completion and main-thread texture updates must both belong to the current surface epoch. */
internal class GlassPresentationState {
    private var owner: Any? = null
    private var epoch = 0L
    private var updates = 0L
    private var successfulSwapUpdateFloor: Long? = null
    @Volatile
    var ready: Boolean = false
        private set

    @Synchronized
    fun begin(session: Any): Boolean {
        owner = session
        epoch++
        updates = 0L
        successfulSwapUpdateFloor = null
        val changed = ready
        ready = false
        return changed
    }

    @Synchronized
    fun presented(session: Any): Boolean {
        if (owner !== session || ready) return false
        updates++
        val floor = successfulSwapUpdateFloor ?: return false
        if (updates <= floor) return false
        ready = true
        return true
    }

    /** Called immediately before swapping a fully drawn buffer, not when capture starts. */
    @Synchronized
    fun startSwap(session: Any): GlassSwapToken? =
        if (owner !== session || ready) null else GlassSwapToken(epoch, updates)

    /** A texture callback may arrive while eglSwapBuffers is returning; hold it until success. */
    @Synchronized
    fun swapped(session: Any, token: GlassSwapToken): Boolean {
        if (owner !== session || token.epoch != epoch || ready) return false
        successfulSwapUpdateFloor = successfulSwapUpdateFloor?.let { minOf(it, token.updatesBeforeSwap) }
            ?: token.updatesBeforeSwap
        if (updates <= token.updatesBeforeSwap) return false
        ready = true
        return true
    }

    @Synchronized
    fun invalidate(session: Any): Boolean {
        if (owner !== session) return false
        owner = null
        epoch++
        successfulSwapUpdateFloor = null
        val changed = ready
        ready = false
        return changed
    }
}
