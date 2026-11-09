package com.green.note.content

import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasurePolicy
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

/** Badge paints beyond its anchor without participating in the anchor's intrinsic dimensions. */
internal object NotificationBadgeMeasurePolicy : MeasurePolicy {
    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int) = measurables.first().minIntrinsicWidth(height)
    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int) = measurables.first().maxIntrinsicWidth(height)
    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int) = measurables.first().minIntrinsicHeight(width)
    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int) = measurables.first().maxIntrinsicHeight(width)
    override fun MeasureScope.measure(measurables: List<Measurable>, constraints: Constraints): androidx.compose.ui.layout.MeasureResult {
        val child = measurables.first().measure(constraints)
        val badge = measurables.getOrNull(1)?.let { item ->
            val height = maxOf(16.dp.roundToPx(), item.maxIntrinsicHeight(Constraints.Infinity))
            val width = maxOf(height, item.maxIntrinsicWidth(height))
            item.measure(Constraints.fixed(width, height))
        }
        return layout(child.width, child.height) {
            child.place(0, 0)
            badge?.let {
                val position = notificationBadgeOffset(child.width / density, it.height / density, layoutDirection == LayoutDirection.Rtl)
                it.place((position.first * density).toInt(), (position.second * density).toInt())
            }
        }
    }
}
