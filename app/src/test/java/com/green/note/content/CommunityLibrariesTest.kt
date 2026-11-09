package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CommunityLibrariesTest {
    @Test fun channelLibrariesRetainAllThreeDistinctRequests() {
        val routes = communityLibraryRoutes("dyh")
        assertEquals(listOf("关注的号", "订阅的号", "管理的号"), routes.map { it.title })
        assertEquals(listOf("/v6/user/dyhFollowList", "/v6/user/dyhSubscribe", "/v6/user/editorDyhList"), routes.map { it.path })
        assertEquals("/v6/user/hitHistoryList", communityLibraryRoutes("history").single().path)
        assertEquals("/v6/user/productAlbumList", communityLibraryRoutes("anylist").single().path)
        assertEquals("/v6/user/albumList", communityLibraryRoutes("albums").single().path)
    }
    @Test fun submittedFilterMatchesLoadedNestedTextWithoutMutatingRows() {
        val row = JSONObject("""{"title":"示例","userInfo":{"username":"ExampleUser"}}""")
        val before = row.toString()
        assertTrue(communityLibraryMatches(row, " exampleuser "))
        assertTrue(communityLibraryMatches(row, "示例"))
        assertTrue(communityLibraryMatches(row, ""))
        assertFalse(communityLibraryMatches(row, "missing"))
        assertEquals(before, row.toString())
    }
}
