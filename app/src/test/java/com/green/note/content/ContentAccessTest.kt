package com.green.note.content

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class ContentAccessTest {
    @Test fun guestsMayOpenPublishDraftsButAnonymousMenuMatchesFlutter() {
        assertNull(publishMenuDenied(ContentSession()))
        assertNull(publishMenuDenied(ContentSession(authenticated = true)))
        assertEquals("当前为匿名登录，无法使用此功能", publishMenuDenied(ContentSession(anonymous = true)))
    }

    @Test fun collectionLongPressDoesNotTurnIntoAnonymousLocalFavorite() {
        assertEquals("请先登录", collectionPickerDenied(ContentSession()))
        assertEquals("匿名账户仅支持本地收藏，暂不支持收藏夹", collectionPickerDenied(ContentSession(anonymous = true)))
        assertNull(collectionPickerDenied(ContentSession(authenticated = true)))
    }

    @Test fun favoriteUsesFlutterActionPriorityAndNullFallback() {
        assertTrue(feedFavoriteFlag(JSONObject("""{"userAction":{"favorite":null,"collect":1},"isFavorite":0}""")))
        assertFalse(feedFavoriteFlag(JSONObject("""{"userAction":{"favorite":0,"collect":1},"isFavorite":1}""")))
        assertTrue(feedFavoriteFlag(JSONObject("""{"isFavorite":true}""")))
    }
}
