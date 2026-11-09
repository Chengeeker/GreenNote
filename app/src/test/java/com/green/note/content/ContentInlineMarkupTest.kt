package com.green.note.content

import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import org.junit.Assert.assertEquals
import org.junit.Test

class ContentInlineMarkupTest {
    @Test fun inlineStylesRemoveDelimitersAndKeepLineBreaks() {
        val parsed = parseContentText("正文**加粗**、__粗体__、*斜体*、~~划掉~~\n`a_b`")
        assertEquals("正文加粗、粗体、斜体、划掉\na_b", parsed.plain)
        assertEquals(listOf("加粗", "粗体", "斜体", "划掉", "a_b"), parsed.styles.map { parsed.plain.substring(it.start, it.end) })
        assertEquals(FontWeight.Bold, parsed.styles[0].item.fontWeight)
        assertEquals(FontWeight.Bold, parsed.styles[1].item.fontWeight)
        assertEquals(FontStyle.Italic, parsed.styles[2].item.fontStyle)
        assertEquals(TextDecoration.LineThrough, parsed.styles[3].item.textDecoration)
        assertEquals(FontFamily.Monospace, parsed.styles[4].item.fontFamily)
    }

    @Test fun unclosedMarkersEscapesAndUnderscoresInUrlsStayLiteral() {
        val parsed = parseContentText("\\* **未闭合* https://example.test/__name__ snake_case")
        assertEquals("* **未闭合* https://example.test/__name__ snake_case", parsed.plain)
        assertEquals(emptyList<Any>(), parsed.styles)
    }

    @Test fun formattingBeforeAndInsideLinkUpdatesItsOffsets() {
        val parsed = renderInlineMarkup(ParsedContentText("**粗体** __链接__", listOf(Triple(7, 13, "/t/test"))))
        assertEquals("粗体 链接", parsed.plain)
        assertEquals(listOf(Triple(3, 5, "/t/test")), parsed.anchors)
    }
}
