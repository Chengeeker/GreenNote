package com.green.note.account

import com.green.note.network.ApiSession
import com.green.note.network.VerifiedReadSessionStore

/** The network layer owns this opaque payload; account storage only encrypts and scopes it. */
class AccountVerifiedReadSessionStore(
    private val accounts: AccountRepository,
    private val session: () -> ApiSession,
) : VerifiedReadSessionStore {
    override suspend fun read(owner: ApiSession): String? =
        accounts.readVerifiedReadSession(owner.revision) { owner == session() }

    override suspend fun compareAndSet(owner: ApiSession, expected: String?, replacement: String?): Boolean =
        accounts.compareAndSetVerifiedReadSession(owner.revision, expected, replacement) { owner == session() }
}
