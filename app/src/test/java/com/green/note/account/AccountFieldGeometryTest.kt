package com.green.note.account

import org.junit.Assert.assertEquals
import org.junit.Test

/** Fixtures from Flutter InputDecorator's non-dense, unfilled M3 layout. */
class AccountFieldGeometryTest {
    @Test fun outlinedBorderDoesNotReserveComposeExternalFloatingLabelSpace() {
        assertEquals(56f, AccountFieldGeometry.height(24f, true, 0f), 0f)
        assertEquals(104f, AccountFieldGeometry.height(72f, true, 0f), 0f) // device identifier: three lines
        assertEquals(68f, AccountFieldGeometry.height(36f, true, 0f), 0f) // 1.5x text
    }
    @Test fun prefixSlotCollapsesToOriginalFloatingLabelInset() {
        assertEquals(16f, AccountFieldGeometry.inputStart(false, true), 0f)
        assertEquals(52f, AccountFieldGeometry.inputStart(true, true), 0f)
        assertEquals(52f, AccountFieldGeometry.labelStart(0f, true, true), 0f)
        assertEquals(34f, AccountFieldGeometry.labelStart(.5f, true, true), 0f)
        assertEquals(16f, AccountFieldGeometry.labelStart(1f, true, true), 0f)
    }
    @Test fun bioUnderlineReservesScaledLabelHeightWithoutHorizontalInset() {
        assertEquals(152f, AccountFieldGeometry.height(120f, false, 16f), 0f)
        assertEquals(220f, AccountFieldGeometry.height(180f, false, 24f), 0f)
        assertEquals(0f, AccountFieldGeometry.inputStart(false, false), 0f)
    }
}
