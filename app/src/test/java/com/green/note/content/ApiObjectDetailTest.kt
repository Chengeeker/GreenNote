package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ApiObjectDetailTest {
    @Test fun rawDetailsKeepOnlyOriginalScalarFieldsAndHumanizeCamelCase() {
        val data = JSONObject("""{"userName":"甲","zero":0,"flag":false,"nothing":null,"object":{"a":1},"rows":[1]}""")
        assertEquals(mapOf("userName" to "甲", "zero" to "0", "flag" to "false", "nothing" to "null"), objectScalars(data).toMap())
        assertEquals("user Name", objectFieldLabel("userName"))
        assertEquals("APKName", objectFieldLabel("APKName"))
    }
}
