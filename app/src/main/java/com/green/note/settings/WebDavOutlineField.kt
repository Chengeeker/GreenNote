package com.green.note.settings

import com.green.note.ui.ReviewText as Text

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.*
import androidx.compose.foundation.layout.*
import com.green.note.ui.ReviewBasicTextField as BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.green.note.ui.MaterialGlyph
import kotlin.math.*

internal object WebDavFieldGeometry {
    fun containerHeight(inputHeight:Float)=max(48f,inputHeight+24f)
    fun labelX(progress:Float)=52f-36f*progress
    fun labelScale(progress:Float)=1f-.25f*progress
    fun gapWidth(labelWidth:Float,progress:Float)=(labelWidth*.75f+8f)*progress
}

internal fun webDavKeyboardOptions(secret:Boolean)=KeyboardOptions(
    keyboardType=if(secret)KeyboardType.Password else KeyboardType.Text,autoCorrectEnabled=!secret)

/** Original TextFormField: outlined R4, dense 12/16/12/8 padding, 48dp prefix slot with an 18dp icon. */
@Composable
internal fun WebDavOutlineField(label:String,value:String,onValue:(String)->Unit,icon:String,enabled:Boolean,
    hint:String?,secret:Boolean,error:String?) {
    val scheme=MaterialTheme.colorScheme
    val density=LocalDensity.current
    val interactions=remember{MutableInteractionSource()}
    val focused by interactions.collectIsFocusedAsState()
    val hovered by interactions.collectIsHoveredAsState()
    val floating=focused||value.isNotEmpty()
    val controller=remember{Animatable(if(floating)1f else 0f)}
    LaunchedEffect(floating){val target=if(floating)1f else 0f;controller.animateTo(target,tween((167*abs(target-controller.value)).roundToInt(),easing=LinearEasing))}
    val progress=if(floating)FastOutSlowInEasing.transform(controller.value)else 1-FastOutSlowInEasing.transform(1-controller.value)
    val targetBorder=when{!enabled->scheme.onSurface.copy(alpha=.12f);error!=null->if(hovered&&!focused)scheme.onErrorContainer else scheme.error;focused->scheme.primary;hovered->scheme.onSurface;else->scheme.outline}
    val border by animateColorAsState(targetBorder,tween(167,easing=FastOutSlowInEasing),label="field border")
    val stroke by animateFloatAsState(if(enabled&&focused)2f else 1f,tween(167,easing=FastOutSlowInEasing),label="field border width")
    val targetLabel=when{!enabled->scheme.onSurface.copy(alpha=.38f);error!=null->if(hovered&&!focused)scheme.onErrorContainer else scheme.error;focused->scheme.primary;else->scheme.onSurfaceVariant}
    val labelColor by animateColorAsState(targetLabel,tween(167,easing=FastOutSlowInEasing),label="field label color")
    val inputColor=scheme.onSurface.copy(alpha=if(enabled)1f else .38f)
    val iconColor=if(enabled)scheme.onSurfaceVariant else scheme.onSurface.copy(alpha=.38f)
    val hintColor=iconColor
    val inputStyle=MaterialTheme.typography.bodyLarge.copy(color=inputColor)
    val labelStyle=MaterialTheme.typography.bodyLarge.copy(color=labelColor)
    val measurer=rememberTextMeasurer()
    val hintOpacity by animateFloatAsState(if(floating&&value.isEmpty())1f else 0f,tween(167,easing=FastOutSlowInEasing),label="field hint")
    var retainedError by remember{mutableStateOf(error)}
    if(error!=null)SideEffect{retainedError=error}
    val errorOpacity by animateFloatAsState(if(error!=null)1f else 0f,tween(167,easing=FastOutSlowInEasing),label="field error")
    Column(Modifier.fillMaxWidth()) {
        BasicTextField(value,onValue,Modifier.fillMaxWidth().hoverable(interactions,enabled)
            .semantics{contentDescription=label;if(error!=null){this.error(error);liveRegion=LiveRegionMode.Polite}},
            enabled=enabled,singleLine=true,keyboardOptions=webDavKeyboardOptions(secret),textStyle=inputStyle,cursorBrush=SolidColor(if(error!=null)scheme.error else scheme.primary),
            visualTransformation=if(secret)PasswordVisualTransformation('\u2022')else VisualTransformation.None,
            interactionSource=interactions,decorationBox={field->
                Layout(modifier=Modifier.drawWithCache {
                    val labelText=measurer.measure(label,labelStyle,maxLines=1,overflow=TextOverflow.Ellipsis,
                        constraints=Constraints(maxWidth=max(0,((size.width-68.dp.toPx())/WebDavFieldGeometry.labelScale(progress)).roundToInt())))
                    onDrawWithContent {
                    val px=stroke.dp.toPx();val inset=px/2
                    val gapLeft=12.dp.toPx()
                    val gapRight=gapLeft+WebDavFieldGeometry.gapWidth(labelText.size.width/density.density,progress).dp.toPx()
                    // Keep the original 4dp gap on either side without painting over the surrounding card.
                    clipRect(left=gapLeft,top=-px,right=gapRight,bottom=px*2,clipOp=ClipOp.Difference){
                        drawRoundRect(border,Offset(inset,inset),Size(size.width-px,size.height-px),CornerRadius(max(0f,4.dp.toPx()-inset)),style=Stroke(px))
                    }
                    drawContent()
                    val x=WebDavFieldGeometry.labelX(progress).dp.toPx()
                    val inlineY=(size.height-labelText.size.height)/2
                    val floatY=-labelText.size.height*.75f/2+px/2
                    translate(x,inlineY+(floatY-inlineY)*progress){scale(WebDavFieldGeometry.labelScale(progress),pivot=Offset.Zero){drawText(labelText)}}
                    }
                },content={
                    Box {field();if(hint!=null&&value.isEmpty())Text(hint,Modifier.graphicsLayer{alpha=hintOpacity},style=inputStyle.copy(color=hintColor),maxLines=1,overflow=TextOverflow.Clip)}
                    MaterialGlyph(icon,size=18.dp,color=iconColor)
                },measurePolicy=WebDavFieldMeasurePolicy)
            })
        if(retainedError!=null&&(error!=null||errorOpacity>0))Text(retainedError.orEmpty(),Modifier.padding(start=16.dp,end=16.dp,top=4.dp)
            .graphicsLayer{alpha=errorOpacity;translationY=-size.height*.25f*(1-errorOpacity)},
            style=MaterialTheme.typography.bodySmall.copy(color=scheme.error),maxLines=1,overflow=TextOverflow.Ellipsis)
    }
}
