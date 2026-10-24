package com.majkeylab.seliawake

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class RelayGuardTest {
    private val secret = ByteArray(32) { it.toByte() }
    private val nonce = "AAECAwQFBgcICQoLDA0ODw"

    private fun request(timestamp: Long): WakeRequest {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val signature = mac.doFinal("$timestamp\n$nonce\nwake-v1".toByteArray(Charsets.UTF_8))
        return WakeRequest(timestamp, nonce, signature)
    }

    @Test
    fun replayAtFinalFreshSecond() {
        var seconds = 1_800_000_000L
        var elapsed = 0L
        val guard = RelayGuard(secret, { elapsed }, { seconds })
        val body = request(seconds + 30)
        guard.authorize(body)
        seconds += 60
        elapsed += 60_000
        assertEquals("replay", assertThrows(RelayFailure::class.java) { guard.authorize(body) }.message)
        seconds++
        elapsed += 1_000
        assertEquals("expired", assertThrows(RelayFailure::class.java) { guard.authorize(body) }.message)
        guard.authorize(request(seconds))
    }

    @Test
    fun newRequestCanReuseNonceAfterMinimumTtl() {
        var seconds = 1_800_000_000L
        var elapsed = 0L
        val guard = RelayGuard(secret, { elapsed }, { seconds })
        guard.authorize(request(seconds))
        seconds += 60
        elapsed += 60_000
        guard.authorize(request(seconds))
    }
}
