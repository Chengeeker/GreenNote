package com.green.note.network

import org.junit.Assert.*
import org.junit.Test

class OfficialDeviceIdentityTest {
    @Test fun onlyUniqueCompleteIdentifierIsAccepted() {
        assertEquals("identifier123", OfficialDeviceIdentity.parse("OAID: ignored\nShuzlmID：identifier123"))
        for (text in listOf("OAID: identifier123", "ShuzlmID: abc", "ShuzlmID: identifier123\nShuzlmID: identifier456")) {
            assertThrows(IllegalArgumentException::class.java) { OfficialDeviceIdentity.parse(text) }
        }
    }
    @Test fun encodedProfilePreservesPreviousFieldsAndRejectsInjection() {
        val profile = mapOf("manufacturer" to "vendor", "brand" to "brand", "model" to "model", "display" to "display")
        val encoded = OfficialDeviceIdentity.encode("identifier123", "legacy-uuid", profile)
        val fields = OfficialDeviceIdentity.fields(encoded)!!
        assertEquals(9, fields.size)
        assertEquals("identifier123", fields.first())
        assertEquals(" vendor", fields[4])
        assertEquals(fields.drop(1), OfficialDeviceIdentity.fields(OfficialDeviceIdentity.encode("identifier456", encoded, emptyMap()))!!.drop(1))
        assertThrows(IllegalArgumentException::class.java) { OfficialDeviceIdentity.encode("identifier123", "legacy", profile + ("model" to "x;injection")) }
        assertNull(OfficialDeviceIdentity.fields("legacy-uuid"))
    }
}
