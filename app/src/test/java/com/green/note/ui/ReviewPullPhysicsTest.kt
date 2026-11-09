package com.green.note.ui

import org.junit.Assert.*
import org.junit.Test

class ReviewPullPhysicsTest {
    @Test fun initialDragAndTensionUseFlutterViewportFriction() {
        assertEquals(20f,ReviewPullPhysics.drag(0f,20f,800f).offset,0f)
        assertEquals(103.98125f,ReviewPullPhysics.drag(100f,10f,800f).offset,.0001f)
        assertEquals(95.90419f,ReviewPullPhysics.drag(100f,-10f,800f).offset,.0001f)
        assertTrue(ReviewPullPhysics.drag(100f,10f,400f).offset<ReviewPullPhysics.drag(100f,10f,800f).offset)
    }
    @Test fun crossingBackIntoContentReturnsRemainingDragToTheList() {
        val crossing=ReviewPullPhysics.drag(10f,-50f,800f)
        assertEquals(0f,crossing.offset,0f)
        assertEquals(-10f/(.52f*1.05f*1.05f),crossing.consumed,.0001f)
        assertTrue(crossing.consumed>-50f)
    }
    @Test fun reboundPreservesInitialStateAndSettlesWithoutFrameIntegrationDrift() {
        val initial=ReviewPullPhysics.sample(200f,70f,300f,0.0)
        assertEquals(200f,initial.position,.0001f);assertEquals(300f,initial.velocity,.0001f)
        val after=ReviewPullPhysics.sample(200f,70f,300f,1.0)
        assertTrue(after.settled(70f))
        val early=ReviewPullPhysics.sample(200f,70f,300f,.1)
        assertEquals(155.92118f,early.position,.0001f)
        assertEquals(-616.4243f,early.velocity,.0001f)
    }
}
