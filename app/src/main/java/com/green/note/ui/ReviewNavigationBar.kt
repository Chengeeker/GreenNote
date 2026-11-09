package com.green.note.ui

import com.green.note.ui.ReviewText as Text

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.*

internal val navLabels=listOf("首页","数码","发布","发现","我的")
private val navIcons=listOf("home_outlined","smartphone_outlined","add_rounded","explore_outlined","person_outline_rounded")
private val navSelectedIcons=listOf("home_rounded","smartphone_rounded","add_rounded","explore_rounded","person_rounded")
internal val floatingNavigationHeight = 56.dp

internal fun floatingNavigationBottom(systemBottom: Dp) = maxOf(21.dp, systemBottom)

@Composable
internal fun FloatingNavigationFrame(systemBottom: Dp, content: @Composable (Dp) -> Unit) {
    BoxWithConstraints(
        Modifier.fillMaxWidth().padding(bottom = floatingNavigationBottom(systemBottom)),
        contentAlignment = Alignment.Center,
    ) {
        content(minOf(440.dp, maxWidth - 40.dp).coerceAtLeast(12.dp))
    }
}

@Composable
fun ReviewNavigationBar(selectedIndex:Int,onSelected:(Int)->Unit,hasBottomInset:Boolean=true) {
    val preferences=LocalAppPreferences.current
    val density=LocalDensity.current
    val systemBottom=with(density){WindowInsets.navigationBars.getBottom(this).toDp()}
    val select=rememberHapticClick { }
    if(!preferences.floatingNavBar) {
        val scheme=MaterialTheme.colorScheme
        val dark=scheme.surface.luminance()<.5f
        NavigationBar(containerColor=if(dark)if(preferences.pureBlackDark)Color.Black else Color(0xFF16171B) else scheme.surfaceContainer,tonalElevation=0.dp,
            windowInsets=if(hasBottomInset)WindowInsets.navigationBars else WindowInsets(0,0,0,0), modifier=Modifier.height(68.dp+if(hasBottomInset)systemBottom else 0.dp)) {
            navLabels.forEachIndexed { index,label -> NavigationBarItem(selected=selectedIndex==index,onClick={select();onSelected(index)},
                colors=NavigationBarItemDefaults.colors(selectedIconColor=scheme.onPrimaryContainer,selectedTextColor=scheme.primary,indicatorColor=scheme.primaryContainer,unselectedIconColor=scheme.onSurfaceVariant,unselectedTextColor=scheme.onSurfaceVariant),
                icon={MaterialGlyph(if(index==selectedIndex)navSelectedIcons[index] else navIcons[index])},label={Text(label,fontSize=12.sp,fontWeight=adjustedWeight(if(index==selectedIndex)700 else 500))}) }
        }
        return
    }
    if (preferences.liquidGlassNavBar && LocalGlassBackdrop.current != null) {
        RedNoteGlassNavigation(selectedIndex, onSelected, hasBottomInset)
    } else {
        FloatingNavigationFrame(if (hasBottomInset) systemBottom else 0.dp) { width ->
            PlainFloatingNavigationBar(selectedIndex, onSelected, Modifier.width(width).height(floatingNavigationHeight))
        }
    }
}

@Composable
private fun PlainFloatingNavigationBar(selected:Int,onSelected:(Int)->Unit,modifier:Modifier) {
    val fraction by animateFloatAsState(selected/4f,tween(220,easing=CubicBezierEasing(.215f,.61f,.355f,1f)),label="selection")
    val dark=MaterialTheme.colorScheme.surface.luminance()<.5f
    val shape = RoundedCornerShape(50)
    BoxWithConstraints(modifier.dropShadow(shape,Shadow(radius=16.dp,color=Color.Black.copy(alpha=if(dark).35f else .12f),offset=DpOffset(0.dp,4.dp)))
        .background(MaterialTheme.colorScheme.surfaceContainerHigh,shape).padding(4.dp)) {
        val itemWidth=maxWidth/5
        Box(Modifier.offset { IntOffset(((maxWidth-itemWidth)*fraction).roundToPx(),0) }.width(itemWidth).fillMaxHeight()
            .background(MaterialTheme.colorScheme.secondaryContainer,RoundedCornerShape(28.dp)))
        Row(Modifier.fillMaxSize()) { navLabels.forEachIndexed { index,label ->
            val foreground=if(selected==index)MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
            val action=rememberHapticClick{onSelected(index)}
            Surface(onClick=action,modifier=Modifier.weight(1f).fillMaxHeight(),color=Color.Transparent) {
                Column(Modifier.fillMaxSize(),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
                    MaterialGlyph(if(selected==index)navSelectedIcons[index] else navIcons[index],size=22.dp,color=foreground)
                    Spacer(Modifier.height(2.dp));Text(label,fontSize=11.5.sp,lineHeight=1.43.em,fontWeight=adjustedWeight(if(selected==index)600 else 400),color=foreground)
                }
            }
        } }
    }
}
