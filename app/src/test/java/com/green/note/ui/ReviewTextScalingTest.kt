package com.green.note.ui

import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class ReviewTextScalingTest {
    @Test
    fun scalesSizesButRetainsLogicalSpacingAndAnnotations() {
        val listener = LinkInteractionListener { }
        val link = LinkAnnotation.Url("https://example.test/item", linkInteractionListener = listener)
        val original = buildAnnotatedString {
            append("38sp link")
            addStyle(SpanStyle(fontSize = 38.sp, letterSpacing = 2.sp), 0, 4)
            addStyle(ParagraphStyle(lineHeight = 44.sp), 0, length)
            addLink(link, 5, length)
            addStringAnnotation("source", "retained", 1, 6)
        }
        val scaled = linearAnnotatedText(original, 1.2f)
        assertEquals(original.text, scaled.text)
        assertEquals(45.6f, scaled.spanStyles.single().item.fontSize.value, .001f)
        assertEquals(2.sp, scaled.spanStyles.single().item.letterSpacing)
        assertEquals(52.8f, scaled.paragraphStyles.single().item.lineHeight.value, .001f)
        val actualLink = scaled.getLinkAnnotations(0, scaled.length).single()
        assertSame(link, actualLink.item)
        assertSame(listener, actualLink.item.linkInteractionListener)
        assertEquals(5, actualLink.start)
        assertEquals(original.getStringAnnotations("source", 0, original.length),
            scaled.getStringAnnotations("source", 0, scaled.length))
        assertSame(original, linearAnnotatedText(original, 1f))
    }

    @Test
    fun retainsEmHeightAndFastPathObjects() {
        val style = TextStyle(fontSize = 38.sp, lineHeight = 1.1.em, letterSpacing = 1.sp)
        val enlarged = linearTextStyle(style, 1.2f)
        assertEquals(45.6f, enlarged.fontSize.value, .001f)
        assertEquals(1.1.em, enlarged.lineHeight)
        assertEquals(1.sp, enlarged.letterSpacing)
        assertSame(style, linearTextStyle(style, 1f))
        assertEquals(32.3f, linearTextStyle(style, .85f).fontSize.value, .001f)
    }
}
