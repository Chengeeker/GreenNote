package com.green.note

import androidx.compose.runtime.mutableStateListOf

internal data class IncomingLink(val sequence: Long, val url: String)

internal class IncomingLinks(restored: List<String> = emptyList()) {
    private val entries = mutableStateListOf<IncomingLink>()
    private var sequence = 0L
    val first: IncomingLink? get() = entries.firstOrNull()

    init {
        restored.forEach(::offer)
    }

    fun offer(url: String?) {
        if (url.isNullOrBlank() || url.length > 8192 || url.any { it.code < 32 } || entries.size >= 32) return
        entries.add(IncomingLink(sequence++, url))
    }

    fun consume(link: IncomingLink) {
        if (entries.firstOrNull() == link) entries.removeAt(0)
    }

    fun snapshot(): ArrayList<String> = ArrayList(entries.map { it.url })
}
