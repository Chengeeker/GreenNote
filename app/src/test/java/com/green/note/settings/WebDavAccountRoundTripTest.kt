package com.green.note.settings

import android.content.Context
import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import com.green.note.account.AccountMode
import com.green.note.account.AccountRepository
import com.green.note.account.ReplacingAtomicFileShadow
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import javax.crypto.KeyGenerator

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], shadows = [ReplacingAtomicFileShadow::class])
class WebDavAccountRoundTripTest {
    private val base = ApplicationProvider.getApplicationContext<Context>()
    private val avatar = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1cAAAAASUVORK5CYII="
    private val identity get() = JSONObject().put("uid", "12345").put("username", "公开身份").put("userAvatar", "https://example.com/avatar.png")
    private val cookie = "uid=12345; token=synthetic-token"
    private val user get() = JSONObject().put("data", JSONObject().put("uid", "12345").put("username", "登录账户"))
    private val config = WebDavConfig("https://example.com/dav/", "synthetic-user")

    private inner class Device(label: String) {
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir() = File(base.filesDir, label).apply { mkdirs() }
            override fun getNoBackupFilesDir() = File(filesDir, "no-backup").apply { mkdirs() }
            override fun getSharedPreferences(name: String, mode: Int) = base.getSharedPreferences("${label}_$name", mode)
        }
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val accounts = AccountRepository(context) { key }
        val settings = SettingsStore(context)
        val backups = WebDavBackups(settings, accounts) { user }
        suspend fun initialize() { accounts.initialize(); settings.initialize() }
    }

    @Test fun anonymousFullAndSafeBackupsCrossDeviceKeysWithEveryProfileAndActiveIdentity() = runBlocking {
        for (full in listOf(false, true)) {
            val old = Device("old-$full").apply { initialize() }
            old.accounts.createProfile("备用资料")
            old.accounts.createProfile("迁移资料", avatar, identity)
            old.accounts.toggleLocal("favorites", "7", JSONObject().put("id", "7").put("message", "synthetic favorite"))
            val expected = old.accounts.state.value.localJson
            val backup = old.backups.export(config, full)
            val new = Device("new-$full").apply { initialize() }
            new.backups.restore(JSONObject(backup.toString()))
            assertEquals(expected, new.accounts.state.value.localJson)
            assertEquals(AccountMode.ANONYMOUS, new.accounts.state.value.mode)
            val restarted = AccountRepository(new.context) { new.key }
            restarted.initialize()
            val local = restarted.exportLocal()
            assertEquals("迁移资料", local.getString("name"))
            assertEquals(avatar, local.getString("avatar"))
            assertEquals("12345", local.getJSONObject("publicIdentity").getString("uid"))
            assertEquals(3, local.getJSONArray("profiles").length())
            assertEquals(AccountMode.ANONYMOUS, restarted.state.value.mode)
        }
    }

    @Test fun fullBackupRestoresValidatedOfficialLoginThroughTheActualWebDavTransport() = runBlocking {
        val old = Device("official-old").apply { initialize() }
        old.accounts.acceptCookie(cookie) { user }
        old.accounts.writeSecret(WebDavBackups.PASSWORD_KEY, "synthetic-password")
        MockWebServer().use { server ->
            var uploaded = ""
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse = when (request.method) {
                    "MKCOL" -> MockResponse().setResponseCode(201)
                    "PUT" -> { uploaded = request.body.readUtf8(); MockResponse().setResponseCode(201) }
                    "PROPFIND" -> MockResponse().setResponseCode(207)
                    "GET" -> if (request.path == "/download") MockResponse().setBody(uploaded)
                        else MockResponse().setResponseCode(302).setHeader("Location", "/download")
                    else -> MockResponse().setResponseCode(405)
                }
            }
            server.start()
            val destination = config.copy(url = server.url("/dav/").toString())
            val transport = WebDavService()
            assertTrue(transport.test(destination, "synthetic-password"))
            assertTrue(transport.upload(destination, "synthetic-password", old.backups.export(destination, true)))
            val new = Device("official-new").apply { initialize() }
            var checkedCookie = ""
            val backups = WebDavBackups(new.settings, new.accounts) { checkedCookie = it; user }
            backups.restore(checkNotNull(transport.download(destination, "synthetic-password")))
            assertEquals(cookie, checkedCookie)
            assertEquals(cookie, new.accounts.state.value.requestCookie)
            assertEquals("12345", new.accounts.state.value.uid)
            assertEquals("synthetic-password", new.accounts.readSecret(WebDavBackups.PASSWORD_KEY))
            val restarted = AccountRepository(new.context) { new.key }
            restarted.initialize()
            assertTrue(restarted.state.value.authenticated)
        }
    }

    @Test fun anonymousBackupDoesNotLogIntoAnInactiveRememberedOfficialAccount() = runBlocking {
        val old = Device("inactive-old").apply { initialize() }
        old.accounts.acceptCookie(cookie) { user }
        old.accounts.createProfile("匿名资料", avatar, identity)
        val backup = old.backups.export(config, true)
        assertEquals("", backup.getJSONObject("credentials").getString("cookie"))
        val new = Device("inactive-new").apply { initialize() }
        WebDavBackups(new.settings, new.accounts) { error("Must not validate inactive credentials") }.restore(backup)
        assertEquals(AccountMode.ANONYMOUS, new.accounts.state.value.mode)
        assertEquals("匿名资料", new.accounts.exportLocal().getString("name"))
    }

    @Test fun rejectedLoginKeepsExistingSessionAndRestoresLocalProfiles() = runBlocking {
        val old = Device("rejected-old").apply { initialize() }
        old.accounts.createProfile("待恢复资料", avatar, identity)
        old.accounts.acceptCookie(cookie) { user }
        val new = Device("rejected-new").apply { initialize() }
        new.accounts.createProfile("新手机资料")
        val result = WebDavBackups(new.settings, new.accounts) { error("synthetic rejection") }
            .restore(old.backups.export(config, true))
        assertFalse(new.accounts.state.value.authenticated)
        assertEquals(AccountMode.ANONYMOUS, new.accounts.state.value.mode)
        assertEquals(old.accounts.state.value.localJson, new.accounts.state.value.localJson)
        assertTrue(result.second.contains("登录"))
    }

    @Test fun safeAnonymousBackupDoesNotReplaceAnExistingOfficialLogin() = runBlocking {
        val old = Device("safe-old").apply { initialize() }
        old.accounts.createProfile("旧匿名资料", avatar, identity)
        val new = Device("safe-new").apply { initialize() }
        new.accounts.acceptCookie(cookie) { user }
        val backup = old.backups.export(config, false)
        assertFalse(backup.has("credentials"))
        new.backups.restore(backup)
        assertTrue(new.accounts.state.value.authenticated)
        assertEquals(cookie, new.accounts.state.value.requestCookie)
        assertEquals(old.accounts.state.value.localJson, new.accounts.state.value.localJson)
    }

    @Test fun failedWriteRollbackRestoresTheOriginalModeAsWellAsTheProfile() = runBlocking {
        val device = Device("rollback").apply { initialize() }
        val previous = device.accounts.state.value
        val profile = com.green.note.account.LocalAccounts.emptyProfile("restored", "旧资料").put("avatar", avatar).put("publicIdentity", identity)
        val local = com.green.note.account.LocalAccounts.canonical(listOf(profile), "restored")
        val applied = device.accounts.restoreLocalFromBackup(local, previous, activateAnonymous = true)
        assertTrue(device.accounts.state.value.anonymous)
        device.accounts.restoreLocalBackupIfUnchanged(previous, applied)
        assertEquals(previous.mode, device.accounts.state.value.mode)
        assertEquals(previous.localJson, device.accounts.state.value.localJson)
    }
}
