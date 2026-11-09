package com.green.note.account

import org.junit.Assert.assertThrows
import org.junit.Test

class AccountGenerationTest {
    @Test fun pendingMutationCannotCrossLoginOrAnonymousProfileSwitch() {
        val original = AccountState(mode = AccountMode.ANONYMOUS, revision = 7)
        requireAccountGeneration(original, original)
        assertThrows(IllegalStateException::class.java) { requireAccountGeneration(original, original.copy(mode = AccountMode.COOKIE, revision = 8)) }
        assertThrows(IllegalStateException::class.java) { requireAccountGeneration(original, original.copy(localJson = LocalAccounts.canonical(listOf(LocalAccounts.emptyProfile("other", "另一个账户")), "other").toString(), revision = 8)) }
        assertThrows(IllegalStateException::class.java) { requireAccountGeneration(original, original.copy(revision = 8)) }
    }
    @Test fun htmlLoginHashDecodesOnceWithoutMarkupParsing() {
        org.junit.Assert.assertEquals("a&b\"c'", OfficialLoginSession.decodeHtml("a&amp;b&#x22;c&#39;"))
        org.junit.Assert.assertEquals("&amp;", OfficialLoginSession.decodeHtml("&amp;amp;"))
    }
}
