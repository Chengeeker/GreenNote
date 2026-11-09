package com.green.note.account

import org.junit.Assert.*
import org.junit.Test

class LocalRestoreOwnershipTest {
    @Test fun unrelatedSecretRevisionDoesNotPreventThisBackupsLocalCompensation() {
        val applied = AccountState(mode = AccountMode.ANONYMOUS, revision = 4)
        requireLocalRestoreOwnership(applied, applied.copy(revision = 5))
    }
    @Test fun aConcurrentLocalEditOrSessionSwitchCannotBeOverwrittenByRollback() {
        val applied = AccountState(mode = AccountMode.ANONYMOUS, revision = 4)
        val edit = org.json.JSONObject(applied.localJson).put("name", "new profile").toString()
        listOf(applied.copy(localJson = edit), applied.copy(mode = AccountMode.COOKIE, cookie = "new session"), applied.copy(uid = "other user")).forEach { next ->
            try { requireLocalRestoreOwnership(applied, next); fail("Concurrent change was accepted") } catch (_: IllegalStateException) { }
        }
    }
}
