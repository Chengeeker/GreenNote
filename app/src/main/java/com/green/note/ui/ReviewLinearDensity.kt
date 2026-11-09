package com.green.note.ui

import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Matches Flutter's explicit TextScaler.linear instead of Android's nonlinear large-font curve. */
internal data class ReviewLinearDensity(
    override val density: Float,
    override val fontScale: Float,
) : Density {
    init {
        require(density.isFinite() && density > 0f)
        require(fontScale.isFinite() && fontScale > 0f)
    }

    override fun TextUnit.toDp(): Dp {
        check(type == TextUnitType.Sp) { "Only Sp can convert to Dp" }
        return (value * fontScale).dp
    }

    override fun Dp.toSp(): TextUnit = (value / fontScale).sp
}
