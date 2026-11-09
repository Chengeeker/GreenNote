package com.green.note.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

private val imageHosts = setOf("api.coolapk.com", "api2.coolapk.com", "image.coolapk.com", "avatar.coolapk.com")
private val uriScheme = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")

/** Match the original network image path resolution before Android's HTTPS-only fetch. */
internal fun normalizeNetworkImageUrl(raw: String): String {
    val value = raw.trim()
    if (value.isEmpty() || value.any { it.isISOControl() || it == '\\' }) return ""
    val url = when {
        value.startsWith("//") -> "https:$value"
        uriScheme.containsMatchIn(value) -> value
        value.substringBefore('/') in imageHosts -> "https://$value"
        value.startsWith("/v6/") -> "https://api.coolapk.com$value"
        else -> "https://image.coolapk.com/${value.removePrefix("/")}"
    }.toHttpUrlOrNull() ?: return ""
    if (url.username.isNotEmpty() || url.password.isNotEmpty()) return ""
    return url.newBuilder().scheme("https").build().toString()
}
