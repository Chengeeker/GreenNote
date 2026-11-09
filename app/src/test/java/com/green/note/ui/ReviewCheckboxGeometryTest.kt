package com.green.note.ui
import org.junit.Assert.*
import org.junit.Test
class ReviewCheckboxGeometryTest {
    @Test fun originalBoxShrinksBeforeCheckStrokeAppears(){
        assertEquals(18f,ReviewCheckboxGeometry.edge(0f),0f)
        assertEquals(16f,ReviewCheckboxGeometry.edge(.5f),0f)
        assertEquals(18f,ReviewCheckboxGeometry.edge(1f),0f)
        assertEquals(0f,ReviewCheckboxGeometry.check(.5f),0f)
        assertEquals(.5f,ReviewCheckboxGeometry.check(.75f),0f)
        assertEquals(1f,ReviewCheckboxGeometry.check(1f),0f)
    }
}
