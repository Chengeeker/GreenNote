package com.green.note.network

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class RequestSignerTest {
    @Test fun newerReplyVersionMatchesDartSigningWithoutChangingDefaultVectors() {
        val signer = RequestSigner(ByteArray(1024) { 65 })
        val modern = signer.token("device", 1700000000, appCode = 2609291)
        assertEquals("v3JDJ5JDA0JE5qVTFNMll4TURBdk9EVTFORGxsTk9YTzN4ZGUuMlJWYVEyYjRKLjVIa1hmWnBqbGJjL2Nl", modern)
        assertNotEquals(signer.token("device", 1700000000), modern)
    }
    @Test fun matchesExistingDartImplementationForSyntheticMaterials() {
        val vectors = javaClass.getResource("/auth-vectors.json")!!.readText()
        val rows = JSONArray(vectors)
        val signer = RequestSigner(ByteArray(1024) { 65 })
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            assertEquals(row.getString("token"), signer.token(row.getString("device"), row.getLong("timestamp")))
        }
    }

    @Test fun missingOrTruncatedMaterialsFailExplicitly() {
        assertThrows(IllegalStateException::class.java) { RequestSigner(byteArrayOf()).token("device", 1700000000) }
        assertThrows(IllegalArgumentException::class.java) { RequestSigner(ByteArray(16)).token("device", 1700000000) }
    }
}
