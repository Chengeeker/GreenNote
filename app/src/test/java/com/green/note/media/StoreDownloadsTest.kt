package com.green.note.media

import android.app.Application
import com.green.note.content.ContentApi
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf
import org.json.JSONObject

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class StoreDownloadsTest {
    @Test fun duplicateQueueSurvivesRestartAsPausedAndCanResumeOrRemove() = runBlocking {
        val app = RuntimeEnvironment.getApplication()
        val source = StoreDownloadSource("example.app", "1", "2")
        val store = StoreDownloads(app)
        store.enqueue("https://example.org/app.apk", "应用", source)
        assertEquals(StoreDownloadService::class.java.name, shadowOf(app).nextStartedService.component?.className)
        store.enqueue("https://example.org/other-signed-url.apk", "应用", source)
        val task = store.tasks.value.single()
        assertEquals(StoreDownloadState.QUEUED, task.state)
        assertNull(shadowOf(app).nextStartedService)

        val restored = StoreDownloads(app)
        assertEquals(StoreDownloadState.PAUSED, restored.tasks.value.single().state)
        restored.resume(task.id, object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject =
                error("unexpected request")
        })
        assertEquals(StoreDownloadState.QUEUED, restored.tasks.value.single().state)
        restored.pause(task.id)
        assertEquals(StoreDownloadState.PAUSED, restored.tasks.value.single().state)
        restored.remove(task.id)
        assertTrue(StoreDownloads(app).tasks.value.isEmpty())
    }
}
