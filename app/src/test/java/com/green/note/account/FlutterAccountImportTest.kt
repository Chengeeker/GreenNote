package com.green.note.account

import okio.ByteString.Companion.toByteString
import org.junit.Assert.*
import org.junit.Test
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class FlutterAccountImportTest {
    @Test fun readsBaselineIvPrefixedAesGcmWithoutChangingCiphertext() {
        val key = SecretKeySpec(ByteArray(16) { it.toByte() }, "AES")
        val iv = ByteArray(12) { (it + 4).toByte() }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        val bytes = iv + cipher.doFinal("uid=123; token=synthetic".toByteArray())
        val original = bytes.clone()
        assertEquals("uid=123; token=synthetic", FlutterAccountImport.decryptValue(bytes.toByteString().base64(), key))
        assertArrayEquals(original, bytes)
        bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { FlutterAccountImport.decryptValue(bytes.toByteString().base64(), key) }
    }
}
