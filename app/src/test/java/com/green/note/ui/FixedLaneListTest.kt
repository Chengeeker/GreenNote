package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test
import kotlin.random.Random

class FixedLaneListTest {
    @Test fun heightUpdatesKeepLaneOrderAndExactBoundaryLookup() {
        val heights = LaneHeights(intArrayOf(120, 200, 80))
        assertEquals(0, heights.indexAt(-1))
        assertEquals(0, heights.indexAt(119))
        assertEquals(1, heights.indexAt(120))
        assertEquals(3, heights.indexAt(400))
        heights.update(0, 220)
        assertEquals(220, heights.prefix(1))
        assertEquals(420, heights.prefix(2))
        assertEquals(1, heights.indexAt(320))
        assertEquals(500, heights.total)
    }
    @Test fun indexedGeometryMatchesLinearReferenceAfterManyImageHeightChanges() {
        val random = Random(450)
        val reference = IntArray(3000) { random.nextInt(20, 900) }
        val heights = LaneHeights(reference)
        repeat(300) {
            val index = random.nextInt(reference.size)
            reference[index] = random.nextInt(20, 1200); heights.update(index, reference[index])
            val position = random.nextInt(reference.sum() + 100)
            var sum = 0; var expected = 0
            while (expected < reference.size && sum + reference[expected] <= position) { sum += reference[expected]; expected++ }
            assertEquals(expected, heights.indexAt(position))
            assertEquals(reference.take(expected).sum(), heights.prefix(expected))
            assertEquals(reference.sum(), heights.total)
        }
    }
    @Test fun emptyLaneCanShareViewportWithPopulatedLanes() {
        val empty = LaneHeights(intArrayOf())
        assertEquals(0, empty.total); assertEquals(0, empty.indexAt(100)); assertEquals(0, empty.prefix(0))
    }
}
