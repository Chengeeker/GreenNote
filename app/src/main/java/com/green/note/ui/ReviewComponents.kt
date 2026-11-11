package com.green.note.ui

import com.green.note.ui.ReviewText as Text

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import com.green.note.R
import com.green.note.settings.AppPreferences
import kotlin.math.roundToInt

val LocalAppPreferences = staticCompositionLocalOf { AppPreferences() }
val LocalScaffoldColor = staticCompositionLocalOf { Color.White }
val LocalImageLoadingColor = staticCompositionLocalOf { Color(0xff6750a4) }
val LocalMaterialGlyphColor = staticCompositionLocalOf { Color(0xDD000000) }
val LocalIconButtonColor = staticCompositionLocalOf { Color.Unspecified }
val LocalMaterialGlyphSize = staticCompositionLocalOf { 24.dp }
internal val ReviewTextLocales = androidx.compose.ui.text.intl.LocaleList("zh-CN")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GreenNoteTheme(preferences: AppPreferences, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val dark = when (preferences.themeMode) { 1 -> false; 2 -> true; else -> isSystemInDarkTheme() }
    val index = AppPreferences.themeSeeds.indexOf(preferences.themeSeedArgb)
    val seedScheme = remember(preferences.themeSeedArgb,dark) {
        if(index >= 0) baselineSchemes[index * 2 + if (dark) 1 else 0] else seedColorScheme(preferences.themeSeedArgb,dark)
    }
    val scheme = if (preferences.dynamicColor && Build.VERSION.SDK_INT >= 31) {
        baselineDynamicColorScheme(context, dark, seedScheme)
    } else seedScheme
    val effectiveScheme = if (dark && preferences.pureBlackDark) scheme.copy(
        surface = Color.Black, surfaceContainer = Color(0xFF121212),
        surfaceContainerHigh = Color(0xFF181818), surfaceContainerHighest = Color(0xFF222222),
    ) else scheme
    val scaffold = if (dark) if (preferences.pureBlackDark) Color.Black else Color(0xFF111215) else scheme.surface
    val configuration = LocalConfiguration.current
    val systemAdjustment = if (Build.VERSION.SDK_INT >= 31) configuration.fontWeightAdjustment.let { if (it == Int.MAX_VALUE) 0 else it } else 0
    val delta = if (preferences.useCustomFontWeight) preferences.customFontWeightDelta else systemAdjustment
    val typography = reviewTypography(effectiveScheme.onSurfaceVariant, delta)
    val physicalDensity = LocalDensity.current.density
    val linearDensity = remember(physicalDensity, preferences.fontScale) { ReviewLinearDensity(physicalDensity, preferences.fontScale) }
    CompositionLocalProvider(
        LocalAppPreferences provides preferences,
        LocalScaffoldColor provides scaffold,
        LocalImageLoadingColor provides if (dark) effectiveScheme.surface else effectiveScheme.primary,
        LocalContentColor provides effectiveScheme.onSurface,
        LocalMaterialGlyphColor provides if(dark) Color.White else Color(0xDD000000),
        LocalRippleConfiguration provides null,
        LocalDensity provides linearDensity,
    ) { MaterialTheme(colorScheme = effectiveScheme, typography = typography) { ProvideTextStyle(typography.bodyMedium,content) } }
}

internal fun reviewTypography(secondary: Color, delta: Int): Typography {
    fun text(size: Float, height: Float, weight: Int = 400, color: Color = Color.Unspecified) = TextStyle(
        fontSize = size.sp, lineHeight = height.em,
        platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false),
        lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center, androidx.compose.ui.text.style.LineHeightStyle.Trim.None), fontWeight = FontWeight((weight + (delta / 100f).roundToInt() * 100).coerceIn(100, 900)),
        letterSpacing = 0.sp, color = color,
        localeList = ReviewTextLocales,
    )
    return Typography(
        displayLarge = text(57f, 1.12f), displayMedium = text(45f, 1.16f), displaySmall = text(36f, 1.22f),
        headlineLarge = text(32f, 1.25f), headlineMedium = text(28f, 1.29f), headlineSmall = text(24f, 1.33f),
        titleLarge = text(22f, 1.27f, 700), titleMedium = text(16f, 1.50f, 600), titleSmall = text(14f, 1.43f, 600, secondary),
        bodyLarge = text(16f, 1.50f), bodyMedium = text(16f, 1.43f), bodySmall = text(12f, 1.33f, color = secondary),
        labelLarge = text(14f, 1.43f, 600), labelMedium = text(12f, 1.33f, 500), labelSmall = text(11f, 1.45f, 500),
    )
}

