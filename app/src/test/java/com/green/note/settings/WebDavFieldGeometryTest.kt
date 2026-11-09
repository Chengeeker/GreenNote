package com.green.note.settings
import org.junit.Assert.*
import org.junit.Test
class WebDavFieldGeometryTest {
    @org.junit.Test fun passwordFieldUsesPasswordImeWithoutAutocorrect() {
        val secret=webDavKeyboardOptions(true)
        org.junit.Assert.assertEquals(androidx.compose.ui.text.input.KeyboardType.Password,secret.keyboardType)
        org.junit.Assert.assertEquals(false,secret.autoCorrectEnabled)
        org.junit.Assert.assertEquals(androidx.compose.ui.text.input.KeyboardType.Text,webDavKeyboardOptions(false).keyboardType)
    }
    @Test fun denseOutlineKeepsOriginalPrefixAndLabelPositions(){
        assertEquals(48f,WebDavFieldGeometry.containerHeight(24f),0f)
        assertEquals(72f,WebDavFieldGeometry.containerHeight(48f),0f)
        assertEquals(52f,WebDavFieldGeometry.labelX(0f),0f)
        assertEquals(16f,WebDavFieldGeometry.labelX(1f),0f)
        assertEquals(.75f,WebDavFieldGeometry.labelScale(1f),0f)
        assertEquals(38f,WebDavFieldGeometry.gapWidth(40f,1f),0f)
    }
}
