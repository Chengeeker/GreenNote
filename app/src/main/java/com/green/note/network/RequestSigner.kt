package com.green.note.network

import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.encodeUtf8
import org.mindrot.jbcrypt.BCrypt

/** Wire-compatible port of the existing request signer. */
class RequestSigner(private val blob: ByteArray) {
    fun token(device: String, seconds: Long = System.currentTimeMillis() / 1000, appCode: Long = 2604201): String {
        check(blob.isNotEmpty()) { "缺少本地签名素材" }
        var lastError: IllegalArgumentException? = null
        for (offset in 0..15) {
            try { return tokenAt(device, seconds + offset, appCode) }
            catch (error: IllegalArgumentException) { lastError = error }
        }
        throw IllegalArgumentException("签名生成失败", lastError)
    }

    internal fun tokenAt(device: String, seconds: Long, appCode: Long = 2604201): String {
        val start = (((seconds + appCode) % 100) * 4 + 0x80).toInt()
        require(start >= 0 && start + 0x80 <= blob.size) { "签名素材片段越界" }
        val segment = blob.copyOfRange(start, start + 0x80).toString(Charsets.US_ASCII)
            .decodeBase64()?.utf8() ?: throw IllegalArgumentException("签名素材格式错误")
        val plain = "com.coolapk.market&$segment&${md5(device)}&$seconds&$appCode"
        val password = md5(plain.encodeUtf8().base64())
        val saltSource = "${seconds.toString(16)}/${md5(plain)}".encodeUtf8().base64().trimEnd('=')
        val prefix = saltSource.take(22)
        val shifted = prefix.dropLast(1) + BASE64[(BASE64.indexOf(prefix.last()) + 59) % 64]
        val salt = encodeSalt(decodeSalt(shifted))
        // jBCrypt implements the same ASCII-password algorithm using the 2a prefix.
        val hash = BCrypt.hashpw(password, "\$2a\$04\$$salt").replaceFirst("\$2a\$", "\$2y\$")
        return "v3" + hash.encodeUtf8().base64().trimEnd('=')
    }

    companion object {
        private const val BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        private const val BCRYPT = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        private fun md5(value: String) = value.encodeUtf8().md5().hex()

        private fun decodeSalt(value: String): ByteArray {
            var buffer = 0
            var bits = 0
            val output = ArrayList<Byte>()
            for (char in value) {
                val code = BCRYPT.indexOf(char)
                require(code >= 0) { "盐字符无效" }
                buffer = (buffer shl 6) or code
                bits += 6
                if (bits >= 8) {
                    bits -= 8
                    output.add((buffer shr bits).toByte())
                }
            }
            require(output.size == 16) { "盐长度无效" }
            return output.toByteArray()
        }

        private fun encodeSalt(value: ByteArray): String = buildString {
            var buffer = 0
            var bits = 0
            for (byte in value) {
                buffer = (buffer shl 8) or (byte.toInt() and 255)
                bits += 8
                while (bits >= 6) {
                    bits -= 6
                    append(BCRYPT[(buffer shr bits) and 63])
                }
            }
            if (bits > 0) append(BCRYPT[(buffer shl (6 - bits)) and 63])
        }
    }
}
