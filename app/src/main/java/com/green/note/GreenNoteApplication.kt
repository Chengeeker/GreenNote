package com.green.note

import android.app.Application
import android.os.Build
import android.webkit.WebView

class GreenNoteApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 28) WebView.setDataDirectorySuffix("greennote_compose")
    }
}
