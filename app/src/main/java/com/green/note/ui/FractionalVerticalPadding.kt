package com.green.note.ui

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.DrawModifier
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.LayoutModifier
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import androidx.compose.ui.unit.offset
import kotlin.math.floor
import kotlin.math.roundToInt

/** Round the pair once; retain the fractional top inset in the canvas, without a graphics layer. */
internal fun Modifier.fractionalVerticalPadding(padding: Dp): Modifier =
    then(FractionalVerticalPadding(padding))

internal data class FractionalVerticalPadding(private val padding: Dp) : LayoutModifier, DrawModifier {
    init { require(padding.value.isFinite() && padding.value >= 0f) }

    private fun total(density: Float): Int = (padding.value * density * 2f).roundToInt().coerceIn(0, 262142)
    private fun finite(value: Int): Int = value.coerceIn(0, 262142)
    private fun available(height: Int, total: Int): Int =
        if (height == Constraints.Infinity) height else (height - total).coerceAtLeast(0)
    private fun sum(height: Int, total: Int): Int = (finite(height).toLong() + total).coerceAtMost(262142).toInt()

    override fun MeasureScope.measure(measurable: Measurable, constraints: Constraints): androidx.compose.ui.layout.MeasureResult {
        val total = total(density)
        val child = measurable.measure(constraints.offset(vertical = -total))
        val top = floor(padding.toPx()).toInt().coerceAtMost(total)
        return layout(constraints.constrainWidth(child.width), constraints.constrainHeight(sum(child.height, total))) {
            child.place(0, top)
        }
    }

    override fun ContentDrawScope.draw() {
        val top = padding.toPx()
        translate(top = top - floor(top)) { this@draw.drawContent() }
    }

    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurable: IntrinsicMeasurable, height: Int): Int =
        finite(measurable.minIntrinsicWidth(available(height, total(density))))
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurable: IntrinsicMeasurable, height: Int): Int =
        finite(measurable.maxIntrinsicWidth(available(height, total(density))))
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurable: IntrinsicMeasurable, width: Int): Int =
        sum(measurable.minIntrinsicHeight(width), total(density))
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurable: IntrinsicMeasurable, width: Int): Int =
        sum(measurable.maxIntrinsicHeight(width), total(density))
}
