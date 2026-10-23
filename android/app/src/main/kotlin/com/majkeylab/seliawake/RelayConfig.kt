package com.majkeylab.seliawake

import java.net.Inet4Address
import java.net.InetAddress
import java.util.Base64

internal class RelayFailure(val code: String) : Exception(code)

internal data class WakeTarget(val mac: ByteArray, val broadcast: Inet4Address) {
    fun packet(): ByteArray = ByteArray(102) { index ->
        if (index < 6) 0xff.toByte() else mac[(index - 6) % mac.size]
    }

    companion object {
        fun parse(mac: String, broadcast: String): WakeTarget {
            val compact = when {
                mac.matches(Regex("[0-9a-fA-F]{12}")) -> mac
                mac.matches(Regex("(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}")) -> mac.replace(":", "")
                mac.matches(Regex("(?:[0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}")) -> mac.replace("-", "")
                else -> throw RelayFailure("invalid_request")
            }
            val bytes = ByteArray(6) { compact.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
            if (bytes.all { it == 0.toByte() } || bytes[0].toInt() and 1 != 0) {
                throw RelayFailure("invalid_request")
            }
            val parts = broadcast.split('.')
            if (parts.size != 4 || parts.any { !it.matches(Regex("0|[1-9][0-9]{0,2}")) }) {
                throw RelayFailure("invalid_request")
            }
            val octets = parts.map { it.toInt() }
            if (octets.any { it > 255 } || octets[0] == 0 || octets[0] == 127 || octets[0] >= 224) {
                throw RelayFailure("invalid_request")
            }
            val address = InetAddress.getByAddress(ByteArray(4) { octets[it].toByte() }) as Inet4Address
            return WakeTarget(bytes, address)
        }
    }
}

internal data class RelayConfig(
    val target: WakeTarget,
    val secret: ByteArray,
    val port: Int,
    val name: String,
    val language: String,
) {
    companion object {
        const val DEFAULT_PORT = 45879

        fun parse(arguments: Map<*, *>): RelayConfig {
            if (arguments.keys != setOf("mac", "broadcast", "secret", "port", "name", "language")) {
                throw RelayFailure("invalid_request")
            }
            val port = when (val value = arguments["port"]) {
                is Int -> value.toLong()
                is Long -> value
                else -> throw RelayFailure("invalid_request")
            }
            val name = arguments.string("name")
            val language = arguments.string("language")
            if (port !in 1L..65535L || name.isBlank() || name.length > 128 ||
                name.any { it.isISOControl() } || language !in setOf("en", "cs")
            ) {
                throw RelayFailure("invalid_request")
            }
            return RelayConfig(
                WakeTarget.parse(arguments.string("mac"), arguments.string("broadcast")),
                decodeBase64Url(arguments.string("secret"), 32),
                port.toInt(), name, language,
            )
        }
    }
}

internal fun Map<*, *>.string(key: String): String =
    this[key] as? String ?: throw RelayFailure("invalid_request")

internal fun decodeBase64Url(value: String, size: Int): ByteArray {
    if (value.length != (size * 8 + 5) / 6 || !value.matches(Regex("[A-Za-z0-9_-]+"))) {
        throw RelayFailure("invalid_request")
    }
    val bytes = try {
        Base64.getUrlDecoder().decode(value)
    } catch (_: IllegalArgumentException) {
        throw RelayFailure("invalid_request")
    }
    if (bytes.size != size || Base64.getUrlEncoder().withoutPadding().encodeToString(bytes) != value) {
        throw RelayFailure("invalid_request")
    }
    return bytes
}
