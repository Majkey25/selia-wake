package com.majkeylab.seliawake

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.ResultReceiver
import android.os.SystemClock
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.StandardProtocolFamily
import java.nio.channels.DatagramChannel
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit

class RelayService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val sockets = Any()
    @Volatile private var stopping = false
    @Volatile private var running = false
    @Volatile private var error: String? = null
    @Volatile private var port = RelayConfig.DEFAULT_PORT
    @Volatile private var worker: Thread? = null
    private var listener: ServerSocket? = null
    private var client: Socket? = null
    private var udp: DatagramChannel? = null
    private var deadline = Long.MAX_VALUE
    private var startReply: ResultReceiver? = null
    private var stopReply: ResultReceiver? = null

    override fun onCreate() {
        super.onCreate()
        active = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val receiver = intent?.receiver()
        if (intent?.action == ACTION_STOP) {
            if (stopReply != null) {
                reply(receiver, "invalid_request")
            } else {
                stopReply = receiver
                stopping = true
                running = false
                if (worker == null) finish()
            }
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START || worker != null || stopping) {
            reply(receiver, "invalid_request")
            if (worker == null) stopSelf()
            return START_NOT_STICKY
        }
        startReply = receiver
        var config: RelayConfig? = null
        try {
            config = RelayConfig.parse(mapOf(
                "mac" to intent.getStringExtra("mac"),
                "broadcast" to intent.getStringExtra("broadcast"),
                "secret" to intent.getStringExtra("secret"),
                "port" to intent.getIntExtra("port", 0),
                "name" to intent.getStringExtra("name"),
                "language" to intent.getStringExtra("language"),
            ))
            intent.removeExtra("secret")
            port = config.port
            val notification = notification(config, false)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            val readyConfig: RelayConfig = config
            worker = Thread({ serve(readyConfig) }, "selia-relay").also { it.start() }
        } catch (failure: Exception) {
            config?.secret?.fill(0)
            error = if (failure is RelayFailure) failure.code else "start_failed"
            finish()
        }
        return START_NOT_STICKY
    }

    private fun serve(config: RelayConfig) {
        val watchdog = ScheduledThreadPoolExecutor(1) { task -> Thread(task, "selia-relay-timeout") }
        var cpu: PowerManager.WakeLock? = null
        var wifi: WifiManager.WifiLock? = null
        try {
            watchdog.scheduleAtFixedRate({
                synchronized(sockets) {
                    if (stopping || SystemClock.elapsedRealtime() >= deadline) {
                        runCatching { client?.close() }
                        runCatching { udp?.close() }
                    }
                    if (stopping) runCatching { listener?.close() }
                }
            }, 0, 100, TimeUnit.MILLISECONDS)
            LanNetworks.select(this, config.target, configuring = true)
            val powerManager = getSystemService(PowerManager::class.java) ?: throw RelayFailure("start_failed")
            val cpuLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK, "$packageName:relay",
            )
            cpu = cpuLock
            cpuLock.setReferenceCounted(false)
            cpuLock.acquire()
            val wifiManager = applicationContext.getSystemService(WifiManager::class.java)
                ?: throw RelayFailure("wifi_unavailable")
            @Suppress("DEPRECATION")
            val wifiLock = wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF, "$packageName:relay",
            )
            wifi = wifiLock
            wifiLock.setReferenceCounted(false)
            wifiLock.acquire()
            val server = ServerSocket()
            synchronized(sockets) { listener = server }
            try {
                server.reuseAddress = true
                server.soTimeout = 1000
                // Wildcard includes loopback: Android Tailscale can forward authenticated requests there.
                server.bind(InetSocketAddress("0.0.0.0", config.port), 8)
            } catch (_: Exception) {
                throw RelayFailure("bind_failed")
            }
            if (stopping) return
            running = true
            error = null
            main.post {
                if (!stopping) {
                    try {
                        val manager = getSystemService(NotificationManager::class.java)
                            ?: throw RelayFailure("notification_permission_denied")
                        manager.notify(NOTIFICATION_ID, notification(config, true))
                        reply(startReply, null)
                        startReply = null
                    } catch (_: Exception) {
                        error = "notification_permission_denied"
                        stopping = true
                        running = false
                    }
                }
            }
            val guard = RelayGuard(config.secret)
            while (!stopping) {
                val connection = try {
                    server.accept()
                } catch (_: SocketTimeoutException) {
                    continue
                }
                connection.use connectionScope@{ socket ->
                    synchronized(sockets) {
                        deadline = SystemClock.elapsedRealtime() + 5000
                        client = socket
                    }
                    try {
                        socket.soTimeout = 1500
                        socket.tcpNoDelay = true
                        val requestError = try {
                            val request = RelayHttp.read(socket)
                            guard.authorize(request)
                            if (stopping) return@connectionScope
                            try {
                                DatagramChannel.open(StandardProtocolFamily.INET).use { channel ->
                                    synchronized(sockets) { udp = channel }
                                    if (stopping) return@connectionScope
                                    LanNetworks.send(this, config.target, channel)
                                }
                            } catch (failure: RelayFailure) {
                                throw failure
                            } catch (_: Exception) {
                                throw RelayFailure("send_failed")
                            }
                            error = null
                            null
                        } catch (failure: RelayFailure) {
                            if (failure.code == "wifi_unavailable" || failure.code == "send_failed") error = failure.code
                            failure.code
                        } catch (_: Exception) {
                            "invalid_request"
                        }
                        if (!stopping) RelayHttp.respond(socket, requestError)
                    } catch (_: Exception) {
                        // The watchdog also closes sockets whose reads or writes exceed the total deadline.
                    } finally {
                        synchronized(sockets) {
                            client = null
                            udp = null
                            deadline = Long.MAX_VALUE
                        }
                    }
                }
            }
        } catch (failure: Exception) {
            if (!stopping) error = if (failure is RelayFailure) failure.code else "relay_failed"
        } finally {
            running = false
            stopping = true
            synchronized(sockets) {
                runCatching { client?.close() }
                runCatching { udp?.close() }
                runCatching { listener?.close() }
                client = null
                udp = null
                listener = null
            }
            watchdog.shutdownNow()
            runCatching { wifi?.let { if (it.isHeld) it.release() } }
            runCatching { cpu?.let { if (it.isHeld) it.release() } }
            config.secret.fill(0)
            main.post { finish() }
        }
    }

    private fun notification(config: RelayConfig, ready: Boolean): Notification {
        val manager = getSystemService(NotificationManager::class.java)
            ?: throw RelayFailure("notification_permission_denied")
        if (!manager.areNotificationsEnabled() || (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
        ) {
            throw RelayFailure("notification_permission_denied")
        }
        val czech = config.language == "cs"
        val channelId = "relay_${config.language}"
        manager.createNotificationChannel(NotificationChannel(channelId,
            if (czech) "Relé Selia Wake" else "Selia Wake relay", NotificationManager.IMPORTANCE_LOW))
        if (manager.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) {
            throw RelayFailure("notification_permission_denied")
        }
        val stop = PendingIntent.getService(this, 1, Intent(this, RelayService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val text = if (!ready) {
            if (czech) "Spouštím relé…" else "Starting relay…"
        } else {
            if (czech) "Připraveno probudit ${config.name}. Port ${config.port}."
            else "Ready to wake ${config.name}. Listening on port ${config.port}."
        }
        return Notification.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_power_off)
            .setContentTitle(if (czech) "Selia Wake – relé" else "Selia Wake relay")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setDeleteIntent(stop)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_lock_power_off,
                if (czech) "Zastavit" else "Stop", stop).build())
            .build()
    }

    private fun finish() {
        running = false
        stopping = true
        reply(startReply, error ?: "start_cancelled")
        startReply = null
        reply(stopReply, null)
        stopReply = null
        lastError = error
        lastPort = port
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun reply(receiver: ResultReceiver?, failure: String?) {
        receiver?.send(if (failure == null) 0 else 1, Bundle().apply {
            putBoolean("running", isRunning())
            putString("error", failure)
            putInt("port", port)
        })
    }

    private fun isRunning(): Boolean = running && !stopping && worker?.isAlive == true &&
        synchronized(sockets) { listener?.isBound == true && listener?.isClosed == false }

    override fun onDestroy() {
        stopping = true
        running = false
        if (active === this) {
            active = null
            lastError = error
            lastPort = port
        }
        super.onDestroy()
    }

    companion object {
        internal const val ACTION_START = "com.majkeylab.seliawake.START_RELAY"
        internal const val ACTION_STOP = "com.majkeylab.seliawake.STOP_RELAY"
        internal const val EXTRA_REPLY = "reply"
        private const val NOTIFICATION_ID = 45879
        @Volatile private var active: RelayService? = null
        @Volatile private var lastError: String? = null
        @Volatile private var lastPort = RelayConfig.DEFAULT_PORT

        internal fun isPresent(): Boolean = active != null

        internal fun status(): Map<String, Any?> {
            val service = active
            return mapOf("running" to (service?.isRunning() == true),
                "error" to if (service != null) service.error else lastError,
                "port" to (service?.port ?: lastPort))
        }

        @Suppress("DEPRECATION")
        private fun Intent.receiver(): ResultReceiver? = if (Build.VERSION.SDK_INT >= 33) {
            getParcelableExtra(EXTRA_REPLY, ResultReceiver::class.java)
        } else {
            getParcelableExtra(EXTRA_REPLY)
        }
    }
}
