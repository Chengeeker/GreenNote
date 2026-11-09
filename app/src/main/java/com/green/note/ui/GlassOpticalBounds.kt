package com.green.note.ui

import kotlin.math.round

/** Optical coordinates must follow the shape, not the cropped render-target centre. */
internal data class GlassOpticalBounds(val left:Float,val top:Float,val width:Float,val height:Float) {
    fun normalized(x:Float,y:Float)=((x-left)/width) to ((y-top)/height)
    val maximumRefractionReach:Float get()=minOf(width,height)*.5f
    companion object {
        fun from(left:Float,top:Float,right:Float,bottom:Float,density:Float,scale:Pair<Float,Float> = 1f to 1f):GlassOpticalBounds {
            // LiquidGlassRenderObject._buildGeometryMatte: pixel snap, then inflate(2).
            val horizontal=2*density*scale.first;val vertical=2*density*scale.second
            val x=round(left)-horizontal;val y=round(top)-vertical
            return GlassOpticalBounds(x,y,(round(right)+horizontal-x).coerceAtLeast(1f),(round(bottom)+vertical-y).coerceAtLeast(1f))
        }
    }
}
