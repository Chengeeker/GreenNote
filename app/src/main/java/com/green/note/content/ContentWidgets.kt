package com.green.note.content

import com.green.note.ui.ReviewText as Text

import android.content.Context
import android.text.Html
import android.text.style.URLSpan
import androidx.compose.foundation.background
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import android.widget.Toast
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import com.green.note.ui.MaterialGlyph
import com.green.note.media.GalleryHeroRegistry
import com.green.note.network.normalizeNetworkImageUrl
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
internal fun ContentIcon(name: String, description: String, onClick: () -> Unit, modifier: Modifier = Modifier, size: Dp = 24.dp) {
    val color = com.green.note.ui.LocalIconButtonColor.current.takeIf { it != androidx.compose.ui.graphics.Color.Unspecified }
        ?: MaterialTheme.colorScheme.onSurfaceVariant
    Box(modifier.size(48.dp).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        MaterialGlyph(name, size = size, color = color, contentDescription = description)
    }
}

internal fun contentImageRequest(context: Context, api: ContentApi, url: String, owner: String = api.imageCacheScope()) =
    ImageRequest.Builder(context).data(url.takeIf(String::isNotEmpty)).crossfade(false)
        .memoryCacheKey("$owner:$url").diskCacheKey("$owner|$url").apply {
            api.imageHeaders(url).forEach { (name, value) -> addHeader(name, value) }
            if (!url.substringBefore('?').endsWith(".gif", true)) addHeader("Accept", "image/jpeg,image/*;q=.8")
        }

@Composable
internal fun ContentImage(api: ContentApi, url: String, description: String?, modifier: Modifier, scale: ContentScale = ContentScale.Crop,
    heroCornerRadius: Dp = 8.dp, onDecoded: ((Int, Int) -> Unit)? = null, onError: ((Throwable) -> Unit)? = null,
    onLoading: (() -> Unit)? = null, showLoading: Boolean = true, showDefaultError: Boolean = true) {
    val context = LocalContext.current
    val radius = with(androidx.compose.ui.platform.LocalDensity.current) { heroCornerRadius.toPx() }
    val decoded by rememberUpdatedState(onDecoded)
    val failed by rememberUpdatedState(onError)
    val invalidateBackdrop = com.green.note.ui.rememberGlassContentInvalidator()
    val normalized = remember(url) { normalizeNetworkImageUrl(url) }
    val cacheScope = api.imageCacheScope()
    var retry by remember(normalized, cacheScope) { mutableIntStateOf(0) }
    var loadState by remember(normalized, cacheScope, retry) { mutableIntStateOf(0) }
    val hero = remember(normalized, cacheScope) { ContentHeroSource() }
    val request = remember(normalized, api, cacheScope) {
        contentImageRequest(context, api, normalized, cacheScope).build()
    }
    Box(modifier, propagateMinConstraints = true) {
    key(retry) { AsyncImage(model = request, contentDescription = description, modifier = Modifier.onGloballyPositioned { coordinates ->
        hero.bounds = coordinates.boundsInRoot()
        hero.drawable?.let { GalleryHeroRegistry.record(normalized, hero.bounds, it, scale, radius) }
    }.pointerInput(normalized, scale, radius) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            hero.drawable?.let { GalleryHeroRegistry.record(normalized, hero.bounds, it, scale, radius); GalleryHeroRegistry.claim(normalized) }
        }
    }, contentScale = scale, onSuccess = { success ->
        loadState = 1
        hero.drawable = success.result.drawable
        GalleryHeroRegistry.record(normalized, hero.bounds, success.result.drawable, scale, radius)
        decoded?.invoke(success.result.drawable.intrinsicWidth, success.result.drawable.intrinsicHeight)
        invalidateBackdrop()
    }, onError = { loadState = 2; failed?.invoke(it.result.throwable); invalidateBackdrop() }, onLoading = { loadState = 0; onLoading?.invoke() }) }
    if (showLoading && loadState == 0) Box(Modifier.align(Alignment.Center), contentAlignment = Alignment.Center) {
        com.green.note.ui.ReviewCircularProgress(Modifier.size(36.dp), color = com.green.note.ui.LocalImageLoadingColor.current, strokeWidth = 2.dp)
    }
    if (showDefaultError && onError == null && loadState == 2) Box(Modifier.align(Alignment.Center), contentAlignment = Alignment.Center) {
        Text("Failed to load image", Modifier.clickable { retry++ })
    }
    }
}

private class ContentHeroSource {
    var bounds = androidx.compose.ui.geometry.Rect.Zero
    var drawable: android.graphics.drawable.Drawable? = null
}

