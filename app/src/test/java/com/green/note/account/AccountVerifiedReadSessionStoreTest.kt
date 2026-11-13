package com.green.note.account

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.green.note.network.ApiSession
import com.green.note.settings.SettingsStore
import com.green.note.settings.WebDavBackups
import com.green.note.settings.WebDavConfig
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], shadows = [ReplacingAtomicFileShadow::class])
class AccountVerifiedReadSessionStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val storage = File(context.filesDir, "greennote-compose-account-v1.bin")
    private val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    private var keyAvailable = true
    private val keyRequests = mutableListOf<Boolean>()
    private val keys: (Boolean) -> SecretKey = { create ->
        keyRequests += create
        if (!keyAvailable) throw AccountKeyUnavailableException()
        key
    }
    private var device = "synthetic-guest-device"
    private val payload = "synthetic-read-proof-do-not-export"
    private val cookie = "uid=12345; token=synthetic-account-token"
    private val user get() = JSONObject().put("data", JSONObject().put("uid", "12345").put("username", "测试账号"))

    private suspend fun repository() = AccountRepository(context, keys).also { it.initialize() }
    private fun session(accounts: AccountRepository) = accounts.state.value.let {
        ApiSession(device, it.requestCookie, it.anonymous, it.sessionRevision)
    }
    private fun store(accounts: AccountRepository) = AccountVerifiedReadSessionStore(accounts) { session(accounts) }
    private fun publicIdentity(name: String = "公开名字", uid: String = "42") = JSONObject()
        .put("uid", uid).put("username", name).put("userAvatar", "")

    @Test fun restartKeepsTheEncryptedCacheAndEpochWithoutChangingAccountGeneration() = runBlocking {
        val accounts = repository()
        accounts.writeSecret("guest_device_code", device)
        accounts.createProfile("匿名资料")
        val before = accounts.state.value
        val owner = session(accounts)
        assertTrue(store(accounts).compareAndSet(owner, null, payload))
        assertEquals(before, accounts.state.value)
        assertFalse(storage.readBytes().toString(Charsets.ISO_8859_1).contains(payload))

        val restarted = repository()
        assertEquals(before.sessionRevision, restarted.state.value.sessionRevision)
        assertEquals(before.localJson, restarted.state.value.localJson)
        assertEquals(before.mode, restarted.state.value.mode)
        assertEquals(owner, session(restarted))
        assertEquals(payload, store(restarted).read(session(restarted)))
    }

    @Test fun logoutAndLoginWithTheSameCookieCannotAcceptAnOldWriter() = runBlocking {
        val accounts = repository()
        accounts.acceptCookie(cookie) { user }
        val cache = store(accounts)
        val oldOwner = session(accounts)
        assertTrue(cache.compareAndSet(oldOwner, null, payload))

        accounts.logout()
        assertEquals(oldOwner.revision + 1, accounts.state.value.sessionRevision)
        assertNull(cache.read(oldOwner))
        assertNull(cache.read(session(accounts)))
        accounts.acceptCookie(cookie) { user }
        val currentOwner = session(accounts)
        assertEquals(oldOwner.revision + 2, currentOwner.revision)
        assertNull(cache.read(currentOwner))
        assertFalse(cache.compareAndSet(oldOwner, null, "late old response"))
        assertTrue(cache.compareAndSet(currentOwner, null, "new accepted response"))
        assertFalse(cache.compareAndSet(oldOwner, "new accepted response", null))
        assertEquals("new accepted response", cache.read(currentOwner))
        assertEquals(currentOwner.revision, repository().state.value.sessionRevision)
    }

    @Test fun anonymousProfileAndPublicIdentitySwitchesInvalidateCachedVerification() = runBlocking {
        val accounts = repository()
        accounts.createProfile("资料一")
        val firstId = accounts.exportLocal().getString("activeProfileId")
        val cache = store(accounts)
        var owner = session(accounts)
        assertTrue(cache.compareAndSet(owner, null, payload))

        accounts.createProfile("资料二")
        assertEquals(owner.revision + 1, accounts.state.value.sessionRevision)
        assertNull(cache.read(session(accounts)))
        owner = session(accounts)
        assertTrue(cache.compareAndSet(owner, null, payload))
        accounts.switchProfile(firstId)
        assertEquals(owner.revision + 1, accounts.state.value.sessionRevision)
        assertNull(cache.read(session(accounts)))

        owner = session(accounts)
        assertTrue(cache.compareAndSet(owner, null, payload))
        accounts.updateProfile(firstId, "公开资料", "", publicIdentity())
        assertEquals(owner.revision + 1, accounts.state.value.sessionRevision)
        assertNull(cache.read(session(accounts)))
        assertFalse(cache.compareAndSet(owner, null, "late profile response"))
    }

    @Test fun deviceChangesClearCacheAndPersistTheirEpochInTheSameSnapshot() = runBlocking {
        val accounts = repository()
        accounts.writeSecret("guest_device_code", device)
        val cache = store(accounts)
        val changes = listOf("guest_device_code" to "new-guest-device", "official_device_code" to "official-device", "official_device_code" to null)
        for ((field, replacement) in changes) {
            val owner = session(accounts)
            assertTrue(cache.compareAndSet(owner, null, payload))
            accounts.writeSecret(field, replacement)
            device = replacement ?: "new-guest-device"
            assertEquals(owner.revision + 1, accounts.state.value.sessionRevision)
            assertNull(cache.read(session(accounts)))
            assertFalse(cache.compareAndSet(owner, null, "late device response"))
            val restarted = repository()
            assertEquals(accounts.state.value.sessionRevision, restarted.state.value.sessionRevision)
            assertNull(store(restarted).read(session(restarted)))
        }
    }

    @Test fun unrelatedSecretsSameDeviceAndDisplayEditsRetainVerification() = runBlocking {
        val accounts = repository()
        accounts.writeSecret("guest_device_code", device)
        accounts.createProfile("原名字", publicIdentity = publicIdentity())
        val id = accounts.exportLocal().getString("activeProfileId")
        val owner = session(accounts)
        val cache = store(accounts)
        assertTrue(cache.compareAndSet(owner, null, payload))

        accounts.writeSecret("guest_device_code", device)
        accounts.writeSecret("greennote.webdav.password", "before")
        assertTrue(accounts.compareAndSetSecret("greennote.webdav.password", "before", "after"))
        accounts.updateProfile(id, "新名字", "", publicIdentity(name = "新的公开名字"))
        accounts.toggleLocal("favorites", "7", JSONObject().put("id", "7").put("message", "synthetic favorite"))
        assertEquals(owner.revision, accounts.state.value.sessionRevision)
        assertEquals(payload, cache.read(owner))
        assertEquals("after", accounts.readSecret("greennote.webdav.password"))
        assertEquals(payload, store(repository()).read(owner))
    }

    @Test fun compareAndSetRejectsStaleValuesAndChecksTheCurrentOwnerUnderTheAccountLock() = runBlocking {
        val accounts = repository()
        val owner = session(accounts)
        val cache = store(accounts)
        val before = accounts.state.value
        assertTrue(cache.compareAndSet(owner, null, payload))
        assertFalse(cache.compareAndSet(owner, null, "stale insert"))
        assertTrue(cache.compareAndSet(owner, payload, "newer snapshot"))
        assertFalse(cache.compareAndSet(owner, payload, null))
        assertEquals(before, accounts.state.value)

        device = "another-device-with-the-same-epoch"
        assertNull(cache.read(owner))
        assertFalse(cache.compareAndSet(owner, "newer snapshot", null))
        device = owner.device
        assertEquals("newer snapshot", cache.read(owner))
        accounts.activateAnonymous()
        val staleSessionProvider = AccountVerifiedReadSessionStore(accounts) { owner }
        assertNull(staleSessionProvider.read(owner))
        assertFalse(staleSessionProvider.compareAndSet(owner, null, payload))
    }

    @Test fun restoringOldLocalProfilesAdvancesTheCurrentEpochInsteadOfRestoringAnOldOne() = runBlocking {
        val accounts = repository()
        accounts.createProfile("旧资料")
        val previous = accounts.state.value
        accounts.createProfile("现有资料")
        val current = accounts.state.value
        val cache = store(accounts)
        assertTrue(cache.compareAndSet(session(accounts), null, payload))
        val applied = accounts.restoreLocalFromBackup(JSONObject(previous.localJson), current)
        assertEquals(current.sessionRevision + 1, applied.sessionRevision)
        assertNull(cache.read(session(accounts)))
        assertTrue(cache.compareAndSet(session(accounts), null, payload))
        accounts.restoreLocalBackupIfUnchanged(current, applied)
        assertEquals(applied.sessionRevision + 1, accounts.state.value.sessionRevision)
        assertEquals(current.localJson, accounts.state.value.localJson)
        assertNull(cache.read(session(accounts)))
        assertEquals(accounts.state.value.sessionRevision, repository().state.value.sessionRevision)
    }

    @Test fun legacyEncryptedAccountsWithoutAnEpochRetainTheirExistingData() = runBlocking {
        val accounts = repository()
        accounts.createProfile("已有资料")
        accounts.writeSecret("greennote.webdav.password", "synthetic existing secret")
        val expected = accounts.state.value
        rewriteEncryptedRoot { it.remove("sessionRevision") }
        val encrypted = storage.readBytes()

        val reopened = repository()
        assertEquals(0L, reopened.state.value.sessionRevision)
        assertEquals(expected.localJson, reopened.state.value.localJson)
        assertEquals(expected.mode, reopened.state.value.mode)
        assertEquals("synthetic existing secret", reopened.readSecret("greennote.webdav.password"))
        assertArrayEquals(encrypted, storage.readBytes())
        assertTrue(store(reopened).compareAndSet(session(reopened), null, payload))
        val restarted = repository()
        assertEquals(0L, restarted.state.value.sessionRevision)
        assertEquals(payload, store(restarted).read(session(restarted)))
    }

    @Test fun malformedPersistedEpochCannotSilentlyResetTheEncryptedAccount() = runBlocking {
        repository().createProfile("保留资料")
        rewriteEncryptedRoot { it.put("sessionRevision", -1) }
        val encrypted = storage.readBytes()
        try {
            AccountRepository(context, keys).recoverAfterTransfer()
            fail("An invalid epoch must not reset the account")
        } catch (_: IllegalArgumentException) { }
        assertArrayEquals(encrypted, storage.readBytes())
        assertFalse(File(context.noBackupFilesDir, "account-recovery").exists())
    }

    @Test fun failedCacheWritesKeepTheLastEncryptedAccountAndCache() = runBlocking {
        val accounts = repository()
        accounts.createProfile("现有资料")
        val owner = session(accounts)
        val cache = store(accounts)
        assertTrue(cache.compareAndSet(owner, null, payload))
        val previous = accounts.state.value
        val encrypted = storage.readBytes()
        keyAvailable = false
        try {
            cache.compareAndSet(owner, payload, "failed replacement")
            fail("The simulated write must fail")
        } catch (_: IllegalStateException) { }
        assertFalse("A cache update must not create a replacement account key", keyRequests.last())
        assertEquals(previous, accounts.state.value)
        assertEquals(payload, cache.read(owner))
        assertArrayEquals(encrypted, storage.readBytes())
        keyAvailable = true
        assertEquals(payload, store(repository()).read(owner))
    }

    @Test fun localAndWebDavExportsNeverIncludeTheVerificationSnapshot() = runBlocking {
        val accounts = repository()
        accounts.createProfile("可备份资料")
        assertTrue(store(accounts).compareAndSet(session(accounts), null, payload))
        val settings = SettingsStore(context).also { it.initialize() }
        val backups = WebDavBackups(settings, accounts) { error("Export must not validate an account") }
        val config = WebDavConfig("https://example.com/dav/", "synthetic-user")
        val exports = listOf(accounts.exportLocal(), backups.export(config, false), backups.export(config, true))
        for (exported in exports) {
            assertFalse(exported.toString().contains(payload))
            assertFalse(exported.toString().contains("greennote.read.verification.v1"))
        }
    }

    private fun rewriteEncryptedRoot(update: (JSONObject) -> Unit) {
        val encrypted = storage.readBytes()
        val read = Cipher.getInstance("AES/GCM/NoPadding")
        read.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, encrypted.copyOfRange(1, 13)))
        val root = JSONObject(String(read.doFinal(encrypted.copyOfRange(13, encrypted.size)), Charsets.UTF_8))
        update(root)
        val write = Cipher.getInstance("AES/GCM/NoPadding")
        write.init(Cipher.ENCRYPT_MODE, key)
        storage.writeBytes(byteArrayOf(1) + write.iv + write.doFinal(root.toString().toByteArray(Charsets.UTF_8)))
    }
}
