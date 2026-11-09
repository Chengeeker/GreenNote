package com.green.note.ui

import androidx.compose.foundation.MutatePriority
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.ScrollScope
import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.lazy.layout.LazyLayout
import androidx.compose.foundation.lazy.layout.LazyLayoutItemProvider
import androidx.compose.foundation.lazy.layout.LazyLayoutMeasurePolicy
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.ScrollAxisRange
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.scrollBy
import androidx.compose.ui.semantics.scrollToIndex
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.verticalScrollAxisRange
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** Mutable prefix sums keep scrolling O(log n + visible items), including uneven fixed lanes. */
internal class LaneHeights(values: IntArray) {
    private val heights = values.copyOf()
    private val tree = IntArray(values.size + 1)
    val size: Int get() = heights.size
    init { heights.indices.forEach { add(it, heights[it]) } }
    private fun add(index: Int, amount: Int) { var i = index + 1; while (i < tree.size) { tree[i] += amount; i += i and -i } }
    fun update(index: Int, height: Int) { require(height >= 1); val delta = height - heights[index]; heights[index] = height; add(index, delta) }
    fun height(index: Int) = heights[index]
    fun prefix(endExclusive: Int): Int { var i = endExclusive.coerceIn(0, size); var result = 0; while (i > 0) { result += tree[i]; i -= i and -i }; return result }
    val total: Int get() = prefix(size)
    /** First item whose trailing edge is after position, or size beyond the final item. */
    fun indexAt(position: Int): Int {
        if (position < 0) return 0
        var index = 0; var sum = 0; var bit = Integer.highestOneBit(size)
        while (bit != 0) { val next = index + bit; if (next <= size && sum + tree[next] <= position) { index = next; sum += tree[next] }; bit = bit ushr 1 }
        return index
    }
}

@Stable
class FixedLaneListState(initialOffset: Float = 0f) : ScrollableState {
    var offset by mutableFloatStateOf(initialOffset.coerceAtLeast(0f)); private set
    var maximumOffset by mutableFloatStateOf(0f); internal set
    var viewportHeight by mutableIntStateOf(0); internal set
    internal var layoutReady by mutableStateOf(false)
    private val scrolling = ScrollableState { delta ->
        val previous = offset
        offset = (previous + delta).coerceIn(0f, maximumOffset)
        offset - previous
    }
    override val isScrollInProgress: Boolean get() = scrolling.isScrollInProgress
    override val canScrollForward: Boolean get() = offset < maximumOffset
    override val canScrollBackward: Boolean get() = offset > 0f
    override suspend fun scroll(scrollPriority: MutatePriority, block: suspend ScrollScope.() -> Unit) = scrolling.scroll(scrollPriority, block)
    override fun dispatchRawDelta(delta: Float): Float = scrolling.dispatchRawDelta(delta)
    suspend fun scrollTo(offset: Float) = scroll { scrollBy(offset - this@FixedLaneListState.offset) }
    internal fun applyMeasure(value: Float, maximum: Float, viewport: Int) {
        maximumOffset = maximum; viewportHeight = viewport; offset = value.coerceIn(0f, maximum); layoutReady = true
    }
    companion object { val Saver = Saver<FixedLaneListState, Float>(save = { it.offset }, restore = { FixedLaneListState(it) }) }
}

@Composable
fun rememberFixedLaneListState(): FixedLaneListState = rememberSaveable(saver = FixedLaneListState.Saver) { FixedLaneListState() }

