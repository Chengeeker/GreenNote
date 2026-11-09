package com.green.note.account

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AnonymousPublicIdentityTest {
    @Test fun uidPasteUsesOriginalAsciiDigitsOnlyFormatterAndLengthLimit() {
        assertEquals("12345", accountUidInput("UID: 12 3-45，６７"))
        assertEquals("1".repeat(30), accountUidInput("1".repeat(31)))
    }
    @Test fun creationCanRemainLocalOfflineButEditingDoesNotClearSavedIdentity() = runBlocking {
        val offline: suspend (String, Map<String, String>) -> JSONObject = { _, _ -> error("offline") }
        assertNull(optionalPublicIdentity("123", offline))
        val failure = runCatching { publicIdentity("123", offline) }.exceptionOrNull()
        assertEquals("offline", failure?.message)
    }

    @Test fun optionalLookupNeverTurnsCancellationIntoAccountCreation() = runBlocking {
        val failure = runCatching {
            optionalPublicIdentity("123") { _, _ -> throw CancellationException("owner left") }
        }.exceptionOrNull()
        assertTrue(failure is CancellationException)
    }

    @Test fun blankUidDoesNotIssueNetworkRequestsAndNestedPublicFieldsMerge() = runBlocking {
        assertNull(optionalPublicIdentity("") { _, _ -> error("must not request") })
        val identity = publicIdentity("123") { path, query ->
            assertEquals("123", query["uid"])
            if (path.endsWith("space")) JSONObject("""{"data":{"userInfo":{"username":"space","userAvatar":"avatar"}}}""")
            else JSONObject("""{"data":{"username":"profile"}}""")
        }
        assertEquals("123", identity!!.getString("uid"))
        assertEquals("profile", identity.getString("username"))
        assertEquals("avatar", identity.getString("userAvatar"))
    }
}
