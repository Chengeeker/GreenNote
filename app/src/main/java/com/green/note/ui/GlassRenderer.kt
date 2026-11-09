package com.green.note.ui

import android.content.Context
import android.graphics.*
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.TextureView
import androidx.compose.ui.geometry.Offset
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.*

internal data class GlassSurfaceStyle(
    val color: Int, val thickness: Float = 10f, val refractiveIndex: Float = 1.16f,
    val aberration: Float = .008f, val blur: Float = 1.5f, val light: Float = .25f,
    val saturation: Float = 1f, val rimShade: Float = 0f, val rimLight: Float = 0f,
    val pinch: Float = 0f, val visibility: Float = 1f, val clearBody:Boolean = true,
    val legacyGallery:Boolean = false, val oval:Boolean = false, val blurOnly:Boolean=false,
)
internal data class GlassDrawRequest(
    val origin: Offset, val width: Int, val height: Int, val density: Float,
    val body: RectF, val radius: Float, val style: GlassSurfaceStyle,
    val touch:GlassTouchFrame?=null, val sourceSize:androidx.compose.ui.unit.IntSize?=null, val shapeScale:Pair<Float,Float> = 1f to 1f,
)
internal data class GlassTouchFrame(val position:Offset,val intensity:Float,val radius:Float)

/** One demand-driven GLES context per visible glass control, including Android 7–12. */
internal class GlassTextureView(context: Context) : TextureView(context), TextureView.SurfaceTextureListener {
    @Volatile private var session: RenderSession? = null
    @Volatile private var retained: GlassDrawRequest? = null
    private val mainHandler=Handler(Looper.getMainLooper())
    private val presentation=GlassPresentationState()
    var onCaptureTarget: ((GlassCaptureTarget?) -> Unit)? = null
    var onPresentationReady: ((Boolean) -> Unit)? = null
    private fun notifyPresentation(changed:Boolean) { if(changed)onPresentationReady?.invoke(presentation.ready) }
    init { isOpaque=false;surfaceTextureListener=this }
    fun submit(request:GlassDrawRequest) { retained=request;session?.submit(request) }
    override fun onSurfaceTextureAvailable(surface:SurfaceTexture,width:Int,height:Int) {
        session?.close(releaseSurface=true)
        val next=RenderSession(surface);session=next
        notifyPresentation(presentation.begin(next))
        next.start()
    }
    override fun onSurfaceTextureSizeChanged(surface:SurfaceTexture,width:Int,height:Int) {
        session?.let { notifyPresentation(presentation.begin(it)) }
        retained?.let(::submit)
    }
    override fun onSurfaceTextureUpdated(surface:SurfaceTexture) {
        session?.takeIf { it.canPresent(surface) }?.let { notifyPresentation(presentation.presented(it)) }
    }
    override fun onSurfaceTextureDestroyed(surface:SurfaceTexture):Boolean {
        val previous=session;session=null
        previous?.let { notifyPresentation(presentation.invalidate(it)) }
        previous?.close(releaseSurface=true)
        try { onCaptureTarget?.invoke(null) }
        catch(error:Exception) { Log.e("ComposeGlass","Removing capture target failed",error) }
        // A live/closing GL session releases only after its EGL window is destroyed.
        return previous==null
    }
    private inner class RenderSession(val surface:SurfaceTexture) {
        private val thread=HandlerThread("ComposeGlass").also{it.start()}
        private val handler=Handler(thread.looper)
        private val pending=AtomicReference<GlassDrawRequest?>()
        private val closing=AtomicBoolean(false)
        private val disposed=AtomicBoolean(false)
        private val releaseOutput=AtomicBoolean(false)
        private val outputReleased=AtomicBoolean(false)
        private val closed get()=closing.get()
        @Volatile private var capture:GlassCaptureTarget?=null
        private var renderer:GlassRenderer?=null
        fun canPresent(output:SurfaceTexture)=surface===output&&!closed
        private val draw=object:Runnable {
            override fun run() {
                if(closed)return
                val request=pending.getAndSet(null) ?: return
                guarded("draw") { renderer?.draw(request) }
                if(!closed && pending.get()!=null)handler.post(this)
            }
        }
        private inline fun guarded(stage:String,action:()->Unit) {
            if(closed)return
            try { action() } catch(error:Exception) {
                Log.e("ComposeGlass","Glass $stage failed; releasing the failed surface session",error)
                close()
            }
        }
        fun start() { handler.post {
            guarded("initialization") {
                val next=GlassRenderer(surface,handler,
                    beforeSwap={presentation.startSwap(this)},
                    afterSwap={token->
                        if(token!=null&&presentation.swapped(this,token))mainHandler.post {
                            if(session===this&&!closed)notifyPresentation(true)
                        }
                    }) {
                    guarded("capture frame") {
                        val active = renderer ?: return@guarded
                        active.updateCapture()
                        retained?.let { active.draw(it) }
                        active.captureTarget.captureFinished()
                    }
                }
                renderer=next;capture=next.captureTarget
                if(closed)next.captureTarget.closed=true
                mainHandler.post {
                    if(!closed && session===this) {
                        try { onCaptureTarget?.invoke(next.captureTarget) }
                        catch(error:Exception) { Log.e("ComposeGlass","Publishing capture target failed",error);close() }
                    }
                }
                retained?.let { submit(it) }
            }
        } }
        fun submit(request:GlassDrawRequest) {
            if(closed)return
            val schedule=pending.getAndSet(request)==null
            if(closed)pending.set(null) else if(schedule)handler.post(draw)
        }
        private fun releaseOutputIfOwned() {
            if(releaseOutput.get() && outputReleased.compareAndSet(false,true)) {
                try { surface.release() }
                catch(error:Exception) { Log.e("ComposeGlass","Releasing window texture failed",error) }
            }
        }
        fun close(releaseSurface:Boolean=false) {
            // Failure alone does not transfer TextureView's output texture ownership.
            if(releaseSurface)releaseOutput.set(true)
            if(!closing.compareAndSet(false,true)) {
                if(disposed.get())releaseOutputIfOwned()
                return
            }
            capture?.closed=true;pending.set(null);handler.removeCallbacks(draw)
            // Capture uses the main thread's hardware canvas. Revoke it on that same
            // queue before releasing its producer Surface/SurfaceTexture on the GL thread.
            mainHandler.post {
                notifyPresentation(presentation.invalidate(this))
                try { if(session===this)onCaptureTarget?.invoke(null) }
                catch(error:Exception) { Log.e("ComposeGlass","Revoking capture target failed",error) }
                finally { handler.post {
                    try { renderer?.close() }
                    catch(error:Exception) { Log.e("ComposeGlass","Releasing renderer failed",error) }
                    finally {
                        renderer=null;capture=null;disposed.set(true)
                        try { releaseOutputIfOwned() }
                        finally { thread.quitSafely() }
                    }
                } }
            }
        }
    }

}

