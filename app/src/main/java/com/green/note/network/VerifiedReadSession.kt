package com.green.note.network

import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Cookie
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okio.ByteString.Companion.encodeUtf8
import org.json.JSONObject

/** The account layer encrypts this opaque, bounded payload and atomically checks the owner. */
interface VerifiedReadSessionStore {
    suspend fun read(owner: ApiSession): String?
    suspend fun compareAndSet(owner: ApiSession, expected: String?, replacement: String?): Boolean
}

/** Only successful read verification is resumable; neither response bodies nor query proofs enter this state. */
internal class VerifiedReadSessions(
    private val currentOwner: () -> ApiSession,
    private val store: VerifiedReadSessionStore?,
    private val now: () -> Long,
) {
    private data class SessionCookie(val owner: ApiSession, val cookie: Cookie, val usableUntil: Long)
    internal class Accepted(
        val owner: ApiSession, val origin: HttpUrl, val context: String, val proof: String?,
        val issued: Long, val expires: Long, val encoded: String?,
    )
    internal class RequestState internal constructor(
        val context: String, val sessionValue: String?, val hasSessionOverride: Boolean,
        val proof: String?, internal val accepted: Accepted?, internal val observed: Accepted?,
    )
    private val lock = Any()
    private val storage = Mutex()
    private val cookies = mutableListOf<SessionCookie>()
    private var accepted: Accepted? = null
    private var loadedOwner: ApiSession? = null
    // Never rebase a failed CAS onto an unseen newer value: a late request must not delete or overwrite it.
    private var diskValue: String? = null
    private var diskKnown = false

    suspend fun restore(owner: ApiSession) {
        if (store != null && synchronized(lock) { loadedOwner != owner }) storage.withLock {
            if (synchronized(lock) { loadedOwner == owner }) return@withLock
            var known = true
            val raw = try { store.read(owner) } catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { known = false; null }
            if (owner != currentOwner()) return@withLock
            val restored = raw?.let { decode(it, owner) }
            synchronized(lock) {
                if (owner != currentOwner()) return@synchronized
                cookies.removeAll { it.owner != owner }
                accepted = null
                loadedOwner = owner; diskValue = raw; diskKnown = known
                if (restored != null) {
                    restored.second?.let { replaceCookie(it) }
                    if (contextLocked(owner, restored.first.origin) == restored.first.context) accepted = restored.first
                    else restored.second?.let { cookies.remove(it) }
                }
            }
            if (raw != null && synchronized(lock) { accepted == null }) writeLatestLocked(owner)
        }
        val expired = synchronized(lock) {
            val value = accepted
            if (value?.owner == owner && (now() < value.issued || now() >= value.expires)) {
                accepted = null; true
            } else false
        }
        if (expired) persist(owner)
    }

    fun context(owner: ApiSession, url: HttpUrl): String = synchronized(lock) { contextLocked(owner, url) }

    fun prepare(owner: ApiSession, url: HttpUrl, remember: Boolean, explicitProof: String?, verification: Boolean, read: Boolean): RequestState = synchronized(lock) {
        val context = contextLocked(owner, url)
        val cookie = if (remember) selectedCookie(owner, url) else null
        val valid = if (remember) accepted?.takeIf {
            it.owner == owner && it.context == context && now() >= it.issued && now() < it.expires
        } else null
        val proof = if (!read) null else explicitProof ?: if (verification) null else valid?.proof
        RequestState(context, cookie?.takeIf { now() < it.usableUntil }?.cookie?.value, cookie != null,
            proof, valid?.takeIf { proof == it.proof }, accepted)
    }

    /** Apply server cookies only if the request still owns the session it actually sent. */
    fun response(owner: ApiSession, url: HttpUrl, headers: Headers, sent: RequestState, remember: Boolean, verification: Boolean): String = synchronized(lock) {
        if (owner != currentOwner()) throw ApiException("账号或设备已变更，已忽略旧请求")
        val current = contextLocked(owner, url)
        if (verification && (current != sent.context || accepted !== sent.observed)) throw ApiException("账号、设备或验证会话已变更，请重新加载")
        if (current != sent.context || accepted !== sent.observed) return@synchronized sent.context
        if (remember) Cookie.parseAll(url, headers).filter { it.name == "SESSID" }.forEach { cookie ->
            replaceCookie(SessionCookie(owner, cookie, if (cookie.persistent) cookie.expiresAt else Long.MAX_VALUE))
        }
        contextLocked(owner, url)
    }

    suspend fun challenged(owner: ApiSession, sent: RequestState) {
        val changed = synchronized(lock) {
            if (sent.accepted != null && accepted === sent.accepted) { accepted = null; true } else false
        }
        if (changed) persist(owner)
    }

    suspend fun failed(owner: ApiSession, sent: RequestState) {
        val changed = synchronized(lock) {
            val previous = sent.observed
            // The failed request may belong to another host/path. Invalidate only if the cookies
            // that actually serve the verified origin have changed, not merely that request's jar.
            if (previous != null && previous.owner == owner && accepted === previous &&
                (contextLocked(owner, previous.origin) != previous.context ||
                (selectedCookie(owner, previous.origin)?.usableUntil ?: Long.MAX_VALUE) < previous.expires)) {
                accepted = null; true
            } else false
        }
        if (changed) persist(owner)
    }

    suspend fun succeeded(owner: ApiSession, url: HttpUrl, sent: RequestState, responseContext: String,
                          verification: Boolean, cookieProof: String?): Accepted? {
        var installed: Accepted? = null
        val changed = synchronized(lock) {
            if (owner != currentOwner() || responseContext != contextLocked(owner, url) || verification && accepted !== sent.observed) {
                if (verification) throw ApiException("账号、设备或会话已变更，已忽略旧验证结果")
                return@synchronized false
            }
            if (verification) {
                val issued = now()
                accepted = create(owner, url, responseContext, cookieProof, issued, issued + MAX_AGE).also { installed = it }
                true
            } else {
                val previous = sent.accepted
                val cookieDeadline = selectedCookie(owner, url)?.usableUntil ?: Long.MAX_VALUE
                if (previous != null && accepted === previous &&
                    (previous.context != responseContext || cookieDeadline < previous.expires) && now() < previous.expires) {
                    // A successful response may rotate its own session. Retain the original verification deadline.
                    accepted = create(owner, url, responseContext, previous.proof, previous.issued, previous.expires)
                    true
                } else false
            }
        }
        if (changed) persist(owner)
        return installed
    }

    fun owns(value: Accepted): Boolean = synchronized(lock) { accepted === value && value.owner == currentOwner() && value.context == contextLocked(value.owner, value.origin) }

    private fun selectedCookie(owner: ApiSession, url: HttpUrl): SessionCookie? {
        val matching = cookies.asReversed().filter { it.owner == owner && it.cookie.matches(url) }
        val valid = matching.filter { it.cookie.value.isNotEmpty() && now() < it.usableUntil }
        // A deleted narrow cookie does not hide an independently valid wider cookie. Keep a tombstone
        // only when there is no valid server cookie, so an old raw login SESSID cannot reappear.
        return (valid.ifEmpty { matching }).maxWithOrNull(compareBy<SessionCookie> { it.cookie.path.length }.thenBy { it.cookie.hostOnly })
    }

    private fun contextLocked(owner: ApiSession, url: HttpUrl): String {
        val selected = selectedCookie(owner, url)
        return JSONObject().put("owner", ownerHash(owner)).apply {
            if (selected == null) put("originHost", url.host)
            else put("session", JSONObject().put("value", selected.cookie.value).put("domain", selected.cookie.domain)
                .put("path", selected.cookie.path).put("hostOnly", selected.cookie.hostOnly)
                .put("secure", selected.cookie.secure).put("httpOnly", selected.cookie.httpOnly).put("persistent", selected.cookie.persistent))
                .put("usable", now() < selected.usableUntil)
        }.toString().encodeUtf8().sha256().hex()
    }

    private fun replaceCookie(value: SessionCookie) {
        cookies.removeAll { it.owner == value.owner && it.cookie.domain == value.cookie.domain && it.cookie.path == value.cookie.path }
        cookies.add(value)
        // These are only the two trusted API origins' SESSID cookies, not a general browser jar.
        while (cookies.size > 16) cookies.removeAt(0)
    }

    private fun create(owner: ApiSession, url: HttpUrl, context: String, proof: String?, issued: Long, expires: Long): Accepted {
        val origin = url.newBuilder().query(null).fragment(null).build()
        val cookie = selectedCookie(owner, url)?.takeIf { it.cookie.value.isNotEmpty() && now() < it.usableUntil }
        val deadline = minOf(expires, cookie?.usableUntil ?: expires)
        // Restoring an app session is bounded by this verification's original deadline, even when
        // the server's session cookie has no Expires/Max-Age. A query proof itself is never saved.
        val canPersist = proof != null || cookie != null
        val payload = if (canPersist && deadline > now()) JSONObject()
            .put("v", 1).put("id", UUID.randomUUID().toString()).put("owner", ownerHash(owner))
            .put("origin", origin.toString()).put("context", context).put("issued", issued).put("expires", deadline)
            .put("proof", proof ?: JSONObject.NULL).apply {
                cookie?.cookie?.let { value -> put("session", JSONObject().put("value", value.value)
                    .put("domain", value.domain).put("path", value.path).put("hostOnly", value.hostOnly)
                    .put("secure", value.secure).put("httpOnly", value.httpOnly).put("persistent", value.persistent)
                    .put("expires", if (value.persistent) value.expiresAt else JSONObject.NULL)) }
            }.toString().takeIf { it.length <= MAX_PAYLOAD } else null
        return Accepted(owner, origin, context, proof, issued, deadline, payload)
    }

    private fun decode(raw: String, owner: ApiSession): Pair<Accepted, SessionCookie?>? = runCatching {
        require(raw.length <= MAX_PAYLOAD)
        val root = JSONObject(raw)
        require(root.getInt("v") == 1 && root.getString("owner") == ownerHash(owner))
        val issued = root.getLong("issued"); val expires = root.getLong("expires")
        require(issued >= 0 && issued <= now() && expires > now() && expires > issued && expires - issued <= MAX_AGE)
        val origin = root.getString("origin").toHttpUrl()
        require(ApiRules.trusted(origin) && origin.query == null && origin.fragment == null && origin.encodedPath.length <= 1024)
        val context = root.getString("context")
        require(context.matches(Regex("[a-f0-9]{64}")))
        val proof = if (root.isNull("proof")) null else root.getString("proof").also {
            require(it.length <= 8205 && it.matches(Regex("NEC:[a-zA-Z0-9]{8}:[^\\s\\p{Cntrl}]+")))
        }
        val cookie = root.optJSONObject("session")?.let { saved ->
            val value = saved.getString("value"); val domain = saved.getString("domain"); val path = saved.getString("path")
            val hostOnly = saved.getBoolean("hostOnly"); val persistent = saved.getBoolean("persistent")
            require(value.isNotEmpty() && value.length <= 8192 && value.none { it.code < 33 || it.code == 127 || it == ';' })
            require(domain in setOf("coolapk.com", "api.coolapk.com", "api2.coolapk.com") && (!hostOnly || domain != "coolapk.com"))
            require(path.startsWith('/') && path.length <= 1024)
            val builder = Cookie.Builder().name("SESSID").value(value).path(path)
            if (hostOnly) builder.hostOnlyDomain(domain) else builder.domain(domain)
            if (saved.getBoolean("secure")) builder.secure()
            if (saved.getBoolean("httpOnly")) builder.httpOnly()
            if (persistent) builder.expiresAt(saved.getLong("expires").also { require(it >= expires) })
            val result = builder.build()
            require(result.matches(origin))
            SessionCookie(owner, result, minOf(expires, result.expiresAt))
        }
        require(proof != null || cookie != null)
        Accepted(owner, origin, context, proof, issued, expires, raw) to cookie
    }.getOrNull()

    private suspend fun persist(owner: ApiSession) {
        if (store == null) return
        storage.withLock { writeLatestLocked(owner) }
    }

    /** Called with the I/O mutex, never with the state monitor held across a suspension. */
    private suspend fun writeLatestLocked(owner: ApiSession) {
        val target = store ?: return
        while (true) {
            val desired = synchronized(lock) {
                if (owner != currentOwner() || loadedOwner != owner) return
                accepted?.takeIf { it.owner == owner && now() >= it.issued && now() < it.expires }?.encoded
            }
            if (desired == diskValue || !diskKnown && desired == null) return
            val expected = diskValue
            val updated = try { target.compareAndSet(owner, expected, desired) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { return }
            if (!updated) return
            diskValue = desired; diskKnown = true
            // If another verification completed while disk I/O was suspended, write only that latest state next.
        }
    }

    companion object {
        private const val MAX_AGE = 60 * 60 * 1000L
        private const val MAX_PAYLOAD = 24576
        private fun ownerHash(owner: ApiSession): String = JSONObject().put("device", owner.device)
            .put("cookie", owner.effectiveCookie).put("anonymous", owner.anonymous).put("revision", owner.revision)
            .toString().encodeUtf8().sha256().hex()
    }
}
