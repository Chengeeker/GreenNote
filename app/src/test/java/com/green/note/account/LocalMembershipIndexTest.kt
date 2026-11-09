package com.green.note.account

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LocalMembershipIndexTest {
    private fun snapshot(active: String = "a", favorite: String = "12"): String {
        val a = LocalAccounts.emptyProfile("a", "A").apply {
            getJSONObject("favorites").put(favorite, JSONObject().put("id", favorite))
            getJSONObject("follows").put("25", JSONObject().put("uid", "25"))
            getJSONObject("productFollows").put("36", JSONObject().put("id", "36"))
        }
        return LocalAccounts.canonical(listOf(a, LocalAccounts.emptyProfile("b", "B")), active).toString()
    }

    @Test fun repeatedCardsAndUnrelatedRevisionReuseOneParse() {
        var parses = 0
        val index = LocalMembershipIndex { parses++; JSONObject(it) }
        val state = AccountState(mode = AccountMode.ANONYMOUS, localJson = snapshot())
        repeat(100) {
            assertTrue(index.contains(state.copy(revision = it.toLong()), "favorites", "12"))
            assertTrue(index.contains(state, "follows", "25"))
            assertTrue(index.contains(state, "productFollows", "36"))
            assertFalse(index.contains(state, "favorites", "25"))
        }
        assertEquals(1, parses)
    }

    @Test fun switchingProfilesRestoringAndRemovingNeverKeepPreviousMembership() {
        val index = LocalMembershipIndex()
        val a = AccountState(mode = AccountMode.ANONYMOUS, localJson = snapshot())
        assertTrue(index.contains(a, "favorites", "12"))
        assertFalse(index.contains(a.copy(localJson = snapshot(active = "b")), "favorites", "12"))
        assertTrue(index.contains(a, "favorites", "12")) // rollback to the exact old snapshot
        val restored = a.copy(localJson = snapshot(favorite = "99"))
        assertFalse(index.contains(restored, "favorites", "12"))
        assertTrue(index.contains(restored, "favorites", "99"))
    }

    @Test fun leavingAnonymousClearsIndexAndNeverExposesStoredLocalFlags() {
        var parses = 0
        val index = LocalMembershipIndex { parses++; JSONObject(it) }
        val state = AccountState(mode = AccountMode.ANONYMOUS, localJson = snapshot())
        assertTrue(index.contains(state, "favorites", "12"))
        assertFalse(index.contains(state.copy(mode = AccountMode.COOKIE), "favorites", "12"))
        assertFalse(index.contains(state.copy(mode = AccountMode.GUEST), "follows", "25"))
        assertTrue(index.contains(state, "favorites", "12"))
        assertEquals(2, parses)
    }
}
