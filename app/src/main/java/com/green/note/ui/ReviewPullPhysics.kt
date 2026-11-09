package com.green.note.ui

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.sign
import kotlin.math.sqrt

/** EasyRefresh 3.5.1 _ERScrollPhysics and Flutter's normal BouncingScrollPhysics. Units are pixels. */
internal object ReviewPullPhysics {
    data class Drag(val offset:Float,val consumed:Float)
    data class Sample(val position:Float,val velocity:Float) {
        fun settled(target:Float)=abs(position-target)<1f&&abs(velocity)<20f
    }
    fun drag(extent:Float,delta:Float,viewport:Float):Drag {
        if(delta==0f)return Drag(extent,0f)
        if(extent<=0f)return if(delta>0f)Drag(delta,delta)else Drag(0f,0f)
        val magnitude=abs(delta)
        val fraction=(if(delta<0f)extent-magnitude else extent)/viewport.coerceAtLeast(1f)
        val gamma=.52f*(1-fraction)*(1-fraction)
        val toLimit=if(gamma==0f)Float.POSITIVE_INFINITY else extent/gamma
        val movement=if(magnitude<toLimit)magnitude*gamma else extent+magnitude-toLimit
        val next=(extent+sign(delta)*movement).coerceAtLeast(0f)
        return Drag(next,if(delta<0f&&next==0f)-toLimit.coerceAtMost(magnitude)else delta)
    }
    // mass .5, stiffness 100, damping ratio 1.1. Closed form avoids a frame-rate-dependent integrator.
    fun sample(start:Float,target:Float,velocity:Float,seconds:Double):Sample {
        val omega=sqrt(200.0);val zeta=1.1;val root=sqrt(zeta*zeta-1)
        val r1=-omega*(zeta-root);val r2=-omega*(zeta+root)
        val displacement=(start-target).toDouble()
        val c1=(velocity-r2*displacement)/(r1-r2);val c2=displacement-c1
        val first=c1*exp(r1*seconds);val second=c2*exp(r2*seconds)
        return Sample((target+first+second).toFloat(),(r1*first+r2*second).toFloat())
    }
}
