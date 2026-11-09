package com.green.note.network

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class CaptchaCoordinator {
    class Pending(val error: CaptchaRequired, internal val result: CompletableDeferred<String?> = CompletableDeferred())
    private val mutex = Mutex()
    private val mutable = MutableStateFlow<Pending?>(null)
    val state = mutable.asStateFlow()
    suspend fun solve(error: CaptchaRequired): String? = mutex.withLock {
        val pending = Pending(error)
        mutable.value = pending
        try { pending.result.await() } finally { if (mutable.value === pending) mutable.value = null }
    }
    fun finish(pending: Pending, proof: String?) {
        if (mutable.value === pending && (proof == null || pending.error.challenge.proof(proof) != null)) pending.result.complete(proof)
    }
}
