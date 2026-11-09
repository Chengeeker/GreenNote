package com.green.note.ui

import android.graphics.PorterDuff
import android.graphics.RectF
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.viewinterop.AndroidView
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import kotlin.math.max

/** Static Gaussian image blur using the same ES 2.0 path on API 24 and later.
 * A URL/size change submits one producer frame; scrolling does not upload or blur again.
 */
@Composable
fun BlurredImage(url:String,headers:Map<String,String>,cacheScope:String,modifier:Modifier=Modifier,sigma:Float=22f,opacity:Float=.13f) {
    val context=LocalContext.current;val density=LocalDensity.current.density;val resources=LocalResources.current
    var size by remember { mutableStateOf(IntSize.Zero) }
    var target by remember {mutableStateOf<GlassCaptureTarget?>(null)}
    LaunchedEffect(url,headers,cacheScope,size,target,opacity,density,resources) {
        val output=target ?: return@LaunchedEffect
        if(size.width<=0 || size.height<=0 || output.closed)return@LaunchedEffect
        val normalized = com.green.note.network.normalizeNetworkImageUrl(url)
        if (normalized.isEmpty()) return@LaunchedEffect
        val result=context.imageLoader.execute(ImageRequest.Builder(context).data(normalized).size(900).crossfade(false)
            .memoryCacheKey("$cacheScope:$normalized:ranking-blur").diskCacheKey("$cacheScope|$normalized")
            .apply{headers.forEach{(name,value)->addHeader(name,value)};if(!normalized.substringBefore('?').endsWith(".gif",true))addHeader("Accept","image/jpeg,image/*;q=.8")}.build()) as? SuccessResult ?: return@LaunchedEffect
        if(output.closed || !output.surface.isValid)return@LaunchedEffect
        output.texture.setDefaultBufferSize(size.width,size.height)
        output.frame=BackdropFrame(size.width,size.height,Offset.Zero)
        val canvas=output.surface.lockHardwareCanvas()
        try {
            canvas.drawColor(android.graphics.Color.TRANSPARENT,PorterDuff.Mode.CLEAR)
            val drawable=(result.drawable.constantState?.newDrawable(resources) ?: result.drawable).mutate()
            val scale=max(size.width.toFloat()/drawable.intrinsicWidth.coerceAtLeast(1),size.height.toFloat()/drawable.intrinsicHeight.coerceAtLeast(1))
            val w=drawable.intrinsicWidth*scale;val h=drawable.intrinsicHeight*scale
            drawable.setBounds(((size.width-w)/2).toInt(),((size.height-h)/2).toInt(),((size.width+w)/2).toInt(),((size.height+h)/2).toInt())
            val alpha=drawable.alpha;drawable.alpha=(opacity*255).toInt();drawable.draw(canvas);drawable.alpha=alpha
        }finally{output.surface.unlockCanvasAndPost(canvas)}
    }
    AndroidView(factory={GlassTextureView(it).apply{onCaptureTarget={target=it}}},modifier=modifier.onSizeChanged{size=it},update={view->
        if(size.width>0&&size.height>0)view.submit(GlassDrawRequest(Offset.Zero,size.width,size.height,density,RectF(0f,0f,size.width.toFloat(),size.height.toFloat()),0f,GlassSurfaceStyle(0,blur=sigma,blurOnly=true)))
    })
}
