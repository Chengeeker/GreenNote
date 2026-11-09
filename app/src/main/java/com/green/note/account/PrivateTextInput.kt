package com.green.note.account

import android.text.InputType
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.PlatformTextInputMethodRequest

/** Preserve the original sensitive fields' no-suggestion/no-personalized-learning IME contract. */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
internal fun PrivateTextInput(content: @Composable () -> Unit) {
    InterceptPlatformTextInput(interceptor = { request, next ->
        next.startInputMethod(object : PlatformTextInputMethodRequest {
            override fun createInputConnection(outAttributes: EditorInfo): InputConnection {
                val connection = request.createInputConnection(outAttributes)
                if (android.os.Build.VERSION.SDK_INT >= 26) outAttributes.imeOptions = outAttributes.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                outAttributes.inputType = outAttributes.inputType or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                return connection
            }
        })
    }, content = content)
}
