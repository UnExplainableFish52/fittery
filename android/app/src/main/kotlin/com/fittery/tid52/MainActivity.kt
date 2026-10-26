package com.fittery.tid52

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var battery: BatteryEngine
    private lateinit var network: NetworkMonitor
    private var permissionResult: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var toneResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        battery = BatteryEngine.get(this)
        network = NetworkMonitor(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"fittery/battery").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initial" -> result.success(battery.snapshot())
                    "refresh" -> result.success(battery.refresh())
                    "deviceInfo" -> battery.worker.execute {
                        try {
                            val info = DeviceInfo.read(applicationContext)
                            runOnUiThread { result.success(info) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DEVICE_INFO", e.message, null) }
                        }
                    }
                    "updateSetting" -> {
                        val key = call.argument<String>("key") ?: error("Missing setting key")
                        val value = call.argument<Any?>("value")
                        val alert = when (key) { "chargeLimit" -> "chargeAlert"; "lowLimit" -> "lowAlert"; "heatLimit" -> "heatAlert"; else -> key }
                        val needsNotifications = alert in setOf("chargeAlert", "lowAlert", "heatAlert") && (if (key == alert) value == true else battery.settings()[alert] == true)
                        if (needsNotifications) withNotifications(result) { battery.updateSetting(key, value) }
                        else { battery.updateSetting(key, value); result.success(null) }
                    }
                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(mapOf("version" to info.versionName, "build" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong(), "package" to packageName))
                    }
                    "history" -> battery.history { data, error -> if (error == null) result.success(data) else result.error("HISTORY",error,null) }
                    "settings" -> {
                        @Suppress("UNCHECKED_CAST") val values = call.arguments as Map<String,Any?>
                        battery.saveSettings(values)
                        result.success(null)
                    }
                    "monitoring" -> {
                        if (call.arguments == true) {
                            withNotifications(result) { startMonitor() }
                        } else {
                            stopService(Intent(this,MonitorService::class.java))
                            battery.setMonitoring(false)
                            result.success(null)
                        }
                    }
                    "pickTone" -> {
                        if (toneResult != null) result.error("BUSY","Tone picker is already open.",null)
                        else {
                            val selected = battery.settings()["toneUri"] as? String
                            val pick = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                                putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,RingtoneManager.TYPE_ALARM)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE,"Battery alarm tone")
                                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,true)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,selected?.let(Uri::parse) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                            }
                            toneResult = result
                            try { startActivityForResult(pick,102) } catch (e: Exception) { toneResult = null; throw e }
                        }
                    }
                    "previewAlarm" -> result.success(Alerts.get(this).startPreview(battery.settings()))
                    "stopPreview" -> { Alerts.get(this).stopPreview(); result.success(false) }
                    "clearHistory" -> battery.clear { error -> if (error == null) result.success(null) else result.error("HISTORY",error,null) }
                    "notificationSettings" -> {
                        open(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName))
                        result.success(null)
                    }
                    "batteryOptimization" -> {
                        open(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,Uri.parse("package:$packageName")),Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    "appSettings" -> { open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName"))); result.success(null) }
                    "openLink" -> {
                        val uri = Uri.parse(call.arguments as String)
                        require(uri.scheme == "https" && !uri.host.isNullOrBlank()) { "A valid HTTPS link is required." }
                        startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("ANDROID",e.message,null) }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,"fittery/readings").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                battery.listener = { events.success(it) }
                events.success(battery.snapshot())
            }
            override fun onCancel(arguments: Any?) { battery.listener = null }
        })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,"fittery/network").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                network.listen { events.success(it) }
            }
            override fun onCancel(arguments: Any?) { network.listen(null) }
        })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,"fittery/preview").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val alerts = Alerts.get(this@MainActivity)
                alerts.previewListener = { events.success(it) }
                events.success(alerts.previewPlaying)
            }
            override fun onCancel(arguments: Any?) { Alerts.get(this@MainActivity).previewListener = null }
        })
    }
    private fun withNotifications(result: MethodChannel.Result, action: () -> Unit) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (permissionResult != null) result.error("BUSY", "A notification request is already open.", null)
            else { permissionResult = result; permissionAction = action; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101) }
        } else { action(); result.success(null) }
    }
    private fun startMonitor() {
        val intent = Intent(this,MonitorService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        // Reflect the request immediately; onCreate confirms it with a live update.
        battery.setMonitoring(true)
    }
    private fun open(intent: Intent, fallback: Intent? = null) {
        try { startActivity(intent) } catch (e: android.content.ActivityNotFoundException) {
            startActivity(fallback ?: Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))
        }
    }
    override fun onResume() {
        super.onResume()
        if (::battery.isInitialized) battery.setForeground(true)
        if (::network.isInitialized) network.setForeground(true)
    }
    override fun onPause() {
        Alerts.get(this).stopPreview()
        if (::network.isInitialized) network.setForeground(false)
        if (::battery.isInitialized) battery.setForeground(false)
        super.onPause()
    }
    override fun onDestroy() {
        Alerts.get(this).stopPreview()
        Alerts.get(this).previewListener = null
        if (::network.isInitialized) network.listen(null)
        if (::battery.isInitialized) {
            battery.listener = null
        }
        permissionResult?.error("CANCELLED","Activity closed during permission request.",null); permissionResult = null
        permissionAction = null
        toneResult?.error("CANCELLED","Activity closed during tone selection.",null); toneResult = null
        super.onDestroy()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if (requestCode == 101) {
            val result = permissionResult; permissionResult = null
            val action = permissionAction; permissionAction = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                try { action?.invoke(); result?.success(null) } catch (e: Exception) { result?.error("ANDROID",e.message,null) }
            } else result?.error("NOTIFICATIONS","Allow notifications in Settings so Fittery can show battery alerts.",null)
        }
    }
    @Deprecated("Android activity result bridge for the system ringtone picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if (requestCode == 102) {
            if (resultCode == RESULT_OK && data != null) {
                @Suppress("DEPRECATION") val uri = data.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                val title = uri?.let { RingtoneManager.getRingtone(this,it)?.getTitle(this) } ?: "Silent"
                battery.updateTone(uri?.toString(),title)
            }
            toneResult?.success(null); toneResult = null
        }
    }
}
