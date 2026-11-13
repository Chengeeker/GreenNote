package com.green.note

import com.green.note.account.AccountMode
import com.green.note.account.AccountState
import com.green.note.content.commentFeedSeed
import com.green.note.content.moveCommentFeedSeeds
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CommentImportNavigationTest {
    @Test fun deviceEpochAndDisplayEditsCanRetainTheSameOfficialAccount() {
        val opened = AccountState(mode = AccountMode.COOKIE, uid = "7", cookie = "uid=7; token=synthetic-a",
            username = "name", revision = 5, sessionRevision = 3)
        assertTrue(sameCommentRecoveryAccount(opened,
            opened.copy(username = "renamed", revision = 6, sessionRevision = 4)))
        assertTrue(sameCommentRecoveryAccount(opened, opened)) // Importing the same identifier is still a success.
    }

    @Test fun sameDisplayedUserWithNewCredentialsOrModeCannotRetainContent() {
        val opened = AccountState(mode = AccountMode.COOKIE, uid = "7", cookie = "uid=7; token=synthetic-a",
            sessionRevision = 3)
        assertFalse(sameCommentRecoveryAccount(opened, opened.copy(cookie = "uid=7; token=synthetic-b")))
        assertFalse(sameCommentRecoveryAccount(opened, opened.copy(uid = "8")))
        assertFalse(sameCommentRecoveryAccount(opened, opened.copy(mode = AccountMode.ANONYMOUS)))
        assertFalse(sameCommentRecoveryAccount(opened, opened.copy(mode = AccountMode.GUEST)))
        assertFalse(sameCommentRecoveryAccount(null, opened))
    }

    @Test fun anonymousProfileAndPublicIdentityBothBelongToTheNavigationOwner() {
        val first = AccountState(mode = AccountMode.ANONYMOUS, sessionRevision = 4)
        val local = JSONObject(first.localJson).put("activeProfileId", "profile-a")
            .put("publicIdentity", JSONObject().put("uid", "7"))
        val opened = first.copy(localJson = local.toString())
        assertTrue(sameCommentRecoveryAccount(opened, opened.copy(sessionRevision = 5)))
        assertFalse(sameCommentRecoveryAccount(opened,
            opened.copy(localJson = JSONObject(local.toString()).put("activeProfileId", "profile-b").toString())))
        assertFalse(sameCommentRecoveryAccount(opened,
            opened.copy(localJson = JSONObject(local.toString()).put("publicIdentity", JSONObject().put("uid", "8")).toString())))
    }

    @Test fun importedDeviceKeepsTheExactFeedObjectBeforeAndAfterScopeMigration() {
        val body = JSONObject().put("id", "42").put("message", "already readable body")
        val other = JSONObject().put("id", "43")
        val community = JSONObject().put("id", "community")
        val entities = mutableMapOf("feed:old:42" to body, "feed:other:43" to other, "community:4" to community)
        assertSame(body, commentFeedSeed(entities, "42", "new", "old", preserve = true))
        assertNull(commentFeedSeed(entities, "42", "new", "old", preserve = false))
        moveCommentFeedSeeds(entities, "old", "new")
        assertSame(body, commentFeedSeed(entities, "42", "new", "old", preserve = false))
        assertFalse(entities.containsKey("feed:old:42"))
        assertSame(other, entities["feed:other:43"])
        assertSame(community, entities["community:4"])
        moveCommentFeedSeeds(entities, "new", "new")
        assertSame(body, entities["feed:new:42"])
    }
}