internal class GlassRenderer(surface: SurfaceTexture, handler: Handler,
    private val beforeSwap:()->GlassSwapToken?, private val afterSwap:(GlassSwapToken?)->Unit,
    onFrame: () -> Unit) {
    private val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var window: EGLSurface = EGL14.EGL_NO_SURFACE
    private var displayAcquired=false
    private var closed=false
    private val programs=ArrayList<Program>(7)
    private lateinit var geometry: Program
    private lateinit var optical: Program
    private lateinit var copy: Program
    private lateinit var blur: Program
    private lateinit var external: Program
    private lateinit var gallery: Program
    private var capture:GlassCaptureTarget?=null
    private var captureTexture:SurfaceTexture?=null
    val captureTarget:GlassCaptureTarget get()=checkNotNull(capture)
    private val externalTexture = IntArray(1)
    private val transform = FloatArray(16)
    private var captureReady = false
    private val textures = IntArray(12)
    private val framebuffer = IntArray(1)
    private val vertices = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
        put(floatArrayOf(-1f,-1f,1f,-1f,-1f,1f,1f,1f)); position(0)
    }
    private var dimensions = Pair(0,0)
    private var captureRevision = 0
    private var bodyKey: List<Any>? = null
    private var captureKey:List<Any>?=null
    private lateinit var glow:Program
    init {
        try {
        GlassEglDisplay.acquire(display);displayAcquired=true
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        check(EGL14.eglChooseConfig(display, intArrayOf(EGL14.EGL_RED_SIZE,8,EGL14.EGL_GREEN_SIZE,8,EGL14.EGL_BLUE_SIZE,8,EGL14.EGL_ALPHA_SIZE,8,
            EGL14.EGL_RENDERABLE_TYPE,EGL14.EGL_OPENGL_ES2_BIT,EGL14.EGL_SURFACE_TYPE,EGL14.EGL_WINDOW_BIT,EGL14.EGL_NONE),0,configs,0,1,count,0) && count[0]>0)
        context = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION,2,EGL14.EGL_NONE),0)
        check(context!=EGL14.EGL_NO_CONTEXT) { "EGL context creation failed: 0x${EGL14.eglGetError().toString(16)}" }
        window = EGL14.eglCreateWindowSurface(display, configs[0], surface, intArrayOf(EGL14.EGL_NONE),0)
        check(window!=EGL14.EGL_NO_SURFACE) { "EGL window creation failed: 0x${EGL14.eglGetError().toString(16)}" }
        check(EGL14.eglMakeCurrent(display,window,window,context)) { "EGL makeCurrent failed: 0x${EGL14.eglGetError().toString(16)}" }
        geometry = Program(BaselineGlassShaders.geometry,"geometry").also { programs.add(it) }
        optical = Program(BaselineGlassShaders.render,"optical").also { programs.add(it) }
        copy = Program(copyShader,"copy").also { programs.add(it) }
        blur = Program(blurShader,"blur").also { programs.add(it) }
        external = Program(externalShader,"external").also { programs.add(it) }
        gallery = Program(galleryShader,"gallery").also { programs.add(it) }
        glow=Program(glowShader,"glow").also { programs.add(it) }
        GLES20.glGenTextures(1, externalTexture, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, externalTexture[0])
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,GLES20.GL_TEXTURE_MIN_FILTER,GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,GLES20.GL_TEXTURE_MAG_FILTER,GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,GLES20.GL_TEXTURE_WRAP_S,GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,GLES20.GL_TEXTURE_WRAP_T,GLES20.GL_CLAMP_TO_EDGE)
        val texture=SurfaceTexture(externalTexture[0]);captureTexture=texture
        capture=GlassCaptureTarget(texture,android.view.Surface(texture))
        texture.setOnFrameAvailableListener({ onFrame() },handler)
        GLES20.glGenTextures(textures.size,textures,0)
        textures.forEach { texture -> GLES20.glBindTexture(GLES20.GL_TEXTURE_2D,texture)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_MIN_FILTER,GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_MAG_FILTER,GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_WRAP_S,GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_WRAP_T,GLES20.GL_CLAMP_TO_EDGE)
        }
        GLES20.glGenFramebuffers(1,framebuffer,0)
        val error=GLES20.glGetError();check(error==GLES20.GL_NO_ERROR) { "Glass initialization GL error: 0x${error.toString(16)}" }
        } catch(error:Exception) {
            close() // A failed constructor is never assigned to RenderSession.renderer.
            throw error
        }
    }
    fun updateCapture() { captureTarget.texture.updateTexImage();captureTarget.texture.getTransformMatrix(transform);captureReady=true;captureRevision++ }
    fun draw(request: GlassDrawRequest) {
        val frame=captureTarget.frame ?: return
        if(!captureReady)return
        if (request.width <= 0 || request.height <= 0) return
        val w=request.width; val h=request.height
        if (dimensions != w to h) {
            dimensions=w to h
            val indices=if(request.style.blurOnly)listOf(1,2,7,10) else (0..7).toList()+listOf(10, 11)
            for (i in indices) { GLES20.glBindTexture(GLES20.GL_TEXTURE_2D,textures[i]); GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D,0,GLES20.GL_RGBA,w,h,0,GLES20.GL_RGBA,GLES20.GL_UNSIGNED_BYTE,null) }
        }
        GLES20.glViewport(0,0,w,h)
        val nextCaptureKey=listOf(captureRevision,w,h,request.origin,request.density,request.style.blur)
        if(captureKey!=nextCaptureKey) {
        GLES20.glDisable(GLES20.GL_BLEND)
        // SurfaceTexture consumes the producer's hardware canvas without CPU readback.
        target(1);external.use(w,h)
        external.vector("uSourceSize",frame.width.toFloat(),frame.height.toFloat())
        external.vector("uOffset",request.origin.x-frame.origin.x,request.origin.y-frame.origin.y)
        GLES20.glUniformMatrix4fv(external.location("uTransform"),1,false,transform,0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0);GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,externalTexture[0])
        GLES20.glUniform1i(external.location("uExternal"),0);quad(external)
        gaussian(1,2,10,request.style.blur*request.density,w,h)
        captureKey=nextCaptureKey
        }
        val nextBodyKey=listOf(captureRevision,w,h,request.origin,request.body,request.radius,request.style,request.density,request.touch?:false,request.shapeScale)
        if(bodyKey!=nextBodyKey) {
        GLES20.glDisable(GLES20.GL_BLEND)
        if(request.style.blurOnly) {
            target(7);copyImage(10,w,h)
        } else {
        matte(request.body,request.radius,request.style,request.density,w,h,4,request.shapeScale)
        target(7); copyImage(1,w,h)
        GLES20.glEnable(GLES20.GL_BLEND); GLES20.glBlendFunc(GLES20.GL_ONE,GLES20.GL_ONE_MINUS_SRC_ALPHA)
        if(request.style.legacyGallery) {
            gallery.use(w,h);gallery.vector("uRect",request.body.left,request.body.top,request.body.width(),request.body.height())
            gallery.scalar("uWarp",if(request.style.visibility>=1f)1f else 0f)
            gallery.texture("uImage",textures[10],0);gallery.texture("uMask",textures[4],1);quad(gallery)
        } else {
            target(3);GLES20.glDisable(GLES20.GL_BLEND);copyImage(1,w,h)
            GLES20.glEnable(GLES20.GL_BLEND);copyImage(10,w,h,mask=4)
            target(7);optics(3,4,request.style,request.density,w,h,false,request.body,request.touch,request.sourceSize,request.shapeScale)
        }
        }
        bodyKey=nextBodyKey
        }
        if(request.style.blurOnly) {
            target(null);GLES20.glDisable(GLES20.GL_BLEND);copyImage(7,w,h,flip=true)
            val presentation=beforeSwap()
            check(EGL14.eglSwapBuffers(display,window)) { "Blur buffer swap failed" }
            check(GLES20.glGetError()==GLES20.GL_NO_ERROR) { "Blur rendering failed" }
            afterSwap(presentation)
            return
        }
        target(5);GLES20.glDisable(GLES20.GL_BLEND);copyImage(7,w,h)
        request.touch?.takeIf{it.intensity>.001f}?.let { touch->
            target(6);GLES20.glDisable(GLES20.GL_BLEND);glow.use(w,h)
            glow.vector("uTouch",touch.position.x,touch.position.y)
            glow.scalar("uRadius",min(request.body.width(),request.body.height())*1.6f*touch.radius)
            glow.scalar("uAlpha",32f/255*touch.intensity.coerceIn(0f,1f));glow.scalar("uCircleOnly",1f);quad(glow)
            gaussian(6,2,3,16*request.density,w,h)
            target(5);GLES20.glEnable(GLES20.GL_BLEND);GLES20.glBlendFunc(GLES20.GL_ONE,GLES20.GL_ONE)
            glow.use(w,h);glow.scalar("uCircleOnly",0f);glow.texture("uCircle",textures[3],0);glow.texture("uShape",textures[4],1);quad(glow)
            GLES20.glBlendFunc(GLES20.GL_ONE,GLES20.GL_ONE_MINUS_SRC_ALPHA)
        }
        target(null); GLES20.glClearColor(0f,0f,0f,0f); GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        if(request.style.legacyGallery) {
            gaussian(4,2,3,(7*.57735f+.5f)*request.density,w,h)
            target(null);GLES20.glEnable(GLES20.GL_BLEND);copy.use(w,h)
            copy.vector("uSolidColor",0f,0f,0f,.20f*request.style.visibility)
            copyImage(1,w,h,mask=3,flip=true,solid=true,maskY=2*request.density)
            gaussian(4,2,3,(5*.57735f+.5f)*request.density,w,h)
            target(null);GLES20.glEnable(GLES20.GL_BLEND);copy.use(w,h)
            copy.vector("uSolidColor",1f,1f,1f,.08f*request.style.visibility)
            copyImage(1,w,h,mask=3,flip=true,solid=true,maskY=-request.density)
        }
        GLES20.glEnable(GLES20.GL_BLEND); copyImage(5,w,h,mask=4,flip=true)
        val presentation=beforeSwap()
        check(EGL14.eglSwapBuffers(display,window)) { "Glass buffer swap failed" }
        check(GLES20.glGetError()==GLES20.GL_NO_ERROR) { "Glass rendering failed" }
        afterSwap(presentation)
    }
    private fun matte(rect: RectF,radius:Float,style:GlassSurfaceStyle,density:Float,w:Int,h:Int,index:Int,shapeScale:Pair<Float,Float> = 1f to 1f) {
        target(index); GLES20.glDisable(GLES20.GL_BLEND); geometry.use(w,h)
        geometry.vector("uSize",w.toFloat(),h.toFloat()); geometry.scalar("uFlipY",0f)
        geometry.vector("uOpticalProps",1f+(style.refractiveIndex-1)*style.visibility,style.aberration,style.thickness*density/3*style.visibility,0f)
        geometry.vector("uShapeSettings",1f,density); geometry.scalar("uNativeEdge",if(style.rimShade>0)1f else 0f)
        geometry.vector("uShapeScale",shapeScale.first,shapeScale.second)
        GLES20.glUniform1fv(geometry.location("uShapeData[0]"),7,floatArrayOf(if(style.oval)2f else 3f,rect.centerX(),rect.centerY(),rect.width(),rect.height(),radius,radius),0)
        quad(geometry)
    }
    private fun optics(source:Int,mask:Int,style:GlassSurfaceStyle,density:Float,w:Int,h:Int,flip:Boolean,bounds:RectF,touch:GlassTouchFrame?=null,sourceSize:androidx.compose.ui.unit.IntSize?=null,shapeScale:Pair<Float,Float> = 1f to 1f,opacity:Float=1f) {
        optical.use(w,h); optical.scalar("uFlipY",if(flip)1f else 0f)
        optical.vector("uSize",w.toFloat(),h.toFloat())
        optical.vector("uEffectSize",sourceSize?.width?.toFloat()?:w.toFloat(),sourceSize?.height?.toFloat()?:h.toFloat())
        // Original matte includes a two-logical-pixel AA border, independent of the
        // texture that stores it. A moving pill must retain its own optical centre.
        val opticalBounds=GlassOpticalBounds.from(bounds.left,bounds.top,bounds.right,bounds.bottom,density,shapeScale)
        optical.vector("uGeometrySize",opticalBounds.width,opticalBounds.height)
        optical.vector("uGeometryOffset",opticalBounds.left,opticalBounds.top)
        optical.vector("uGlassColor",Color.red(style.color)/255f,Color.green(style.color)/255f,Color.blue(style.color)/255f,Color.alpha(style.color)/255f*style.visibility)
        optical.vector("uOpticalProps",1f+(style.refractiveIndex-1)*style.visibility,style.aberration,style.thickness*density/3*style.visibility,1f)
        optical.vector("uLightConfig",style.light*style.visibility,0f,1+(style.saturation-1)*style.visibility)
        optical.vector("uLightDirection",cos(PI*.75).toFloat(),-sin(PI*.75).toFloat())
        optical.scalar("uWhiten",0f); optical.scalar("uWhitenGated",1f); optical.scalar("uPinchStrength",style.pinch)
        optical.vector("uBackgroundFallback",0f,0f,0f,0f); optical.vector("uCaptureOffset",0f,0f)
        optical.vector("uEdgeConfig",0f,style.visibility,density/3,0f); optical.scalar("uPlatformViewMode",0f); optical.scalar("uBodyMode",if(style.clearBody)1f else 0f)
        optical.vector("uTouchPosition",touch?.position?.x?:w/2f,touch?.position?.y?:h/2f); optical.scalar("uTouchIntensity",touch?.intensity?.coerceIn(0f,1f)?:0f)
        optical.vector("uRimConfig",style.rimShade*style.visibility,style.rimLight*style.visibility,.2f); optical.scalar("uLensModel",0f)
        optical.vector("uFrost",0f,0f,0f,1f); optical.scalar("uBodyShade",0f)
        optical.scalar("uLayerFade",1f-opacity)
        optical.texture("uBackgroundTexture",textures[source],0); optical.texture("uGeometryTexture",textures[mask],1); quad(optical)
    }
    private fun gaussian(source:Int,temp:Int,result:Int,sigma:Float,w:Int,h:Int) {
        GLES20.glDisable(GLES20.GL_BLEND)
        if (sigma<.01f) { target(result); copyImage(source,w,h); return }
        target(temp); blur.use(w,h); blur.vector("uDirection",1f/w,0f); blur.scalar("uSigma",sigma); blur.texture("uImage",textures[source],0); quad(blur)
        target(result); blur.use(w,h); blur.vector("uDirection",0f,1f/h); blur.scalar("uSigma",sigma); blur.texture("uImage",textures[temp],0); quad(blur)
    }
    private fun target(index:Int?) {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER,if(index==null)0 else framebuffer[0])
        if(index!=null) { GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER,GLES20.GL_COLOR_ATTACHMENT0,GLES20.GL_TEXTURE_2D,textures[index],0)
            check(GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)==GLES20.GL_FRAMEBUFFER_COMPLETE) }
    }
    private fun copyImage(index:Int,w:Int,h:Int,mask:Int?=null,flip:Boolean=false,solid:Boolean=false,maskY:Float=0f,inverseMask:Boolean=false,opacity:Float=1f) {
        copy.use(w,h); copy.scalar("uSolid",if(solid)1f else 0f);copy.scalar("uFlipY",if(flip)1f else 0f); copy.vector("uSourceSize",w.toFloat(),h.toFloat()); copy.vector("uOffset",0f,0f)
        copy.scalar("uMasked",if(mask==null)0f else if(inverseMask)-1f else 1f); copy.texture("uImage",textures[index],0)
        copy.vector("uMaskOffset",0f,maskY)
        copy.scalar("uOpacity",opacity)
        // Always bind a valid non-target texture. Even an unmasked draw keeps the
        // sampler active in GLSL; a stale binding to this FBO is an ES feedback loop.
        copy.texture("uMask",textures[mask?:index],1); quad(copy)
    }
    private fun quad(program:Program) {
        val position=GLES20.glGetAttribLocation(program.id,"aPosition")
        vertices.position(0); GLES20.glEnableVertexAttribArray(position); GLES20.glVertexAttribPointer(position,2,GLES20.GL_FLOAT,false,0,vertices)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP,0,4); GLES20.glDisableVertexAttribArray(position)
    }
    fun close() {
        if(closed)return
        closed=true;capture?.closed=true
        fun release(label:String,action:()->Unit) {
            try { action() } catch(error:Exception) { Log.w("ComposeGlass","Failed to release $label",error) }
        }
        release("capture listener") { captureTexture?.setOnFrameAvailableListener(null) }
        release("capture surface") { capture?.surface?.release() }
        release("capture texture") { captureTexture?.release() }
        capture=null;captureTexture=null
        // A lost context cannot delete GL objects explicitly; destroying that context
        // still releases its objects. Never delete ids in another renderer's context.
        var current=false
        if(context!=EGL14.EGL_NO_CONTEXT && window!=EGL14.EGL_NO_SURFACE)release("makeCurrent") {
            current=EGL14.eglMakeCurrent(display,window,window,context)
        }
        if(current) {
            release("external texture") { GLES20.glDeleteTextures(1,externalTexture,0) }
            release("textures") { GLES20.glDeleteTextures(textures.size,textures,0) }
            release("framebuffer") { GLES20.glDeleteFramebuffers(1,framebuffer,0) }
            programs.forEach { program->release("program") { GLES20.glDeleteProgram(program.id) } }
        }
        programs.clear()
        if(displayAcquired) {
            release("current context") { EGL14.eglMakeCurrent(display,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_CONTEXT) }
            if(window!=EGL14.EGL_NO_SURFACE)release("EGL window") { EGL14.eglDestroySurface(display,window) }
            if(context!=EGL14.EGL_NO_CONTEXT)release("EGL context") { EGL14.eglDestroyContext(display,context) }
            window=EGL14.EGL_NO_SURFACE;context=EGL14.EGL_NO_CONTEXT
            release("EGL display") { GlassEglDisplay.release(display) };displayAcquired=false
        }
        release("EGL thread") { EGL14.eglReleaseThread() }
    }
    private class Program(source:String,label:String) {
        val id:Int
        private val locations=HashMap<String,Int>()
        init {
            var vertex=0;var fragment=0;var program=0
            fun compile(kind:Int,code:String):Int {
                val shader=GLES20.glCreateShader(kind)
                check(shader!=0) { "$label shader allocation failed" }
                try {
                    GLES20.glShaderSource(shader,code);GLES20.glCompileShader(shader)
                    val valid=IntArray(1);GLES20.glGetShaderiv(shader,GLES20.GL_COMPILE_STATUS,valid,0)
                    check(valid[0]!=0) { "$label shader: ${GLES20.glGetShaderInfoLog(shader)}" }
                    return shader
                } catch(error:Exception) { GLES20.glDeleteShader(shader);throw error }
            }
            try {
                vertex=compile(GLES20.GL_VERTEX_SHADER,"attribute vec2 aPosition; void main(){gl_Position=vec4(aPosition,0.,1.);}")
                fragment=compile(GLES20.GL_FRAGMENT_SHADER,source)
                program=GLES20.glCreateProgram();check(program!=0) { "$label program allocation failed" }
                GLES20.glAttachShader(program,vertex);GLES20.glAttachShader(program,fragment);GLES20.glLinkProgram(program)
                val valid=IntArray(1);GLES20.glGetProgramiv(program,GLES20.GL_LINK_STATUS,valid,0)
                check(valid[0]!=0) { "$label program: ${GLES20.glGetProgramInfoLog(program)}" }
                id=program
            } catch(error:Exception) {
                if(program!=0)GLES20.glDeleteProgram(program)
                throw error
            } finally {
                if(vertex!=0)GLES20.glDeleteShader(vertex)
                if(fragment!=0)GLES20.glDeleteShader(fragment)
            }
        }
        fun location(name:String)=locations.getOrPut(name){GLES20.glGetUniformLocation(id,name)}
        fun use(w:Int,h:Int) { GLES20.glUseProgram(id); vector("uViewport",w.toFloat(),h.toFloat()) }
        fun scalar(name:String,value:Float)=GLES20.glUniform1f(location(name),value)
        fun vector(name:String,vararg values:Float) { val at=location(name); when(values.size){2->GLES20.glUniform2fv(at,1,values,0);3->GLES20.glUniform3fv(at,1,values,0);4->GLES20.glUniform4fv(at,1,values,0)} }
        fun texture(name:String,texture:Int,unit:Int) { GLES20.glActiveTexture(GLES20.GL_TEXTURE0+unit); GLES20.glBindTexture(GLES20.GL_TEXTURE_2D,texture); GLES20.glUniform1i(location(name),unit) }
    }
    companion object {
        // Same thin spherical-cap ray calculation as shaders/gallery_glass_button.frag.
        internal const val glowShader="""precision highp float;
uniform vec2 uViewport;uniform vec2 uTouch;uniform float uRadius;uniform float uAlpha;
uniform float uCircleOnly;uniform sampler2D uCircle;uniform sampler2D uShape;
void main(){float distance=length(gl_FragCoord.xy-uTouch);
if(uCircleOnly>.5){gl_FragColor=vec4(1.-smoothstep(uRadius-.5,uRadius+.5,distance));return;}
// Flutter MaskFilter blurs the circle coverage, not the radial shader colour.
float alpha=clamp(1.-distance/max(uRadius,.001),0.,1.)*uAlpha;
alpha*=texture2D(uCircle,gl_FragCoord.xy/uViewport).a*texture2D(uShape,gl_FragCoord.xy/uViewport).a;
gl_FragColor=vec4(alpha);}
"""
        internal const val galleryShader="""precision highp float;
uniform vec2 uViewport;uniform vec4 uRect;uniform float uWarp;uniform sampler2D uImage;uniform sampler2D uMask;
void main(){vec2 position=gl_FragCoord.xy-uRect.xy;vec2 radial=position-uRect.zw*.5;
float radius=min(uRect.z,uRect.w)*.5;float r=clamp(length(radial)/radius,0.,.98);
float slope=(1.4/radius)*r/sqrt(max(1.-r*r,.04));float incidence=atan(slope);
float transmission=asin(clamp(sin(incidence)/1.52,0.,.99));float shift=clamp((incidence-transmission)*8.,0.,.45)*smoothstep(.08,.42,r)*uWarp;
vec2 samplePosition=position+radial/max(length(radial),.001)*shift;
vec2 uv=(clamp(samplePosition/uRect.zw,vec2(.001),vec2(.999))*uRect.zw+uRect.xy)/uViewport;
float alpha=texture2D(uMask,gl_FragCoord.xy/uViewport).a;gl_FragColor=texture2D(uImage,uv)*alpha;}
"""
        internal const val externalShader="""#extension GL_OES_EGL_image_external : require
precision highp float;
uniform samplerExternalOES uExternal;uniform mat4 uTransform;uniform vec2 uViewport;uniform vec2 uSourceSize;uniform vec2 uOffset;
void main(){vec2 uv=(gl_FragCoord.xy+uOffset)/uSourceSize;vec2 sampleUV=(uTransform*vec4(uv.x,1.-uv.y,0.,1.)).xy;gl_FragColor=texture2D(uExternal,sampleUV);}
"""
        internal const val copyShader="""precision highp float;
uniform vec2 uViewport; uniform vec2 uSourceSize; uniform vec2 uOffset; uniform float uFlipY; uniform float uMasked;
uniform sampler2D uImage; uniform sampler2D uMask; uniform float uSolid; uniform vec4 uSolidColor; uniform vec2 uMaskOffset; uniform float uOpacity;
void main(){ vec2 p=vec2(gl_FragCoord.x,mix(gl_FragCoord.y,uViewport.y-gl_FragCoord.y,uFlipY));
vec4 c=texture2D(uImage,(p+uOffset)/uSourceSize); float maskAlpha=texture2D(uMask,(p-uMaskOffset)/uViewport).a;float a=uMasked>.5?maskAlpha:(uMasked<-.5?1.-maskAlpha:1.); gl_FragColor=(uSolid>.5?vec4(uSolidColor.rgb*uSolidColor.a,uSolidColor.a):c)*a*uOpacity; }
"""
        internal const val blurShader="""precision highp float;
uniform vec2 uViewport; uniform vec2 uDirection; uniform float uSigma; uniform sampler2D uImage;
void main(){vec2 uv=gl_FragCoord.xy/uViewport;vec4 sum=texture2D(uImage,uv);float total=1.;float radius=ceil(uSigma*3.);
for(int i=0;i<192;i++){float x=float(i*2+1);if(x>radius)break;float a=exp(-x*x/(2.*uSigma*uSigma));float b=x+1.<=radius?exp(-(x+1.)*(x+1.)/(2.*uSigma*uSigma)):0.;float weight=a+b;float offset=x+b/weight;sum+=(texture2D(uImage,uv+uDirection*offset)+texture2D(uImage,uv-uDirection*offset))*weight;total+=2.*weight;}
gl_FragColor=sum/max(total,.0001);}
"""
    }
}


internal object GlassEglDisplay {
    private val users=HashMap<EGLDisplay,Int>()
    @Synchronized fun acquire(display:EGLDisplay) {
        check(display!=EGL14.EGL_NO_DISPLAY) { "No EGL display" }
        val count=users[display]?:0
        if(count==0)check(EGL14.eglInitialize(display,IntArray(2),0,IntArray(2),0)) {
            "EGL initialization failed: 0x${EGL14.eglGetError().toString(16)}"
        }
        users[display]=count+1
    }
    @Synchronized fun release(display:EGLDisplay) {
        val count=users[display]?:return
        if(count>1)users[display]=count-1 else { users.remove(display);EGL14.eglTerminate(display) }
    }
}
