package com.green.note.nativebridge

internal fun vivoOsName(display: String, name: String, version: String): String? {
    // Compatibility properties may still say Funtouch/17 on an OriginOS 7 device.
    val explicit = Regex("(?i)^(OriginOS|Funtouch(?:\\s*OS)?)\\s*(\\d+(?:\\.\\d+)*)(?:\\s|$)")
        .find(display.trim())
    val family: String
    val number: String
    if (explicit != null) {
        family = if (explicit.groupValues[1].startsWith("Origin", true)) "OriginOS" else "Funtouch OS"
        number = explicit.groupValues[2]
    } else {
        number = version.trim()
        if (!Regex("\\d+(?:\\.\\d+)*").matches(number)) return null
        family = if (name.contains("funtouch", true)) "Funtouch OS" else "OriginOS"
    }
    return "$family ${if ('.' in number) number else "$number.0"}"
}