@Composable
fun adjustedWeight(value: Int): FontWeight {
    val prefs = LocalAppPreferences.current
    val configuration = LocalConfiguration.current
    val system = if (Build.VERSION.SDK_INT >= 31) configuration.fontWeightAdjustment.let { if (it == Int.MAX_VALUE) 0 else it } else 0
    return FontWeight((value + ((if (prefs.useCustomFontWeight) prefs.customFontWeightDelta else system) / 100f).roundToInt() * 100).coerceIn(100, 900))
}

@Composable
fun MaterialGlyph(name: String, modifier: Modifier = Modifier, size: Dp = LocalMaterialGlyphSize.current, color: Color = LocalMaterialGlyphColor.current, contentDescription: String? = null) {
    val point = materialGlyphs[name] ?: error("Unknown baseline icon: $name")
    val font = remember { FontFamily(Font(R.font.greennote_material_icons)) }
    val descriptionModifier = if (contentDescription == null) Modifier else Modifier.semantics { this.contentDescription = contentDescription }
    Text(String(Character.toChars(point)), modifier.then(descriptionModifier).size(size), color = color, fontFamily = font,
        fontSize = with(LocalDensity.current) { size.toSp() }, lineHeight = with(LocalDensity.current) { size.toSp() },
        textAlign = TextAlign.Center, fontWeight = FontWeight.Normal, letterSpacing = 0.sp,
        style = TextStyle(localeList = ReviewTextLocales, platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false)))
}

@Composable
fun rememberHapticClick(onClick: () -> Unit): () -> Unit {
    val view = LocalView.current
    val enabled = LocalAppPreferences.current.haptics
    return { AppHaptics.light(view, enabled); onClick() }
}

@Composable
fun ReviewPage(title: String, onBack: () -> Unit, topPadding: Dp = 12.dp, contentHorizontalPadding: Dp = 16.dp,
    actions: @Composable RowScope.() -> Unit = {}, bottomPadding: Dp = 12.dp, content: @Composable ColumnScope.() -> Unit) {
    val scroll = rememberScrollState()
    ReviewScrollActivity(scroll)
    Column(Modifier.fillMaxSize().background(LocalScaffoldColor.current).imePadding()) {
        // Flutter's childless flexibleSpace DecoratedBox has zero height here, so no bottom border is painted.
        Column(Modifier.background(LocalScaffoldColor.current).statusBarsPadding()) {
            ReviewToolbarIcons { Row(Modifier.fillMaxWidth().height(52.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(56.dp).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null,
                    onClick = rememberHapticClick(onBack)), contentAlignment = Alignment.Center) {
                    MaterialGlyph("arrow_back", contentDescription = "返回")
                }
                Spacer(Modifier.width(16.dp))
                Text(title, Modifier.weight(1f), style = TextStyle(localeList = ReviewTextLocales, fontSize = 18.sp, fontWeight = adjustedWeight(700),
                    platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false)))
                actions()
            } }
        }
        Column(Modifier.fillMaxSize().verticalScroll(scroll).navigationBarsPadding()
            .padding(start = contentHorizontalPadding, end = contentHorizontalPadding, top = topPadding + 4.dp, bottom = bottomPadding), content = content)
    }
}

@Composable
fun SectionCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
        .background(scheme.settingsCardColor(LocalScaffoldColor.current)), content = content)
}

