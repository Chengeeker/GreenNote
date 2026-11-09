package com.green.note.media

object MediaDirectories {
    fun sanitize(name: String?, fallback: String = "User"): String {
        val clean = name.orEmpty().trim().replace(Regex("[\\\\/:*?\"<>|\\r\\n]"), "_").replace(Regex("_+"), "_").trim()
        return if (clean.isEmpty() || clean == "." || clean == "..") fallback else clean.take(50).trim()
    }
    fun resolve(type: Int, nickname: String? = null, author: String? = null): String = when (type) {
        1 -> "GreenNote/${sanitize(nickname, "MyProfile")}"
        2 -> "GreenNote/${sanitize(author, "Unknown")}"
        else -> "GreenNote"
    }
}
