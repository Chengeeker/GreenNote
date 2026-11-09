package com.green.note.account

import androidx.compose.ui.layout.*
import androidx.compose.ui.unit.*
import kotlin.math.max

/** InputDecorator's content and icon slots. Intrinsic queries must never execute
 * actual measurement: dialog IntrinsicSize.Min supplies an infinite width. */
internal class AccountFieldMeasurePolicy(
    private val leading: Boolean,
    private val trailing: Boolean,
    private val outlined: Boolean,
    private val labelWidth: Int,
    private val floatingHeight: Float,
) : MeasurePolicy {
    private fun Density.left() = AccountFieldGeometry.inputStart(leading, outlined).dp.roundToPx()
    private fun Density.right() = (if (trailing) 52.dp else if (outlined) 16.dp else 0.dp).roundToPx()
    private fun Density.vertical() = (if (outlined) 32f else 16f + floatingHeight).dp.roundToPx()
    private fun available(value: Int, padding: Int) =
        if (value == Constraints.Infinity) value else (value - padding).coerceAtLeast(0)
    private fun sum(a: Int, b: Int) = (a.toLong() + b).coerceIn(0, (Constraints.Infinity - 1).toLong()).toInt()
    private fun IntrinsicMeasureScope.naturalWidth(children: List<IntrinsicMeasurable>, height: Int, minimum: Boolean): Int {
        val inputHeight = available(height, vertical())
        val text = if (minimum) children[0].minIntrinsicWidth(inputHeight) else children[0].maxIntrinsicWidth(inputHeight)
        return sum(max(text, labelWidth), left() + right())
    }
    private fun IntrinsicMeasureScope.naturalHeight(children: List<IntrinsicMeasurable>, width: Int, minimum: Boolean): Int {
        val inner = available(width, left() + right())
        val text = if (minimum) children[0].minIntrinsicHeight(inner) else children[0].maxIntrinsicHeight(inner)
        return max(48.dp.roundToPx(), sum(text, vertical()))
    }
    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int) = naturalWidth(measurables, height, true)
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int) = naturalWidth(measurables, height, false)
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int) = naturalHeight(measurables, width, true)
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int) = naturalHeight(measurables, width, false)

    override fun MeasureScope.measure(measurables: List<Measurable>, constraints: Constraints): MeasureResult {
        val sides = left() + right()
        // An actually unbounded parent gets the input's natural width, not an
        // Infinity-minus-padding fixed constraint or a global fixed field width.
        val innerMax = available(constraints.maxWidth, sides)
        val innerMin = if (constraints.hasBoundedWidth) innerMax
            else max(available(constraints.minWidth, sides), labelWidth)
        val input = measurables[0].measure(Constraints(
            minWidth = innerMin, maxWidth = innerMax,
            maxHeight = available(constraints.maxHeight, vertical()),
        ))
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth
            else constraints.constrainWidth(sum(max(input.width, labelWidth), sides))
        val height = constraints.constrainHeight(max(48.dp.roundToPx(), sum(input.height, vertical())))
        val slot = 48.dp.roundToPx()
        val iconWidth = slot.coerceAtMost(width)
        val iconHeight = slot.coerceAtMost(height)
        val prefix = measurables[1].measure(Constraints.fixed(if (leading) iconWidth else 0, if (leading) iconHeight else 0))
        val suffix = measurables[2].measure(Constraints.fixed(if (trailing) iconWidth else 0, if (trailing) iconHeight else 0))
        val inputX = left().coerceAtMost((width - input.width).coerceAtLeast(0))
        val desiredY = if (outlined) (height - input.height) / 2 else (8f + floatingHeight).dp.roundToPx()
        val inputY = desiredY.coerceIn(0, (height - input.height).coerceAtLeast(0))
        return layout(width, height) {
            input.placeRelative(inputX, inputY)
            prefix.placeRelative(0, (height - prefix.height) / 2)
            suffix.placeRelative(width - suffix.width, (height - suffix.height) / 2)
        }
    }
}
