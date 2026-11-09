package com.green.note.content

/** Stop before parsing/layout: retain complete inline tags and entities in a bounded list preview. */
internal fun clipContentPreview(raw: String, maxVisible: Int = 1000): String {
    if (maxVisible <= 0) return ""
    if (raw.length <= maxVisible) return raw
    val out = StringBuilder(); var offset = 0; var visible = 0; var anchor = false
    while (offset < raw.length && visible < maxVisible && out.length < 16_384) {
        if (raw[offset] == '<') {
            val end = raw.indexOf('>', offset + 1)
            if (end in (offset + 1)..minOf(raw.lastIndex, offset + 4096)) {
                val tag = raw.substring(offset, end + 1)
                val name = Regex("^</?([A-Za-z][A-Za-z0-9]*)").find(tag)?.groupValues?.get(1)?.lowercase()
                if (name == "script" || name == "style") {
                    val close = raw.indexOf("</$name", end + 1, ignoreCase = true)
                    offset = if (close < 0) raw.length else raw.indexOf('>', close).let { if (it < 0) raw.length else it + 1 }; continue
                }
                if (name != null) {
                    when (name) {
                        "a" -> { anchor = !tag.startsWith("</"); out.append(tag) }
                        "p", "br" -> { out.append('\n'); visible++ }
                        "img" -> Regex("alt=[\"'](\\[[^\\]]+])[\"']", RegexOption.IGNORE_CASE).find(tag)?.groupValues?.get(1)?.let { out.append(it); visible++ }
                    }
                    offset = end + 1; continue
                }
            }
        }
        if (raw[offset] == '&') {
            val end = raw.indexOf(';', offset + 1)
            if (end in (offset + 1)..minOf(raw.lastIndex, offset + 12)) { out.append(raw, offset, end + 1); offset = end + 1; visible++; continue }
        }
        val size = if (Character.isHighSurrogate(raw[offset]) && offset + 1 < raw.length && Character.isLowSurrogate(raw[offset + 1])) 2 else 1
        out.append(raw, offset, offset + size); offset += size; visible++
    }
    if (anchor) out.append("</a>")
    return out.toString()
}
