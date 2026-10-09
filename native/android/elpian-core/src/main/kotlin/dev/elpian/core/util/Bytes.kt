package dev.elpian.core.util

import java.util.Base64

object Bytes {
    fun utf8(text: String): ByteArray = text.toByteArray(Charsets.UTF_8)

    /** UTF-8 decode, malformed sequences → U+FFFD (`allowMalformed`). */
    fun utf8(bytes: ByteArray, offset: Int = 0, length: Int = bytes.size - offset): String = String(bytes, offset, length, Charsets.UTF_8)

    fun base64(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)

    /** Standard or URL-safe base64, whitespace and padding tolerated. */
    fun base64(text: String): ByteArray {
        val clean = text.replace(Regex("[\\s=]"), "").replace('-', '+').replace('_', '/')
        val padded = clean + "=".repeat((4 - clean.length % 4) % 4)
        return Base64.getDecoder().decode(padded)
    }
}