private data class LaneEntry(val key: String, val providerIndex: Int)
private class LaneModel(val entries: List<LaneEntry>, val heights: LaneHeights)
private data class FixedLaneEnvironment(val contentWidth: Int, val width: Int, val spacing: Int, val density: Float, val fontScale: Float, val revision: Any?)
private class FixedLaneMeasurements {
    private var environment: FixedLaneEnvironment? = null
    private var source: List<List<String>>? = null
    private val measured = HashMap<String, Int>()
    var lanes: List<LaneModel> = emptyList(); private set
    var headerHeight: Int? = null
    var footerHeight: Int? = null
    fun prepare(keys: List<List<String>>, next: FixedLaneEnvironment, estimate: (String, Int) -> Int): Boolean {
        if (environment != next) { measured.clear(); headerHeight = null; footerHeight = null; source = null; environment = next }
        if (source === keys) return false
        var index = 1
        val present = HashSet<String>()
        lanes = keys.map { lane ->
            val entries = lane.map { key -> require(present.add(key)) { "FixedLaneList item keys must be unique" }; LaneEntry(key, index++) }
            LaneModel(entries, LaneHeights(IntArray(entries.size) { i -> (measured[entries[i].key] ?: estimate(entries[i].key, next.width).coerceAtLeast(1)) + next.spacing }))
        }
        measured.keys.retainAll(present); source = keys; return true
    }
    fun record(lane: LaneModel, index: Int, height: Int, spacing: Int) { measured[lane.entries[index].key] = height.coerceAtLeast(1); lane.heights.update(index, height.coerceAtLeast(1) + spacing) }
}

/**
 * Each key remains in its supplied lane. Only visible cards plus a bounded 256dp buffer are composed;
 * offscreen geometry uses indexed measured heights or caller estimates, never image-driven relaning.
 * Supply dataRevision when same-key content is replaced; append-only pagination retains measurements.
 */
