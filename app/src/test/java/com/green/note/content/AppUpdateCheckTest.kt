package com.green.note.content

import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AppUpdateCheckTest {
    @Test fun changingPriorityKeepsCompletedChecksAndChangesTheNextBatch() = runBlocking {
        val apps = (1..6).map { InstalledApp("example.app$it", "应用$it", "1.0", 1, false, true, 0, 0, true) }
        val quiet = mutableStateOf(true)
        val first = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val high = CompletableDeferred<Unit>()
        val releaseHigh = CompletableDeferred<Unit>()
        val requests = mutableListOf<String>()
        var active = 0
        val api = UpdateTestApi { id ->
            requests += id
            active++
            try {
                when (id.last()) {
                    '1' -> { first.complete(Unit); releaseFirst.await() }
                    '2', '3', '4' -> {
                        if (active == 3) high.complete(Unit)
                        releaseHigh.await()
                    }
                    else -> assertEquals(1, active)
                }
                updateDetail(id, 2)
            } finally { active-- }
        }
        val check = AppUpdateCheck(apps)
        val worker = launch { check.run(api) { quiet.value } }
        withTimeout(2000) { first.await() }
        assertEquals(listOf("example.app1"), requests)
        quiet.value = false
        releaseFirst.complete(Unit)
        withTimeout(2000) { high.await() }
        assertEquals(1, check.updates.size)
        quiet.value = true
        releaseHigh.complete(Unit)
        withTimeout(3000) { worker.join() }
        assertTrue(check.complete)
        assertEquals(apps.map(InstalledApp::packageName), requests)
        assertEquals(6, check.updates.size)
    }

    @Test fun resumesAfterCancelledBatchAndDoesNotRepeatCompletedCheck() = runBlocking {
        val apps = (1..5).map { InstalledApp("example.app$it", "应用$it", "1.0", 1, false, true, 0, 2000, true) }
        val check = AppUpdateCheck(apps)
        val requests = mutableListOf<String>()
        val secondBatchStarted = CompletableDeferred<Unit>()
        var block = true
        val api = UpdateTestApi { id ->
            requests += id
            if (id.endsWith("4") && block) {
                secondBatchStarted.complete(Unit)
                awaitCancellation()
            }
            if (id.endsWith("5")) JSONObject() else updateDetail(id, code = if (id.endsWith("1") || id.endsWith("4")) 2 else 1)
        }

        val job = launch { check.run(api) }
        secondBatchStarted.await()
        assertEquals(listOf("example.app1"), check.updates.map { it.app.packageName })
        job.cancelAndJoin()
        assertTrue(check.pending)

        block = false
        check.run(api)
        assertTrue(check.complete)
        assertEquals(1, check.failures)
        assertEquals(listOf("example.app1", "example.app4"), check.updates.map { it.app.packageName })
        assertEquals(1, requests.count { it == "example.app1" })
        val count = requests.size
        check.run(api)
        assertEquals(count, requests.size)

        check.restart()
        assertEquals(2, check.updates.size)
        check.run(api)
        assertEquals(count + apps.size, requests.size)
    }

    @Test fun stoppedCheckDiscardsUncommittedBatch() = runBlocking {
        val app = InstalledApp("example.app", "应用", "1.0", 1, false, true, 0, 0, true)
        val check = AppUpdateCheck(listOf(app))
        val release = CompletableDeferred<Unit>()
        val entered = CompletableDeferred<Unit>()
        val api = UpdateTestApi { id ->
            entered.complete(Unit)
            release.await()
            updateDetail(id, code = 2)
        }
        val job = launch { check.run(api) }
        entered.await()
        check.stop()
        check.restart()
        release.complete(Unit)
        job.join()
        assertTrue(check.updates.isEmpty())
        check.run(api)
        assertEquals(2L, check.updates.single().versionCode)
    }

    @Test fun requestsAtMostThreeAppsAndRejectsMismatchedDetails() = runBlocking {
        val apps = (1..7).map { InstalledApp("example.app$it", "应用$it", "1.0", 1, false, true, 0, 0, true) }
        var inFlight = 0
        var maximum = 0
        val check = AppUpdateCheck(apps)
        check.run(UpdateTestApi { id ->
            inFlight++
            maximum = maxOf(maximum, inFlight)
            yield()
            inFlight--
            updateDetail(if (id.endsWith("7")) "different.app" else id, 2)
        })
        assertEquals(3, maximum)
        assertEquals(6, check.updates.size)
        assertEquals(1, check.failures)
    }
}

internal class UpdateTestApi(private val detail: suspend (String) -> JSONObject) : ContentApi {
    override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
        assertEquals("/v6/apk/detail", path)
        assertEquals("GET", method)
        assertNull(body)
        return detail(query.getValue("id"))
    }
}

internal fun updateDetail(id: String, code: Long) = JSONObject().put("data", JSONObject()
    .put("apkname", id).put("apkversioncode", code).put("apkversionname", "$code.0").put("apksize", "31.5 MB"))