@Composable
fun SectionHeading(title: String, modifier: Modifier = Modifier, insideCard: Boolean = false,topPadding:Dp?=null,bottomPadding:Dp?=null) {
    Text(title, modifier.padding(start = 16.dp, top = topPadding ?: if (insideCard) 14.dp else 0.dp, bottom = bottomPadding ?: if (insideCard) 6.dp else 0.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (insideCard) 15.sp else 14.sp,
        fontWeight = adjustedWeight(if (insideCard) 700 else 600))
}

@Composable
fun PreferenceRow(title: String, subtitle: String? = null, icon: String? = null, enabled: Boolean = true,
    onClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null, titleSize: Float = 15f,
    subtitleSize: Float = 12.5f, primaryIcon: Boolean = false, horizontalPadding:Dp=16.dp, verticalPadding:Dp=0.dp, minVerticalPadding:Dp=8.dp,titleFontWeight:FontWeight?=null,
) {
    val modifier = if (onClick == null) Modifier else Modifier.clickable(enabled = enabled,
        interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = rememberHapticClick(onClick))
    ReviewTileLayout(modifier,horizontalPadding,verticalPadding,minVerticalPadding,
        leading=icon?.let{{MaterialGlyph(it,color=if(primaryIcon)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)}},
        trailing=trailing ?: {MaterialGlyph("chevron_right_rounded",color=MaterialTheme.colorScheme.onSurfaceVariant)},
        subtitle=subtitle?.let{{Text(it,fontSize=subtitleSize.sp,lineHeight=1.4.em,color=MaterialTheme.colorScheme.onSurfaceVariant)}}) {
        Text(title,fontSize=titleSize.sp,lineHeight=1.35.em,fontWeight=titleFontWeight?:adjustedWeight(600))
    }
}

@Composable
fun ChoiceRow(title: String, selected: Boolean, onClick: () -> Unit, summary: String? = null, enabled: Boolean = true,
    horizontalPadding:Dp=16.dp,verticalPadding:Dp=2.dp,controlSize:Dp=40.dp,titleWeight:Int=600,titleColor:Color?=null,subtitleColor:Color?=null,titleSize:Float=16f,subtitleSize:Float=14f,allowReselect:Boolean=false,titleFontWeight:FontWeight?=null) {
    val click=rememberHapticClick { if(!selected||allowReselect) onClick() }
    ReviewTileLayout(Modifier.selectable(selected, enabled = enabled, role = Role.RadioButton,
        interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = click),
        horizontalPadding,verticalPadding,4.dp,
        leading={Box(Modifier.size(controlSize),contentAlignment=Alignment.Center){ReviewRadioButton(selected,onClick=null,enabled=enabled,shrinkWrap=true)}},
        subtitle=summary?.let{{Text(it,fontSize=subtitleSize.sp,lineHeight=1.4.em,color=subtitleColor?:MaterialTheme.colorScheme.onSurfaceVariant)}}) {
        Text(title,fontSize=titleSize.sp,lineHeight=1.35.em,fontWeight=titleFontWeight?:adjustedWeight(titleWeight),color=titleColor?:MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, summary: String? = null, icon: String? = null, enabled: Boolean = true,titleSize:Float=16f,subtitleSize:Float=14f,horizontalPadding:Dp=16.dp,verticalPadding:Dp=3.dp,disabledTextColor:Color?=null) {
    val view = LocalView.current
    val haptics = LocalAppPreferences.current.haptics
    ReviewTileLayout(Modifier.toggleable(checked, enabled = enabled, role = Role.Switch,
        interactionSource = remember { MutableInteractionSource() }, indication = null,
        onValueChange = { AppHaptics.light(view, haptics); onChange(it) }),horizontalPadding=horizontalPadding,verticalPadding=verticalPadding,
        leading=icon?.let{{MaterialGlyph(it,color=MaterialTheme.colorScheme.primary)}},
        trailing={ReviewSwitch(checked,onCheckedChange=onChange,enabled=enabled,shrinkWrap=true)},
        subtitle=summary?.let{{Text(it,fontSize=subtitleSize.sp,lineHeight=1.4.em,color=if(!enabled&&disabledTextColor!=null)disabledTextColor else MaterialTheme.colorScheme.onSurfaceVariant)}}) {
        Text(title,fontSize=titleSize.sp,lineHeight=1.35.em,fontWeight=adjustedWeight(600),color=if(!enabled&&disabledTextColor!=null)disabledTextColor else MaterialTheme.colorScheme.onSurface)
    }
}
