package com.green.note.media

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.ReviewText as Text

@Composable
internal fun HdrBadge(modifier: Modifier = Modifier, description: String = "HDR 图片", compact: Boolean = false) {
    Text("HDR", modifier.semantics { contentDescription = description }
        .background(Color.Black.copy(alpha = .4f), RoundedCornerShape(4.dp))
        .padding(horizontal = if (compact) 3.dp else 6.dp, vertical = if (compact) 1.dp else 2.dp),
        color = Color.White, fontSize = if (compact) 8.sp else 10.sp, lineHeight = if (compact) 9.sp else 12.sp,
        fontWeight = FontWeight.Normal)
}