@Composable
internal fun ContentAvatar(api: ContentApi, url: String, name: String, size: Dp = 36.dp, onClick: (() -> Unit)? = null) {
    val scheme = MaterialTheme.colorScheme
    var fallback by remember(url, api.imageCacheScope()) { mutableStateOf(true) }
    Box(Modifier.size(size).clip(CircleShape).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier), contentAlignment = Alignment.Center) {
        if (fallback) Box(Modifier.fillMaxSize().background(scheme.primaryContainer), contentAlignment = Alignment.Center) {
            val initial = avatarInitial(name)
            if (initial.isNotEmpty()) Text(initial, color = scheme.onPrimaryContainer, fontWeight = FontWeight.Bold, fontSize = (size.value * .45f).sp)
            else MaterialGlyph("person_rounded", size = size * .55f, color = scheme.onPrimaryContainer)
        }
        if (url.isNotBlank()) ContentImage(api, url, name, Modifier.fillMaxSize(), heroCornerRadius = size / 2,
            onDecoded = { _, _ -> fallback = false }, onError = { fallback = true }, onLoading = { fallback = true }, showLoading = false)
    }
}

internal fun avatarInitial(name: String): String = name.trim().let {
    if (it.isEmpty()) "" else String(Character.toChars(it.codePointAt(0))).uppercase(Locale.ROOT)
}

internal fun relativeTime(raw: String, now: Long = System.currentTimeMillis()): String {
    val number = raw.toLongOrNull()?.takeIf { it > 0 } ?: return ""
    val timestamp = if (number > 1_000_000_000_000) number else number * 1000
    val duration = now - timestamp
    return when {
        duration < 0 -> ""
        duration < 60_000 -> "刚刚"
        duration < 3_600_000 -> "${duration / 60_000}分钟前"
        duration < 86_400_000 -> "${duration / 3_600_000}小时前"
        duration < 30L * 86_400_000 -> "${duration / 86_400_000}天前"
        else -> SimpleDateFormat("M月d日", Locale.CHINA).format(Date(timestamp))
    }
}

internal fun feedImages(row: JSONObject): List<String> {
    val result = linkedSetOf<String>()
    for (field in listOf("picArr", "pics", "imageUriList", "image_uri_list")) row.optJSONArray(field)?.let { list ->
        for (i in 0 until list.length()) {
            val value = when (val item = list.opt(i)) { is String -> item.trim(); is JSONObject -> item.text("url", "pic", "image", "original", "originalUrl"); else -> "" }
            if (value.isNotBlank()) result.add(value)
        }
    }
    row.text("pic").split(',').map(String::trim).filter(String::isNotEmpty).forEach(result::add)
    return result.toList()
}

@Composable
internal fun FeedImages(api: ContentApi, images: List<String>, detail: Boolean = false, joined: Boolean = false, raw: JSONObject? = null, onOpen: (List<String>, Int) -> Unit) {
    val visible = if (detail) images else images.take(9)
    if (visible.isEmpty()) return
    val columns = if (visible.size in setOf(1, 2, 4)) 2 else 3
    val gap = if (joined) 3.dp else 7.dp
    val indices = visible.indices.toList()
    val groups = if (joined && visible.size == 5) listOf(indices.take(2), indices.drop(2)) else indices.chunked(columns)
    Column(Modifier.then(if (joined) Modifier.clip(RoundedCornerShape(8.dp)) else Modifier), verticalArrangement = Arrangement.spacedBy(gap)) {
        groups.forEach { group ->
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                group.forEach { index -> FeedImageTile(api,visible[index],raw,index,joined,
                    if(!detail&&index==8)(images.size-9).coerceAtLeast(0)else 0,Modifier.weight(1f).aspectRatio(1f)) {onOpen(images,index)} }
                if (!(joined && visible.size == 5)) repeat(columns - group.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
internal fun FeedRow(api: ContentApi, row: JSONObject, detail: Boolean = false, onOpen: (JSONObject) -> Unit,
    onUser: (String) -> Unit, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit, onLike: (JSONObject) -> Unit,
    onMore: (JSONObject) -> Unit, body: (@Composable () -> Unit)? = null) =
    NativeFeedCard(api,row,detail,onOpen,onUser,onLink,onGallery,onLike,onMore,body)

@Composable
internal fun FeedAction(icon: String, count: String, onClick: () -> Unit) {
    Row(Modifier.heightIn(min = 40.dp).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        MaterialGlyph(icon, size = 20.dp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(6.dp)); Text(count, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
