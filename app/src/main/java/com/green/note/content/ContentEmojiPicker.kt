package com.green.note.content

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.green.note.ui.ReviewScrollActivity
import com.green.note.ui.ReviewText
import com.green.note.ui.tapClickable

private val coolapkEmojiTokens by lazy {
    val common = listOf("滑稽", "doge", "笑哭", "捂脸", "点赞", "机智", "吃瓜", "微笑", "流泪", "白眼", "酷", "疑问")
    (common + contentEmojiCodes.keys().asSequence().sorted().toList())
        .filter { contentEmojiCode(it) in contentEmojiDrawables }
        .distinctBy(::contentEmojiCode)
        .map { "[$it]" }
}
private val privateMessageEmojiTokens by lazy {
    coolapkEmojiTokens + listOf("🙂", "😀", "😂", "🥰", "😭", "😅", "😎", "👍", "🙏", "🐶", "🤔", "🎉")
}

internal fun TextFieldValue.insertEmoji(token: String): TextFieldValue {
    val start = selection.min
    return TextFieldValue(text.replaceRange(start, selection.max, token), TextRange(start + token.length))
}

@Composable
internal fun ContentEmojiPicker(includeUnicode: Boolean = false, onPick: (String) -> Unit) {
    val scroll = rememberLazyGridState()
    ReviewScrollActivity(scroll)
    LazyVerticalGrid(GridCells.Fixed(6), Modifier.fillMaxWidth().height(220.dp).semantics { contentDescription = "表情列表" },
        state = scroll, contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)) {
        items(if (includeUnicode) privateMessageEmojiTokens else coolapkEmojiTokens, key = { it }) { token ->
            Column(Modifier.aspectRatio(1f).clip(RoundedCornerShape(8.dp)).tapClickable { onPick(token) },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                if (token.startsWith('[')) {
                    val name = token.removeSurrounding("[", "]")
                    ContentEmotion(name, Modifier.size(26.dp), 18.sp)
                    ReviewText(name, Modifier.padding(horizontal = 2.dp), fontSize = 10.sp, maxLines = 1,
                        overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else ReviewText(token, fontSize = 26.sp)
            }
        }
    }
}
