package com.majkeylab.seliawake

import android.os.SystemClock
import android.util.JsonReader
import android.util.JsonToken
import java.io.InputStream
import java.io.StringReader
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

internal data class WakeRequest(val timestamp: Long, val nonce: String, val signature: ByteArray)

internal object RelayHttp {
    private const val MAX_HEADERS = 4096
    private const val MAX_BODY = 1024

    fun read(socket: Socket): WakeRequest {
        val input = socket.getInputStream()
        var remaining = MAX_HEADERS
        fun line(): String {
            val text = StringBuilder()
            while (true) {
                if (--remaining < 0 || text.length > 1024) throw RelayFailure("invalid_request")
                val byte = input.read()
                if (byte == 13) {
                    if (--remaining < 0 || input.read() != 10) throw RelayFailure("invalid_request")
                    return text.toString()
                }
                if (byte !in 32..126 && byte != 9) throw RelayFailure("invalid_request")
                text.append(byte.toChar())
            }
        }
        val requestLine = line()
        if (requestLine != "POST /v1/wake HTTP/1.1" && requestLine != "POST /v1/wake HTTP/1.0") {
            throw RelayFailure("invalid_request")
        }
        val headers = mutableMapOf<String, String>()
        while (true) {
            val header = line()
            if (header.isEmpty()) break
            val colon = header.indexOf(':')
            if (headers.size >= 32 || colon <= 0 ||
                !header.substring(0, colon).matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+"))
            ) {
                throw RelayFailure("invalid_request")
            }
            val key = header.substring(0, colon).lowercase(Locale.ROOT)
            if (headers.put(key, header.substring(colon + 1).trim()) != null) {
                throw RelayFailure("invalid_request")
            }
        }
        val length = headers["content-length"]
        val contentType = headers["content-type"]?.lowercase(Locale.ROOT)
        if ("transfer-encoding" in headers || "expect" in headers ||
            (requestLine.endsWith("1.1") && headers["host"].isNullOrBlank()) ||
            length == null || !length.matches(Regex("[0-9]{1,4}")) ||
            contentType == null || !contentType.matches(Regex("application/json(?:\\s*;\\s*charset\\s*=\\s*(?:utf-8|\"utf-8\"))?"))
        ) {
            throw RelayFailure("invalid_request")
        }
        val size = length.toInt()
        if (size !in 1..MAX_BODY) throw RelayFailure("invalid_request")
        val body = ByteArray(size)
        readFully(input, body)
        return parse(body)
    }

    private fun readFully(input: InputStream, bytes: ByteArray) {
        var offset = 0
        while (offset < bytes.size) {
            val count = input.read(bytes, offset, bytes.size - offset)
            if (count <= 0) throw RelayFailure("invalid_request")
            offset += count
        }
    }

    private fun parse(bytes: ByteArray): WakeRequest {
        try {
            val body = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
            JsonReader(StringReader(body)).use { reader ->
                reader.isLenient = false
                reader.beginObject()
                val fields = mutableSetOf<String>()
                var timestamp: Long? = null
                var nonce: String? = null
                var signature: String? = null
                while (reader.hasNext()) {
                    val key = reader.nextName()
                    if (!fields.add(key)) throw RelayFailure("invalid_request")
                    when (key) {
                        "timestamp" -> {
                            if (reader.peek() != JsonToken.NUMBER) throw RelayFailure("invalid_request")
                            val value = reader.nextString()
                            if (!value.matches(Regex("-?(?:0|[1-9][0-9]*)"))) throw RelayFailure("invalid_request")
                            timestamp = value.toLongOrNull() ?: throw RelayFailure("invalid_request")
                        }
                        "nonce", "signature" -> {
                            if (reader.peek() != JsonToken.STRING) throw RelayFailure("invalid_request")
                            val value = reader.nextString()
                            if (key == "nonce") nonce = value else signature = value
                        }
                        else -> throw RelayFailure("invalid_request")
                    }
                }
                reader.endObject()
                if (reader.peek() != JsonToken.END_DOCUMENT) throw RelayFailure("invalid_request")
                val stamp = timestamp ?: throw RelayFailure("invalid_request")
                val token = nonce ?: throw RelayFailure("invalid_request")
                val signed = signature ?: throw RelayFailure("invalid_request")
                decodeBase64Url(token, 16)
                if (!signed.matches(Regex("[0-9a-f]{64}"))) throw RelayFailure("invalid_request")
                return WakeRequest(stamp, token, ByteArray(32) { signed.substring(it * 2, it * 2 + 2).toInt(16).toByte() })
            }
        } catch (failure: RelayFailure) {
            throw failure
        } catch (_: Exception) {
            throw RelayFailure("invalid_request")
        }
    }

    fun respond(socket: Socket, error: String?) {
        val status = when (error) {
            null -> "200 OK"
            "unauthorized", "expired" -> "401 Unauthorized"
            "replay" -> "409 Conflict"
            "rate_limited" -> "429 Too Many Requests"
            "wifi_unavailable" -> "503 Service Unavailable"
            "send_failed" -> "500 Internal Server Error"
            else -> "400 Bad Request"
        }
        val body = if (error == null) "{\"status\":\"sent\"}" else "{\"error\":\"$error\"}"
        val response = "HTTP/1.1 $status\r\nContent-Type: application/json\r\n" +
            "Content-Length: ${body.toByteArray(Charsets.UTF_8).size}\r\nConnection: close\r\n" +
            "Cache-Control: no-store\r\n\r\n$body"
        socket.getOutputStream().write(response.toByteArray(Charsets.UTF_8))
    }
}

internal class RelayGuard(
    private val secret: ByteArray,
    private val elapsedRealtime: () -> Long = SystemClock::elapsedRealtime,
    private val unixSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    private val nonces = LinkedHashMap<String, Long>()
    private var windowStart = elapsedRealtime()
    private var attempts = 0

    private fun admit() {
        val now = elapsedRealtime()
        if (now - windowStart >= 60_000) {
            windowStart = now
            attempts = 0
        }
        if (attempts >= 30) throw RelayFailure("rate_limited")
        attempts++
    }

    fun authorize(request: WakeRequest) {
        val nowSeconds = unixSeconds()
        if (request.timestamp < nowSeconds - 30 || request.timestamp > nowSeconds + 30) {
            throw RelayFailure("expired")
        }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val expected = mac.doFinal("${request.timestamp}\n${request.nonce}\nwake-v1".toByteArray(Charsets.UTF_8))
        if (!MessageDigest.isEqual(expected, request.signature)) throw RelayFailure("unauthorized")
        val now = elapsedRealtime()
        val iterator = nonces.entries.iterator()
        while (iterator.hasNext()) {
            if (iterator.next().value <= now) iterator.remove()
        }
        if (request.nonce in nonces) throw RelayFailure("replay")
        if (nonces.size >= 128) throw RelayFailure("rate_limited")
        admit()
        nonces[request.nonce] = now + maxOf(60_000L, (request.timestamp - nowSeconds + 31) * 1_000)
    }
}
