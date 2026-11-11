package com.green.note.account

import android.content.Context
import android.util.AtomicFile
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], shadows = [ReplacingAtomicFileShadow::class])
class AccountRecoveryTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val storage = File(context.filesDir, "greennote-compose-account-v1.bin")
    private val recovery = File(context.noBackupFilesDir, "account-recovery")
    private var key: SecretKey? = null
    private val keys: (Boolean) -> SecretKey = { create ->
        key ?: if (create) KeyGenerator.getInstance("AES").apply { init(256) }.generateKey().also { key = it }
        else throw AccountKeyUnavailableException()
    }

    private suspend fun seed(): AccountState {
        val repository = AccountRepository(context, keys)
        repository.initialize()
        repository.createProfile("旧手机的匿名资料")
        repository.writeSecret("greennote.webdav.password", "synthetic")
        return repository.state.value
    }

    @Test fun transferredCiphertextIsPreservedBeforeCreatingAUsableGuestSession() = runBlocking {
        seed()
        val encrypted = storage.readBytes()
        key = null
        val migrated = AccountRepository(context, keys)
        try { migrated.initialize(); fail("Missing key must require recovery") }
        catch (_: AccountKeyUnavailableException) { }
        assertArrayEquals(encrypted, storage.readBytes())
        migrated.recoverAfterTransfer()
        assertArrayEquals(encrypted, recovery.listFiles()!!.single().readBytes())
        assertEquals(AccountMode.GUEST, migrated.state.value.mode)
        assertNull(migrated.readSecret("greennote.webdav.password"))
        migrated.createProfile("新手机")
        val restarted = AccountRepository(context, keys)
        restarted.initialize()
        assertEquals(migrated.state.value.localJson, restarted.state.value.localJson)
    }

    @Test fun ordinaryUpdateAndRestoredKeyKeepTheOriginalAccount() = runBlocking {
        val previous = seed()
        val originalKey = key
        val encrypted = storage.readBytes()
        key = null
        val repository = AccountRepository(context, keys)
        try { repository.initialize(); fail("Missing key must require recovery") }
        catch (_: AccountKeyUnavailableException) { }
        key = originalKey
        repository.recoverAfterTransfer()
        assertEquals(previous.localJson, repository.state.value.localJson)
        assertEquals("synthetic", repository.readSecret("greennote.webdav.password"))
        assertArrayEquals(encrypted, storage.readBytes())
        assertFalse(recovery.exists())
    }

    @Test fun backupFailureLeavesTheOriginalFileAndMissingKeyUntouched() = runBlocking {
        seed()
        val encrypted = storage.readBytes()
        key = null
        recovery.writeText("synthetic obstruction")
        val repository = AccountRepository(context, keys)
        try { repository.recoverAfterTransfer(); fail("Cannot recover without a verified backup") }
        catch (_: IllegalStateException) { }
        assertArrayEquals(encrypted, storage.readBytes())
        assertNull(key)
    }

    @Test fun interruptedRecoveryWithANewKeyStillPreservesTheOldCiphertext() = runBlocking {
        seed()
        val encrypted = storage.readBytes()
        key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val repository = AccountRepository(context, keys)
        repository.recoverAfterTransfer()
        assertArrayEquals(encrypted, recovery.listFiles()!!.single().readBytes())
        AccountRepository(context, keys).initialize()
    }

    @Test fun malformedStorageCannotBeSilentlyReset() = runBlocking {
        storage.writeBytes(byteArrayOf(1, 2, 3))
        val repository = AccountRepository(context, keys)
        try { repository.recoverAfterTransfer(); fail("Malformed data must remain protected") }
        catch (_: IllegalArgumentException) { }
        assertArrayEquals(byteArrayOf(1, 2, 3), storage.readBytes())
        assertFalse(recovery.exists())
    }
}

@Implements(AtomicFile::class)
class ReplacingAtomicFileShadow {
    companion object {
        // Windows File.renameTo cannot replace an existing file; Android's rename does.
        @JvmStatic @Implementation
        fun rename(source: File, target: File) {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }
}
