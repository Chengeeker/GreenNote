package com.green.note.network

import android.util.Log
import okhttp3.HttpUrl

/** Deliberately excludes query strings, IDs, message text, credentials, and verification proofs. */
internal object ReplyDiagnostics {
    private const val TAG = "GreenNoteReplies"

    fun response(url: HttpUrl, client: Int, http: Int, status: Int?, messageStatus: String, captchaSupported: Boolean) {
        networkLine(url, client, http, status, messageStatus, captchaSupported)?.let(::write)
    }

    internal fun networkLine(url: HttpUrl, client: Int, http: Int, status: Int?, messageStatus: String, captchaSupported: Boolean): String? {
        if (!ApiRules.commentRead(url)) return null
        val category = when (messageStatus) { "err_request_captcha_v2" -> "err_request_captcha_v2"; "", "null" -> "none"; else -> "other" }
        return "response host=${url.host} path=${url.encodedPath} client=$client http=$http status=${status ?: "none"} messageStatus=$category captchaMetadata=$captchaSupported"
    }

    fun page(path: String, sourceCount: Int, visibleCount: Int, missingBodyCount: Int, hydrationCount: Int, partial: Boolean = false) {
        if (path !in ApiRules.commentPaths) return
        write("page path=$path source=${sourceCount.coerceAtLeast(0)} visible=${visibleCount.coerceAtLeast(0)} missingBody=${missingBodyCount.coerceAtLeast(0)} hydrated=${hydrationCount.coerceAtLeast(0)} partial=$partial")
    }

    private fun write(line: String) {
        // A diagnostic sink must never change request behavior, including in plain JVM tests.
        runCatching { Log.i(TAG, line) }
    }
}
