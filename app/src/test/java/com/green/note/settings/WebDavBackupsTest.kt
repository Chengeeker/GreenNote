package com.green.note.settings

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WebDavBackupsTest {
    @Test fun formValidationReportsEachInvalidFieldAndAcceptsLoopback() {
        assertEquals(setOf("url","username","password","directory"),webDavFieldErrors("http://dav.example"," "," ","../outside").keys)
        assertTrue(webDavFieldErrors("http://127.0.0.1:8080/dav","user","secret","GreenNote").isEmpty())
    }
    private fun fixture(version: Int) = JSONObject(checkNotNull(javaClass.getResource("/backups/flutter_v$version.json")).readText())

    @Test fun actualFlutterExportsRemainCompatibleAndSafeBackupIgnoresCredentials() {
        for (version in 1..3) {
            val checked = BackupFormat.validate(fixture(version))
            assertEquals(1.2f, checked.settings.fontScale)
            assertEquals("test-user", checked.config.username)
            if (version == 1) assertNull(checked.local) else {
                assertEquals("导出资料", checked.local!!.getString("name"))
                assertEquals("12345", checked.local.getJSONObject("publicIdentity").getString("uid"))
                assertFalse(checked.local.toString().contains("must-not-export"))
            }
            if (version == 3) assertEquals("synthetic-dav-password", checked.credentials!!.second) else assertNull(checked.credentials)
        }
        val safe = fixture(2).put("credentials", JSONObject().put("cookie", "not-allowed").put("webDavPassword", "not-allowed"))
        assertNull(BackupFormat.validate(safe).credentials)
    }

    @Test fun malformedBackupFailsBeforeAnyMutation() {
        for (version in 1..3) {
            val broken = fixture(version)
            broken.getJSONObject("preferences").put("themeMode", 9)
            assertThrows(IllegalArgumentException::class.java) { BackupFormat.validate(broken) }
        }
        val invalid = fixture(3)
        invalid.getJSONObject("credentials").put("cookie", "bad\nCookie")
        assertThrows(IllegalArgumentException::class.java) { BackupFormat.validate(invalid) }
        for (key in listOf("themeMode","customFontWeightDelta","autoClearCacheThresholdMb","imageSavePathType","videoSavePathType")) {
            val overflow=fixture(2);overflow.getJSONObject("preferences").put(key,4294967296L)
            assertThrows(IllegalArgumentException::class.java) { BackupFormat.validate(overflow) }
        }
        assertThrows(IllegalArgumentException::class.java) { BackupFormat.validate(fixture(3).put("accountMode", "unknown")) }
        assertNull(BackupFormat.validate(fixture(3)).accountMode)
    }

    @Test fun failedAccountSettingsOrPasswordWritesRestoreBothStores() = runBlocking {
        for (failure in listOf("account", "settings", "password")) {
            val checked = BackupFormat.validate(fixture(3))
            val originalPreferences = AppPreferences(fontScale = .85f)
            val originalConfig = WebDavConfig("https://old.example/", "old-user")
            var preferences = originalPreferences
            var config = originalConfig
            var local = "old-local"
            var password: String? = "old-password"
            var failed = false
            fun failOnce(stage: String) { if (!failed && failure == stage) { failed = true; throw IllegalStateException("synthetic failure") } }
            val writer = BackupRestoreWrites(
                { value, server -> preferences = value; config = server; failOnce("settings") },
                { failOnce("account"); local = it.toString() },
                { local = "old-local" },
                { password = it; failOnce("password") },
            )
            try { writer.apply(checked, originalPreferences, originalConfig, "old-password"); fail("Expected write failure") }
            catch (_: IllegalStateException) { }
            assertEquals(originalPreferences, preferences)
            assertEquals(originalConfig, config)
            assertEquals("old-local", local)
            assertEquals("old-password", password)
        }
    }

    @Test fun addressValidationAndEncodingPreventCredentialRedirectsOrTraversal() {
        assertEquals("https://dav.example/dav/", WebDavAddress.normalize("dav.example/dav").toString())
        listOf("http://dav.example", "https://user:password@dav.example", "https://dav.example/?secret=1", "https://dav.example/#fragment").forEach { bad ->
            assertThrows(IllegalArgumentException::class.java) { WebDavAddress.normalize(bad) }
        }
        listOf("", "..", "a/../b", "a\\b", "a\nb").forEach { bad -> assertThrows(IllegalArgumentException::class.java) { WebDavAddress.segments(bad) } }
        assertTrue(WebDavAddress.backupUrl(WebDavConfig("https://dav.example/dav/", directory = "备份/a?b")).toString().contains("a%3Fb/greennote_settings_latest.json"))
    }

    @Test fun guardedRollbackPreservesConcurrentEditsAndStillAttemptsOtherStores()=runBlocking {
        val checked=BackupFormat.validate(fixture(3));var preferences="old";var local="old";var password="old";var localRollback=false
        val writer=BackupRestoreWrites(
            writePreferences={_,_->preferences="restored"},writeLocal={local="restored"},
            rollbackLocal={localRollback=true;if(local=="restored")local="old"},
            writePassword={password="new-user-secret";preferences="new-user-settings";throw IllegalStateException("write failure")},
            rollbackPreferences={check(preferences=="restored"){"new settings retained"};preferences="old"},
            rollbackPassword={check(password=="restored"){"new secret retained"};password="old"},
        )
        try{writer.apply(checked,AppPreferences(),WebDavConfig(),"old");fail("Expected failure")}
        catch(error:IllegalStateException){assertEquals(2,error.suppressed.size)}
        assertEquals("new-user-settings",preferences);assertEquals("new-user-secret",password);assertEquals("old",local);assertTrue(localRollback)
    }

    @Test fun redirectIsNotFollowedAndOversizedDownloadsAreRejected() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "https://other.example/"))
            server.enqueue(MockResponse().setHeader("Content-Length", WebDavService.MAX_BACKUP_BYTES + 1))
            server.start()
            val config = WebDavConfig(server.url("/").toString(), "test-user")
            val service = WebDavService()
            assertFalse(service.test(config, "synthetic"))
            assertEquals(1, server.requestCount)
            try { service.download(config, "synthetic"); fail("Expected size rejection") } catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun downloadOnlyTreats404AsMissingAndKeepsAuthenticationErrorsDistinct() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val service = WebDavService()
            val config = WebDavConfig(server.url("/dav/").toString(), "synthetic-user", "备份")
            server.enqueue(MockResponse().setResponseCode(404))
            server.enqueue(MockResponse().setResponseCode(404))
            assertNull(service.download(config, "synthetic-password"))
            for (code in listOf(401, 403, 302, 429, 500)) {
                server.enqueue(MockResponse().setResponseCode(code))
                try { service.download(config, "synthetic-password"); fail("HTTP $code must not masquerade as missing") }
                catch (error: IllegalStateException) { assertTrue(error.message.orEmpty().contains(code.toString())) }
            }
            assertEquals(7, server.requestCount)
            server.enqueue(MockResponse().setBody("<html>login</html>"))
            try { service.download(config, "synthetic-password"); fail("Expected format error") }
            catch (error: IllegalStateException) { assertTrue(error.message.orEmpty().contains("JSON")) }
            assertEquals("/dav/%E5%A4%87%E4%BB%BD/greennote_settings_latest.json", server.takeRequest().path)
        }
    }

    @Test fun readsTheExactFlutterDoubleSlashLocationOnlyWhenTheCurrentFileIsMissing() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val service = WebDavService()
            val config = WebDavConfig(server.url("/dav/").toString(), "synthetic-user", "备份/sub")
            server.enqueue(MockResponse().setResponseCode(404))
            server.enqueue(MockResponse().setBody(fixture(3).toString()))
            val backup = checkNotNull(service.download(config, "synthetic-password"))
            assertEquals("12345", BackupFormat.validate(backup).local!!.getJSONObject("publicIdentity").getString("uid"))
            assertEquals("/dav/%E5%A4%87%E4%BB%BD/sub/greennote_settings_latest.json", server.takeRequest().path)
            assertEquals("/dav//%E5%A4%87%E4%BB%BD/sub/greennote_settings_latest.json", server.takeRequest().path)
            server.enqueue(MockResponse().setBody(fixture(2).toString()))
            assertEquals(2, service.download(config, "synthetic-password")!!.getInt("version"))
            assertEquals(3, server.requestCount)
            val root = config.copy(url = server.url("/").toString())
            assertEquals(WebDavAddress.backupUrl(root), WebDavAddress.backupUrl(root, legacyFlutter = true))
        }
    }
}
