package com.green.note.content

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

internal fun digitalHomeFixture(title: String = "首屏数据") = JSONObject().put("data", JSONArray().put(
    JSONObject().put("entityType", "card").put("entityTemplate", "textCard").put("title", title)))

class DigitalHomeStateTest {
    @Test fun lateFollowCannotReplaceARefreshedCardAndBindingSameSourceReusesRows() = runBlocking {
        var pages = 0
        val follow = CompletableDeferred<JSONObject>()
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject =
                if (query["url"] == "#/product/followProductList") follow.await()
                else digitalHomeFixture("page-${++pages}")
        }
        val holder = DigitalHomeState(api, ContentSession(authenticated = true))
        holder.bind(null)
        val oldFollow = holder.content.rows.first()
        val resolving = launch(start = CoroutineStart.UNDISPATCHED) { holder.resolveFollow(oldFollow) }
        assertFalse(holder.content.busy)
        assertTrue(holder.content.rows.any { it.text("title") == "page-1" })
        holder.bind(null)
        assertEquals(1, pages)
        holder.content.load(true)
        val newFollow = holder.content.rows.first()
        assertNotSame(oldFollow, newFollow)
        follow.complete(JSONObject().put("data", JSONArray().put(JSONObject().put("entityType", "product").put("id", "old"))))
        resolving.join()
        assertSame(newFollow, holder.content.rows.first())
        assertTrue(newFollow.optBoolean("_digitalFollowPending"))
        assertTrue(holder.content.rows.any { it.text("title") == "page-2" })
    }

    @Test fun primaryFailureIsNotAnEmptySuccessAndExistingEmptyServerFollowNeedsNoFallback() = runBlocking {
        var fail = true
        var calls = 0
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                calls++
                if (fail) error("offline")
                return digitalHomeFixture().apply { getJSONArray("data").put(JSONObject().put("entityType", "card")
                    .put("entityTemplate", "followCard").put("title", "我的关注").put("entities", JSONArray())) }
            }
        }
        val holder = DigitalHomeState(api, ContentSession(authenticated = true))
        holder.bind(null)
        assertEquals("offline", holder.content.error)
        assertTrue(holder.content.rows.isEmpty())
        assertTrue(holder.content.needsInitialLoad)
        fail = false
        holder.content.load(true)
        assertNull(holder.content.error)
        assertFalse(holder.content.rows.first().optBoolean("_digitalFollowPending"))
        assertEquals(2, calls)
    }
}
