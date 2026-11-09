package com.green.note.ui

/** Busy is also used for initial loads. Only an armed, released pull owns the header. */
internal enum class ReviewRefreshCycle {
    Idle, Ready, Running, Result;

    val holdsHeader get() = this == Running || this == Result
    val processing get() = this == Ready || this == Running

    fun release(armed: Boolean, busy: Boolean): ReviewRefreshCycle =
        if (this == Idle && armed && !busy) Ready else this

    fun start(busy: Boolean): ReviewRefreshCycle =
        if (this == Ready) if (busy) Idle else Running else this

    fun complete(): ReviewRefreshCycle = if (this == Running) Result else this
    fun interruptReady(): ReviewRefreshCycle = if (this == Ready) Idle else this
    fun dismiss(): ReviewRefreshCycle = Idle
}
