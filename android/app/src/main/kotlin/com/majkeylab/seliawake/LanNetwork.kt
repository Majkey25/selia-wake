package com.majkeylab.seliawake

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel

internal data class LanNetwork(val address: Inet4Address, val broadcast: Inet4Address)

internal object LanNetworks {
    private fun physical(context: Context): List<LanNetwork> {
        val manager = context.getSystemService(ConnectivityManager::class.java)
            ?: throw RelayFailure("wifi_unavailable")
        val preferred = manager.activeNetwork
        return manager.allNetworks.sortedBy { if (it == preferred) 0 else 1 }.flatMap { network ->
            val capabilities = manager.getNetworkCapabilities(network)
            if (capabilities == null || !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            ) {
                return@flatMap emptyList()
            }
            manager.getLinkProperties(network)?.linkAddresses.orEmpty().mapNotNull { link ->
                val address = link.address as? Inet4Address ?: return@mapNotNull null
                val prefix = link.prefixLength
                if (prefix !in 1..30 || address.isLoopbackAddress || address.isAnyLocalAddress ||
                    address.isMulticastAddress
                ) {
                    return@mapNotNull null
                }
                val ip = address.address.fold(0) { value, byte -> (value shl 8) or (byte.toInt() and 255) }
                val broadcast = ip or (-1 ushr prefix)
                val bytes = ByteArray(4) { (broadcast ushr (24 - it * 8)).toByte() }
                LanNetwork(address, InetAddress.getByAddress(bytes) as Inet4Address)
            }
        }
    }

    fun select(context: Context, target: WakeTarget, configuring: Boolean = false): LanNetwork {
        val networks = try {
            physical(context)
        } catch (_: Exception) {
            throw RelayFailure("wifi_unavailable")
        }
        if (networks.isEmpty()) throw RelayFailure("wifi_unavailable")
        return networks.firstOrNull { it.broadcast == target.broadcast }
            ?: throw RelayFailure(if (configuring) "invalid_request" else "wifi_unavailable")
    }

    fun info(context: Context): Map<String, String?> {
        val lan = physical(context).firstOrNull()
        val manager = context.getSystemService(ConnectivityManager::class.java)
            ?: throw RelayFailure("wifi_unavailable")
        val tailscale = manager.allNetworks.asSequence().filter { network ->
            manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }.flatMap { manager.getLinkProperties(it)?.linkAddresses.orEmpty().asSequence() }
            .mapNotNull { it.address as? Inet4Address }.firstOrNull { address ->
                val bytes = address.address
                // shortcut: VPN 100.64.0.0/10 is a Tailscale hint; replace when VPN identity is exposed.
                bytes[0].toInt() and 255 == 100 && bytes[1].toInt() and 192 == 64
            }
        return mapOf("wifiIp" to lan?.address?.hostAddress, "broadcast" to lan?.broadcast?.hostAddress,
            "tailscaleIp" to tailscale?.hostAddress)
    }

    fun send(context: Context, target: WakeTarget, channel: DatagramChannel) {
        val lan = select(context, target)
        try {
            channel.configureBlocking(false)
            val socket = channel.socket()
            socket.broadcast = true
            // Bind the LAN source address. Android VPNs can reject explicit Network.bindSocket.
            channel.bind(InetSocketAddress(lan.address, 0))
            val packet = target.packet()
            if (channel.send(ByteBuffer.wrap(packet), InetSocketAddress(target.broadcast, 9)) != packet.size) {
                throw RelayFailure("send_failed")
            }
        } catch (_: Exception) {
            throw RelayFailure("send_failed")
        }
    }
}
