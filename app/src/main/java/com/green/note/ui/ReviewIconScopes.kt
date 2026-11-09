package com.green.note.ui

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

/** AppBar's foreground differs from both the root IconTheme and M3 IconButton defaults. */
@Composable
fun ReviewToolbarIcons(color:Color=MaterialTheme.colorScheme.onSurface,content:@Composable ()->Unit) {
    CompositionLocalProvider(LocalMaterialGlyphColor provides color, LocalIconButtonColor provides color,
        LocalContentColor provides color,content=content)
}

@Composable
fun ReviewIconButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,
    colors:IconButtonColors=IconButtonDefaults.iconButtonColors(
        contentColor=LocalIconButtonColor.current.takeIf { it!=Color.Unspecified } ?: MaterialTheme.colorScheme.onSurfaceVariant),
    interactionSource:MutableInteractionSource?=null,content:@Composable ()->Unit) {
    IconButton(rememberHapticClick(onClick),modifier,enabled,colors,interactionSource) {
        CompositionLocalProvider(LocalMaterialGlyphColor provides LocalContentColor.current,content=content)
    }
}
