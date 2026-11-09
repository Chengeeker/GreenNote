package com.green.note.ui

import org.junit.Assert.assertFalse
import org.junit.Test

class GlassShaderCompatibilityTest {
    @Test fun gles100DirectivesDoNotUseDesktopLineContinuations() {
        // The device Mali compiler rejects these even when the desktop driver accepts them.
        listOf(BaselineGlassShaders.geometry, BaselineGlassShaders.render).forEach { shader ->
            assertFalse(shader.lineSequence().any { it.trimStart().startsWith("#") && it.trimEnd().endsWith("\\") })
        }
    }
}