@Composable
fun FixedLaneList(
    lanes: List<List<String>>,
    estimatedHeight: (String, Int) -> Int,
    header: @Composable () -> Unit,
    footer: @Composable () -> Unit,
    itemContent: @Composable (String) -> Unit,
    onNearEnd: () -> Unit,
    modifier: Modifier = Modifier,
    state: FixedLaneListState = rememberFixedLaneListState(),
    horizontalSpacing: Dp = 8.dp,
    verticalSpacing: Dp = 8.dp,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    dataRevision: Any? = null,
) {
    require(lanes.isNotEmpty()) { "At least one fixed lane is required" }
    val density = LocalDensity.current; val direction = LocalLayoutDirection.current
    val measurements = remember { FixedLaneMeasurements() }
    val scope = rememberCoroutineScope()
    // Immutable provider preserves item identity; the slots read current lambdas without retaining old rows.
    val currentHeader by rememberUpdatedState(header); val currentFooter by rememberUpdatedState(footer)
    val currentItem by rememberUpdatedState(itemContent); val currentNearEnd by rememberUpdatedState(onNearEnd)
    val stableLanes = remember(lanes) { lanes.map { it.toList() } }
    val keys = remember(stableLanes) { stableLanes.flatten() }
    val provider = remember(keys) { object : LazyLayoutItemProvider {
        override val itemCount = keys.size + 2
        override fun getKey(index: Int): Any = when (index) { 0 -> "fixed:header"; itemCount - 1 -> "fixed:footer"; else -> "fixed:item:" + keys[index - 1] }
        private val indices = (0 until itemCount).associateBy { getKey(it) }
        override fun getIndex(key: Any): Int = indices[key] ?: -1
        override fun getContentType(index: Int): Any = when (index) { 0 -> "header"; itemCount - 1 -> "footer"; else -> "card" }
        @Composable override fun Item(index: Int, key: Any) {
            when (index) {
                0 -> Column { currentHeader() }
                itemCount - 1 -> Box { currentFooter() }
                else -> Box { currentItem(keys[index - 1]) }
            }
        }
    } }
    ReviewScrollActivity(state)
    LaunchedEffect(state, keys.size, dataRevision) {
        snapshotFlow { state.layoutReady && state.viewportHeight > 0 && state.maximumOffset - state.offset <= state.viewportHeight * .75f }
            .distinctUntilChanged().filter { it }.collect { currentNearEnd() }
    }
    LazyLayout(itemProvider = { provider }, modifier = modifier.clipToBounds()
        .semantics {
            collectionInfo = CollectionInfo(-1, lanes.size)
            verticalScrollAxisRange = ScrollAxisRange({ state.offset }, { state.maximumOffset }, reverseScrolling = false)
            scrollBy { _, y ->
                scope.launch { state.scroll { scrollBy(y) } }
                true
            }
            scrollToIndex { index ->
                if (index !in 0 until provider.itemCount) false else {
                    val target = when (index) {
                        0 -> 0f
                        provider.itemCount - 1 -> state.maximumOffset
                        else -> {
                            val lane = measurements.lanes.firstOrNull { row -> row.entries.any { it.providerIndex == index } }
                            val row = lane?.entries?.indexOfFirst { it.providerIndex == index } ?: -1
                            with(density) { contentPadding.calculateTopPadding().toPx() } + (measurements.headerHeight ?: 0) +
                                (if (lane != null && row >= 0) lane.heights.prefix(row) else 0)
                        }
                    }
                    scope.launch { state.scrollTo(target) }; true
                }
            }
        }
        .scrollable(state, Orientation.Vertical, reverseDirection = true),
        measurePolicy = LazyLayoutMeasurePolicy { constraints ->
            require(constraints.hasBoundedHeight && constraints.hasBoundedWidth) { "FixedLaneList requires a bounded viewport" }
            val width = constraints.maxWidth; val viewport = constraints.maxHeight
            val start = contentPadding.calculateStartPadding(direction).roundToPx(); val end = contentPadding.calculateEndPadding(direction).roundToPx()
            val top = contentPadding.calculateTopPadding().roundToPx(); val bottom = contentPadding.calculateBottomPadding().roundToPx()
            val gap = horizontalSpacing.roundToPx().coerceAtLeast(0); val verticalGap = verticalSpacing.roundToPx().coerceAtLeast(0)
            val contentWidth = (width - start - end).coerceAtLeast(1)
            val laneWidth = ((contentWidth - (lanes.size - 1) * gap) / lanes.size).coerceAtLeast(1)
            val priorBodyTop = top + (measurements.headerHeight ?: 0)
            val priorLane = measurements.lanes.firstOrNull { it.heights.indexAt((state.offset - priorBodyTop).toInt()) < it.entries.size }
            val priorIndex = priorLane?.heights?.indexAt((state.offset - priorBodyTop).toInt()) ?: 0
            val priorKey = priorLane?.entries?.getOrNull(priorIndex)?.key
            val priorAnchorTop = priorBodyTop + (priorLane?.heights?.prefix(priorIndex) ?: 0)
            val rebuilt = measurements.prepare(stableLanes, FixedLaneEnvironment(contentWidth, laneWidth, verticalGap, density.density, density.fontScale, dataRevision), estimatedHeight)
            val positions = ArrayList<Triple<Placeable, Int, Int>>()
            val oldOffset = state.offset
            var scroll = oldOffset
            val buffer = minOf(viewport / 2, 256.dp.roundToPx())
            // Header/footer have their own cache and are not kept composed after leaving the viewport.
            var headerPlaceable: Placeable? = null
            val oldHeader = measurements.headerHeight ?: 0
            if (measurements.headerHeight == null || top + oldHeader >= scroll - buffer) {
                headerPlaceable = compose(0).single().measure(Constraints.fixedWidth(width))
                measurements.headerHeight = headerPlaceable.height
                if (scroll > top + oldHeader && oldHeader > 0) scroll += headerPlaceable.height - oldHeader
            }
            val headerHeight = measurements.headerHeight ?: 0
            val bodyTop = top + headerHeight
            if (rebuilt && priorKey != null && oldOffset > priorBodyTop) {
                measurements.lanes.forEach { lane ->
                    val index = lane.entries.indexOfFirst { it.key == priorKey }
                    if (index >= 0) scroll = bodyTop + lane.heights.prefix(index) + (oldOffset - priorAnchorTop)
                }
            }
            // Keep a visible card anchored if an asynchronous height change affects earlier cards.
            val anchorLane = measurements.lanes.firstOrNull { lane -> lane.heights.indexAt((scroll - bodyTop).toInt()) < lane.entries.size }
            val anchorIndex = anchorLane?.heights?.indexAt((scroll - bodyTop).toInt()) ?: 0
            val anchorBefore = anchorLane?.heights?.prefix(anchorIndex) ?: 0
            val measuredThisPass = HashMap<Int, Placeable>()
            fun measureCard(lane: LaneModel, index: Int): Placeable {
                val item = lane.entries[index]
                return measuredThisPass.getOrPut(item.providerIndex) {
                    compose(item.providerIndex).single().measure(Constraints.fixedWidth(laneWidth)).also { measurements.record(lane, index, it.height, verticalGap) }
                }
            }
            var appliedAnchorDelta = 0
            var footerPlaceable: Placeable? = null
            fun footerPosition(): Int = bodyTop + (measurements.lanes.maxOfOrNull { it.heights.total } ?: 0).let { if (it > 0) it - verticalGap else 0 }
            var maximum = 0f
            // Measure, correct the anchor and clamp to the actual trailing edge before placement.
            // Changed image heights can expose more rows; every key is measured at most once here.
            for (pass in 0 until 4) {
                val windowStart = scroll
                measurements.lanes.forEach { lane ->
                    var index = lane.heights.indexAt((scroll - bodyTop - buffer).toInt())
                    while (index < lane.entries.size && bodyTop + lane.heights.prefix(index) < scroll + viewport + buffer) { measureCard(lane, index); index++ }
                }
                if (anchorLane != null) {
                    val delta = anchorLane.heights.prefix(anchorIndex) - anchorBefore
                    scroll += delta - appliedAnchorDelta; appliedAnchorDelta = delta
                }
                val footerTop = footerPosition()
                if (footerPlaceable == null && footerTop <= scroll + viewport + buffer && footerTop + (measurements.footerHeight ?: viewport) >= scroll - buffer) {
                    footerPlaceable = compose(provider.itemCount - 1).single().measure(Constraints.fixedWidth(width))
                    measurements.footerHeight = footerPlaceable!!.height
                }
                maximum = (footerTop + (measurements.footerHeight ?: 0) + bottom - viewport).coerceAtLeast(0).toFloat()
                scroll = scroll.coerceIn(0f, maximum)
                if (scroll == windowStart) break
            }
            if (headerPlaceable == null && top + headerHeight >= scroll - buffer) {
                // This can occur when dataset shrinkage clamps a far-away offset back to the top.
                headerPlaceable = compose(0).single().measure(Constraints.fixedWidth(width))
                measurements.headerHeight = headerPlaceable.height
            }
            // Writes only layout metadata; paging is dispatched from the snapshotFlow above.
            Snapshot.withoutReadObservation { state.applyMeasure(scroll, maximum, viewport) }
            headerPlaceable?.let { positions += Triple(it, 0, top) }
            measurements.lanes.forEachIndexed { laneIndex, lane ->
                var index = lane.heights.indexAt((scroll - bodyTop - buffer).toInt())
                while (index < lane.entries.size && bodyTop + lane.heights.prefix(index) < scroll + viewport + buffer) {
                    measuredThisPass[lane.entries[index].providerIndex]?.let { item -> positions += Triple(item, start + laneIndex * (laneWidth + gap), bodyTop + lane.heights.prefix(index)) }; index++
                }
            }
            footerPlaceable?.let { positions += Triple(it, 0, footerPosition()) }
            layout(width, viewport) { positions.forEach { (item, x, y) -> item.placeRelative(x, (y - scroll).roundToInt()) } }
        })
}
