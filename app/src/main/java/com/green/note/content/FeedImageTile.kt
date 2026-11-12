package com.green.note.content

import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import com.green.note.ui.ReviewText as Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.imageLoader
import com.green.note.media.HdrImageDetection
import com.green.note.media.HdrImageRegistry
import com.green.note.media.HdrBadge
import com.green.note.network.normalizeNetworkImageUrl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

@OptIn(coil.annotation.ExperimentalCoilApi::class)
@Composable
internal fun FeedImageTile(api:ContentApi,url:String,raw:JSONObject?,index:Int,joined:Boolean,overflow:Int,modifier:Modifier,badgeOnTop:Boolean=false,onOpen:()->Unit) {
    val metadata=remember(raw,url){feedPictureMetadata(raw,url)}
    val known by HdrImageRegistry.known.collectAsState()
    val normalized = remember(url) { normalizeNetworkImageUrl(url) }
    var dimensions by remember(url){mutableStateOf(0 to 0)}
    val context=LocalContext.current;val cacheScope=api.imageCacheScope()
    LaunchedEffect(normalized,cacheScope,dimensions) {
        if(dimensions.first<=0||known.contains(normalized))return@LaunchedEffect
        val hdr=withContext(Dispatchers.IO) {
            runCatching {
                context.imageLoader.diskCache?.openSnapshot("$cacheScope|$normalized")?.use { snapshot ->
                    snapshot.data.toFile().inputStream().use { input ->
                        val bytes=ByteArray(131072);var count=0
                        while(count<bytes.size){val read=input.read(bytes,count,bytes.size-count);if(read<=0)break;count+=read}
                        HdrImageDetection.hasMetadata(if(count==bytes.size)bytes else bytes.copyOf(count))
                    }
                } ?: false
            }.getOrDefault(false)
        }
        if(hdr)HdrImageRegistry.mark(normalized)
    }
    val badge=feedImageBadge(url,metadata,raw,normalized in known,dimensions.first,dimensions.second)
    val radius=if(joined)0.dp else 12.dp
    Box(modifier.clip(RoundedCornerShape(radius)).background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha=.4f)).clickable(onClick=onOpen)) {
        ContentImage(api,url,"图片 ${index+1}",Modifier.fillMaxSize(),heroCornerRadius=radius,onDecoded={w,h->dimensions=w to h})
        if (badge != null) {
            val badgeModifier = Modifier.align(if (badgeOnTop) Alignment.TopStart else Alignment.BottomEnd)
                .padding(if (badgeOnTop) 8.dp else 4.dp)
            if (badge == "HDR") HdrBadge(badgeModifier)
            else Text(badge, badgeModifier.background(Color.Black.copy(alpha = if (badgeOnTop) .42f else .72f), RoundedCornerShape(4.dp))
                .padding(horizontal = 5.dp, vertical = 2.dp), color = Color.White, fontSize = 10.sp,
                fontWeight = FontWeight.Bold, letterSpacing = 0.sp, lineHeight = 12.sp)
        }
        if(overflow>0)Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha=.45f)),contentAlignment=Alignment.Center) {
            Text("+$overflow",color=Color.White,fontSize=24.sp,fontWeight=FontWeight.SemiBold)
        }
    }
}
