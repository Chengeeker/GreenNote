package com.green.note.ui

import com.green.note.ui.ReviewText as Text

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

/** Original selection dialogs use contentPadding(horizontal:0, vertical:12). */
@Composable
fun ReviewSelectionDialog(title:String,onDismiss:()->Unit,content:@Composable ColumnScope.()->Unit) {
    if(!reviewWindowVisible())return
    val paddingScale=reviewDialogPaddingScale(with(LocalDensity.current){14.sp.toDp().value/14f})
    val maximumHeight=with(LocalDensity.current){LocalWindowInfo.current.containerSize.height.toDp()}-48.dp
    Dialog(onDismiss,properties=DialogProperties(usePlatformDefaultWidth=false)) {
        ReviewDialogWindow(true)
        Surface(Modifier.stopWindowScrollOnPress().padding(horizontal=40.dp).widthIn(min=280.dp).heightIn(max=maximumHeight),
            shape=RoundedCornerShape(28.dp),color=MaterialTheme.colorScheme.surfaceContainerHigh,tonalElevation=0.dp) {
            Column {
                CompositionLocalProvider(LocalTextStyle provides TextStyle(localeList=ReviewTextLocales,fontSize=18.sp,fontWeight=adjustedWeight(700),platformStyle=androidx.compose.ui.text.PlatformTextStyle(includeFontPadding=false))) {
                    Text(title,Modifier.padding(start=(24*paddingScale).dp,top=(24*paddingScale).dp,end=(24*paddingScale).dp))
                }
                Column(Modifier.weight(1f,false).verticalScroll(rememberReviewScrollState()).padding(vertical=12.dp),content=content)
                Row(Modifier.fillMaxWidth().padding(start=24.dp,end=24.dp,bottom=24.dp),horizontalArrangement=Arrangement.End) {
                    com.green.note.ui.ReviewTextButton(onClick=onDismiss){Text("取消")}
                }
            }
        }
    }
}
