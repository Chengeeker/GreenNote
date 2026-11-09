package com.green.note.content

import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.LayoutIdParentData
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasurePolicy
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import kotlin.math.roundToInt

/** The underline field is also measured intrinsically by Flutter-style dialogs. */
internal class CommunityFieldMeasurePolicy(
    private val floating: Float,
    private val floatingHeight: Int,
    private val padding: Int,
    private val minimumHeight: Int,
    private val iconGap: Int,
) : MeasurePolicy {
    private val labelScale get() = 1f - .25f * floating
    private fun finite(value: Int) = value.takeIf { it in 0 until Constraints.Infinity } ?: 0
    private fun sum(vararg values: Int) = values.sumOf { finite(it).toLong() }.coerceAtMost(262142L).toInt()
    private fun List<IntrinsicMeasurable>.slot(id: String) = firstOrNull { (it.parentData as? LayoutIdParentData)?.layoutId == id }
    private fun naturalWidth(children: List<IntrinsicMeasurable>, height: Int, minimum: Boolean): Int {
        fun IntrinsicMeasurable.width() = finite(if (minimum) minIntrinsicWidth(height) else maxIntrinsicWidth(height))
        val prefix = children.slot("prefix")
        val content = maxOf(children.slot("input")?.width() ?: 0, children.slot("hint")?.width() ?: 0,
            ((children.slot("label")?.width() ?: 0) * labelScale).roundToInt())
        return sum(prefix?.width() ?: 0, if (prefix == null) 0 else iconGap, content, children.slot("suffix")?.width() ?: 0)
    }
    private fun naturalHeight(children: List<IntrinsicMeasurable>, width: Int, minimum: Boolean): Int {
        val prefix = children.slot("prefix")
        val suffix = children.slot("suffix")
        val side = sum(prefix?.maxIntrinsicWidth(Constraints.Infinity) ?: 0, if (prefix == null) 0 else iconGap,
            suffix?.maxIntrinsicWidth(Constraints.Infinity) ?: 0)
        val available = if (width == Constraints.Infinity) width else (width - side).coerceAtLeast(0)
        fun IntrinsicMeasurable.height(atWidth: Int) = finite(if (minimum) minIntrinsicHeight(atWidth) else maxIntrinsicHeight(atWidth))
        val inputHeight = maxOf(children.slot("input")?.height(available) ?: 0, children.slot("hint")?.height(available) ?: 0)
        return maxOf(minimumHeight, sum(floatingHeight, padding, padding, inputHeight),
            prefix?.height(Constraints.Infinity) ?: 0, suffix?.height(Constraints.Infinity) ?: 0)
    }
    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int) = naturalWidth(measurables, height, true)
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int) = naturalWidth(measurables, height, false)
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int) = naturalHeight(measurables, width, true)
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int) = naturalHeight(measurables, width, false)

    override fun MeasureScope.measure(measurables: List<Measurable>, constraints: Constraints): androidx.compose.ui.layout.MeasureResult {
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth
            else constraints.constrainWidth(naturalWidth(measurables, Constraints.Infinity, false))
        val prefix = measurables.firstOrNull { it.layoutId == "prefix" }?.measure(Constraints())
        val suffix = measurables.firstOrNull { it.layoutId == "suffix" }?.measure(Constraints())
        val inputX = if (prefix == null) 0 else prefix.width + iconGap
        val available = (width - inputX - (suffix?.width ?: 0)).coerceAtLeast(0)
        val inner = Constraints.fixedWidth(available)
        val input = measurables.first { it.layoutId == "input" }.measure(inner)
        val hint = measurables.firstOrNull { it.layoutId == "hint" }?.measure(inner.copy(minWidth = 0))
        val label = measurables.firstOrNull { it.layoutId == "label" }
            ?.measure(Constraints(maxWidth = (available / labelScale).roundToInt().coerceAtMost(262142)))
        val contentHeight = sum(floatingHeight, padding, padding, maxOf(input.height, hint?.height ?: 0))
        val height = constraints.constrainHeight(maxOf(minimumHeight, contentHeight, prefix?.height ?: 0, suffix?.height ?: 0))
        val inputY = padding + floatingHeight + (height - contentHeight).coerceAtLeast(0) / 2
        return layout(width, height) {
            prefix?.placeRelative(0, (height - prefix.height) / 2)
            suffix?.placeRelative(width - suffix.width, (height - suffix.height) / 2)
            input.placeRelative(inputX, inputY)
            hint?.placeRelative(inputX, inputY)
            label?.let { val inlineY = (height - it.height) / 2f; it.placeRelative(inputX, (inlineY + (padding - inlineY) * floating).roundToInt()) }
        }
    }
}
