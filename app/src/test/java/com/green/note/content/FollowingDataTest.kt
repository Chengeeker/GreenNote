package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class FollowingDataTest {
    @Test fun followedIdentityAndFanIdentityUseTheirOwnEnvelopes() {
        val row=JSONObject("""{"uid":"1","fuid":"2","username":"fan","fUserInfo":{"uid":"3","displayUserName":"followed","avatar":"https://a.test/x"},"userInfo":{"uid":"4","username":"viewer"}}""")
        val followed=relationUser(row,false)
        assertEquals("3",followed.getString("uid"));assertEquals("followed",followed.getString("username"))
        assertEquals("4",relationUser(row,true).getString("uid"));assertEquals("1",row.getString("uid"))
        assertEquals(mapOf("uid" to "4","isFriend" to "1"),relationQuery("4",2))
        assertEquals(mapOf("uid" to "4"),relationQuery("4",3))
    }
}
