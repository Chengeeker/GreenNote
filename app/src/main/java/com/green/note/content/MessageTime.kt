package com.green.note.content

import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal fun messageTime(raw: String, now: Long = System.currentTimeMillis(), zone: TimeZone = TimeZone.getDefault()): String {
    if (raw.isEmpty()) return ""
    val number = raw.toLongOrNull()
    val date = if (number != null) {
        val seconds = if (number > 10_000_000_000L) number / 1000 else number
        if (seconds > Long.MAX_VALUE / 1000 || seconds < Long.MIN_VALUE / 1000) return raw
        Date(seconds * 1000)
    } else listOf("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd").firstNotNullOfOrNull { pattern ->
        val input = raw.replace(' ', 'T'); val position = ParsePosition(0)
        SimpleDateFormat(pattern, Locale.ROOT).apply { isLenient = false; timeZone = zone }.parse(input, position)?.takeIf { position.index == input.length }
    } ?: return raw
    val current = Calendar.getInstance(zone).apply { timeInMillis = now }
    val value = Calendar.getInstance(zone).apply { time = date }
    val pattern = if (value.get(Calendar.YEAR) != current.get(Calendar.YEAR)) "yy-MM-dd"
        else if (value.get(Calendar.DAY_OF_YEAR) == current.get(Calendar.DAY_OF_YEAR)) "HH:mm" else "M月d日"
    return SimpleDateFormat(pattern, Locale.CHINA).apply { timeZone = zone }.format(date)
}
