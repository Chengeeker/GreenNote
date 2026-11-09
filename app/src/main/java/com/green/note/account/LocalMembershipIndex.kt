package com.green.note.account

import org.json.JSONObject

/** One immutable local-state snapshot only; no per-card JSON parses or cached account objects. */
internal class LocalMembershipIndex(private val parse: (String) -> JSONObject = ::JSONObject) {
    private var source: String? = null
    private var entries: Map<String, Set<String>> = emptyMap()

    @Synchronized
    fun contains(state: AccountState, field: String, id: String): Boolean {
        require(field in FIELDS) { "未知的匿名账户列表" }
        if (!state.anonymous) {
            source = null
            entries = emptyMap()
            return false
        }
        if (source !== state.localJson) {
            // Canonical local JSON mirrors the active profile's three maps at the root.
            // A different snapshot also covers profile switches, import and rollback.
            val root = parse(state.localJson)
            val next = FIELDS.associateWith { key -> root.optJSONObject(key)?.keys()?.asSequence()?.toSet().orEmpty() }
            entries = next
            source = state.localJson
        }
        return id in entries.getValue(field)
    }

    private companion object { val FIELDS = setOf("favorites", "follows", "productFollows") }
}
