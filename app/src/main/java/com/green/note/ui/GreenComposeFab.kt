package com.green.note.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** Original greenComposeFab: use inside GlassBackdropHost.overlay for the liquid material. */
@Composable
fun GreenComposeFab(onClick:()->Unit,modifier:Modifier=Modifier,useLiquidGlass:Boolean=true) {
    val click=rememberHapticClick(onClick)
    val button:@Composable ()->Unit = {
        Surface(onClick=click,modifier=Modifier.size(48.dp).semantics{contentDescription="发布动态"},
            shape=CircleShape,color=if(useLiquidGlass)Color.Transparent else Color(0xFF00B075),
            shadowElevation=if(useLiquidGlass)0.dp else 4.dp,border=BorderStroke(1.5.dp,Color(0x33FFFFFF))) {
            Box(contentAlignment=Alignment.Center){MaterialGlyph("add_rounded",size=26.dp,color=Color.White)}
        }
    }
    if(useLiquidGlass)GlassSurface(modifier.size(48.dp),cornerRadius=24.dp,liquid=true,interactive=false,
        material=GlassMaterial.NAVIGATION,tintColor=Color(0xCC00B075),themeAdaptive=false){button()}
    else Box(modifier){button()}
}
