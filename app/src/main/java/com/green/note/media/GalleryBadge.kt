package com.green.note.media

import com.green.note.content.feedPictureDimension
import com.green.note.content.feedPictureMetadata
import org.json.JSONObject

/** GalleryImage.isLong uses constructor dimensions, never decoded image dimensions.
 * Only the original NineGrid entry passes dimensions; article/cool-picture entries
 * pass raw metadata for HDR but leave width/height at zero. */
internal fun galleryBadge(url: String, feed: JSONObject?, detectedHdr: Boolean): String {
    if (url.contains(".gif", ignoreCase = true)) return "GIF"
    if (detectedHdr || galleryDeclaredHdr(url, feed)) return "HDR"
    if (url.contains("is_long=1", ignoreCase = true)) return "长图"
    if (feed?.optBoolean("_composeGalleryUseDeclaredDimensions") == true) {
        val metadata = feedPictureMetadata(feed, url)
        val width = feedPictureDimension(metadata, "width")
        val height = feedPictureDimension(metadata, "height")
        if (width > 0 && height > 0 && height.toDouble() / width > 2.0) return "长图"
    }
    return ""
}
