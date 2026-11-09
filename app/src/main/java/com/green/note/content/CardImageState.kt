package com.green.note.content

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.green.note.ui.MaterialGlyph

internal fun digitalHomeImage(row:org.json.JSONObject):String = listOf("logo","pic","message_cover")
    .firstNotNullOfOrNull { row.opt(it)?.takeUnless { value->value===org.json.JSONObject.NULL }?.toString() }.orEmpty()

/** Retains ExtendedImage's default loading while restoring each original errorBuilder. */
@Composable
internal fun CardImage(api:ContentApi,url:String,modifier:Modifier,scale:ContentScale=ContentScale.Crop,
    radius:Dp=0.dp,description:String?=null,fallback:@Composable ()->Unit={}) {
    var failed by remember(url,api.imageCacheScope()){mutableStateOf(false)}
    Box(modifier.clip(RoundedCornerShape(radius)),contentAlignment=Alignment.Center) {
        if(url.isEmpty())fallback() else {
            ContentImage(api,url,description,Modifier.fillMaxSize(),scale,heroCornerRadius=radius,
                onError={failed=true},onLoading={failed=false})
            if(failed)fallback()
        }
    }
}

@Composable
internal fun DiscoveryImage(api:ContentApi,url:String,description:String?,modifier:Modifier,scale:ContentScale=ContentScale.Crop) {
    if(url.isEmpty())Box(modifier) else CardImage(api,url,modifier,scale,description=description) {
        MaterialGlyph("broken_image_outlined",size=20.dp)
    }
}

@Composable
internal fun DiscoveryPicture(api:ContentApi,row:org.json.JSONObject,modifier:Modifier,
    scale:ContentScale=ContentScale.Crop,radius:Dp=0.dp) {
    DiscoveryImage(api,cardImage(row),cardTitle(row),modifier.clip(RoundedCornerShape(radius)),scale)
}
