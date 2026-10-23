package com.majkeylab.seliawake

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.StandardProtocolFamily
import java.nio.channels.DatagramChannel
import java.util.Base64
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val io = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, ArrayBlockingQueue(4),
        { task -> Thread(task, "selia-channel") }, ThreadPoolExecutor.AbortPolicy())
        .apply { allowCoreThreadTimeOut(true) }
    private var channel: MethodChannel? = null
    private var attached = false
    private var controlBusy = false
    private class PermissionRequest(
        val permissions: Array<String>,
        val result: MethodChannel.Result,
        val action: () -> Unit,
        val cancel: () -> Unit,
    )
    private var pendingPermission: PermissionRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        attached = true
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "selia_wake/relay").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(RelayService.status())
                        "start" -> {
                            if (controlBusy) throw RelayFailure("invalid_request")
                            val config = RelayConfig.parse(call.arguments as? Map<*, *>
                                ?: throw RelayFailure("invalid_request"))
                            controlBusy = true
                            withPermissions(result, notification = true, cancel = {
                                config.secret.fill(0)
                                controlBusy = false
                            }) {
                                startRelay(config, result)
                            }
                        }
                        "stop" -> {
                            if (controlBusy) throw RelayFailure("invalid_request")
                            if (!RelayService.isPresent()) {
                                result.success(RelayService.status())
                            } else {
                                controlBusy = true
                                dispatch(Intent(this@MainActivity, RelayService::class.java)
                                    .setAction(RelayService.ACTION_STOP), result, foreground = false)
                            }
                        }
                        "wakeLocal" -> {
                            val arguments = call.arguments as? Map<*, *> ?: throw RelayFailure("invalid_request")
                            if (arguments.keys != setOf("mac", "broadcast")) throw RelayFailure("invalid_request")
                            val target = WakeTarget.parse(arguments.string("mac"), arguments.string("broadcast"))
                            withPermissions(result) {
                                execute(result) {
                                    LanNetworks.select(applicationContext, target, configuring = true)
                                    try {
                                        DatagramChannel.open(StandardProtocolFamily.INET).use {
                                            LanNetworks.send(applicationContext, target, it)
                                        }
                                    } catch (failure: RelayFailure) {
                                        throw failure
                                    } catch (_: Exception) {
                                        throw RelayFailure("send_failed")
                                    }
                                    mapOf("status" to "sent")
                                }
                            }
                        }
                        "networkInfo" -> execute(result) { LanNetworks.info(applicationContext) }
                        else -> result.notImplemented()
                    }
                } catch (failure: Exception) {
                    result.error(if (failure is RelayFailure) failure.code else "native_error",
                        if (failure is RelayFailure) failure.code else "Native relay operation failed", null)
                }
            }
        }
    }

    private fun startRelay(config: RelayConfig, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, RelayService::class.java).setAction(RelayService.ACTION_START)
                .putExtra("mac", config.target.mac.joinToString(":") { "%02x".format(it.toInt() and 255) })
                .putExtra("broadcast", config.target.broadcast.hostAddress)
                .putExtra("secret", Base64.getUrlEncoder().withoutPadding().encodeToString(config.secret))
                .putExtra("port", config.port)
                .putExtra("name", config.name)
                .putExtra("language", config.language)
            dispatch(intent, result, foreground = true)
        } finally {
            config.secret.fill(0)
        }
    }

    private fun dispatch(intent: Intent, result: MethodChannel.Result, foreground: Boolean) {
        var completed = false
        val timeout = Runnable {
            if (!completed) {
                completed = true
                controlBusy = false
                if (attached) result.error("service_timeout", "The relay service did not respond", null)
            }
        }
        val receiver = object : ResultReceiver(main) {
            override fun onReceiveResult(resultCode: Int, data: Bundle?) {
                if (completed) return
                completed = true
                controlBusy = false
                main.removeCallbacks(timeout)
                if (!attached) return
                if (resultCode == 0 && data != null) {
                    result.success(mapOf("running" to data.getBoolean("running"),
                        "error" to data.getString("error"), "port" to data.getInt("port")))
                } else {
                    val error = data?.getString("error") ?: "service_failed"
                    result.error(error, error, null)
                }
            }
        }
        intent.putExtra(RelayService.EXTRA_REPLY, receiver)
        main.postDelayed(timeout, 10_000)
        try {
            if (foreground) startForegroundService(intent) else startService(intent)
        } catch (_: Exception) {
            completed = true
            controlBusy = false
            main.removeCallbacks(timeout)
            if (attached) result.error("service_failed", "The relay service could not be started", null)
        }
    }

    private fun execute(result: MethodChannel.Result, task: () -> Any?) {
        try {
            io.execute {
                try {
                    val value = task()
                    main.post { if (attached) result.success(value) }
                } catch (failure: Exception) {
                    val code = if (failure is RelayFailure) failure.code else "wifi_unavailable"
                    main.post { if (attached) result.error(code, code, null) }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("rate_limited", "Too many native operations", null)
        }
    }

    private fun withPermissions(
        result: MethodChannel.Result,
        notification: Boolean = false,
        cancel: () -> Unit = {},
        action: () -> Unit,
    ) {
        val required = mutableListOf<String>()
        if (notification && Build.VERSION.SDK_INT >= 33) required.add(Manifest.permission.POST_NOTIFICATIONS)
        // Android 16's opt-in LAN protection uses the Nearby devices runtime permission.
        if (Build.VERSION.SDK_INT >= 36) required.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        val missing = required.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.toTypedArray()
        try {
            if (missing.isEmpty()) {
                action()
            } else {
                if (pendingPermission != null) throw RelayFailure("rate_limited")
                pendingPermission = PermissionRequest(missing, result, action, cancel)
                try {
                    requestPermissions(missing, RELAY_PERMISSIONS)
                } catch (failure: Exception) {
                    pendingPermission = null
                    throw failure
                }
            }
        } catch (failure: Exception) {
            cancel()
            throw failure
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != RELAY_PERMISSIONS) return
        val pending = pendingPermission ?: return
        pendingPermission = null
        if (pending.permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            try {
                pending.action()
            } catch (_: Exception) {
                pending.cancel()
                pending.result.error("native_error", "Native relay operation failed", null)
            }
        } else {
            pending.cancel()
            val notificationDenied = Build.VERSION.SDK_INT >= 33 &&
                Manifest.permission.POST_NOTIFICATIONS in pending.permissions &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            val code = if (notificationDenied) "notification_permission_denied" else "local_network_permission_denied"
            pending.result.error(code, code, null)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        attached = false
        channel?.setMethodCallHandler(null)
        channel = null
        pendingPermission?.cancel?.invoke()
        pendingPermission = null
        io.shutdownNow()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        private const val RELAY_PERMISSIONS = 45879
    }
}
