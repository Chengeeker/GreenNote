package com.green.note.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

internal fun reviewButtonPadding(scale:Float,one:Float,two:Float,three:Float):Float = when {
    scale<=1 ->one
    scale<2 ->one+(two-one)*(scale-1)
    scale<3 ->two+(three-two)*(scale-2)
    else ->three
}

@Composable fun ReviewButtonIconGap() {
    val scale=with(LocalDensity.current){14.sp.toDp().value/14}
    Spacer(Modifier.width((8f-4f*(scale-1f).coerceIn(0f,1f)).dp))
}

@Composable private fun originalButtonPadding(text:Boolean,icon:Boolean):PaddingValues {
    val scale=with(LocalDensity.current){14.sp.toDp().value/14}
    return if(text) PaddingValues(start=reviewButtonPadding(scale,12f,if(icon)4f else 8f,4f).dp,
        end=reviewButtonPadding(scale,if(icon)16f else 12f,if(icon)4f else 8f,4f).dp,
        top=reviewButtonPadding(scale,8f,0f,0f).dp,bottom=reviewButtonPadding(scale,8f,0f,0f).dp)
    else PaddingValues(start=reviewButtonPadding(scale,if(icon)16f else 24f,if(icon)8f else 12f,if(icon)4f else 6f).dp,
        end=reviewButtonPadding(scale,24f,12f,6f).dp)
}

@Composable
fun ReviewButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,shape:Shape=ButtonDefaults.shape,
    colors:ButtonColors=ButtonDefaults.buttonColors(),elevation:ButtonElevation?=ButtonDefaults.buttonElevation(),border:BorderStroke?=null,
    contentPadding:PaddingValues?=null,interactionSource:MutableInteractionSource?=null,iconPadding:Boolean=false,content:@Composable RowScope.()->Unit) {
    CompositionLocalProvider(LocalMaterialGlyphSize provides 18.dp){
        Button(rememberHapticClick(onClick),modifier.defaultMinSize(64.dp,40.dp),enabled,shape,colors,elevation,border,contentPadding?:originalButtonPadding(false,iconPadding),interactionSource) { CompositionLocalProvider(LocalMaterialGlyphColor provides LocalContentColor.current) { content() } }
    }
}

@Composable
fun ReviewFilledTonalButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,shape:Shape=ButtonDefaults.filledTonalShape,
    colors:ButtonColors=ButtonDefaults.filledTonalButtonColors(),elevation:ButtonElevation?=ButtonDefaults.filledTonalButtonElevation(),border:BorderStroke?=null,
    contentPadding:PaddingValues?=null,interactionSource:MutableInteractionSource?=null,iconPadding:Boolean=false,content:@Composable RowScope.()->Unit) {
    CompositionLocalProvider(LocalMaterialGlyphSize provides 18.dp){
        FilledTonalButton(rememberHapticClick(onClick),modifier.defaultMinSize(64.dp,40.dp),enabled,shape,colors,elevation,border,contentPadding?:originalButtonPadding(false,iconPadding),interactionSource) { CompositionLocalProvider(LocalMaterialGlyphColor provides LocalContentColor.current) { content() } }
    }
}

@Composable
fun ReviewOutlinedButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,shape:Shape=ButtonDefaults.outlinedShape,
    colors:ButtonColors=ButtonDefaults.outlinedButtonColors(),elevation:ButtonElevation?=null,border:BorderStroke?=null,
    contentPadding:PaddingValues?=null,interactionSource:MutableInteractionSource?=null,iconPadding:Boolean=false,content:@Composable RowScope.()->Unit) {
    val source=interactionSource?:remember{MutableInteractionSource()}
    val focused by source.collectIsFocusedAsState()
    val originalBorder=border?:BorderStroke(1.dp,if(!enabled)MaterialTheme.colorScheme.onSurface.copy(alpha=.12f)else if(focused)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
    CompositionLocalProvider(LocalMaterialGlyphSize provides 18.dp){
        OutlinedButton(rememberHapticClick(onClick),modifier.defaultMinSize(64.dp,40.dp),enabled,shape,colors,elevation,originalBorder,contentPadding?:originalButtonPadding(false,iconPadding),source) { CompositionLocalProvider(LocalMaterialGlyphColor provides LocalContentColor.current) { content() } }
    }
}

@Composable
fun ReviewTextButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,shape:Shape=ButtonDefaults.textShape,
    colors:ButtonColors=ButtonDefaults.textButtonColors(),elevation:ButtonElevation?=null,border:BorderStroke?=null,
    contentPadding:PaddingValues?=null,interactionSource:MutableInteractionSource?=null,iconPadding:Boolean=false,content:@Composable RowScope.()->Unit) {
    CompositionLocalProvider(LocalMaterialGlyphSize provides 18.dp){
        TextButton(rememberHapticClick(onClick),modifier.defaultMinSize(64.dp,40.dp),enabled,shape,colors,elevation,border,contentPadding?:originalButtonPadding(true,iconPadding),interactionSource) { CompositionLocalProvider(LocalMaterialGlyphColor provides LocalContentColor.current) { content() } }
    }
}
