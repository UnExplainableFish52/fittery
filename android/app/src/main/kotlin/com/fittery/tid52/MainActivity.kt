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
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var battery: BatteryEngine
    private lateinit var network: NetworkMonitor
    private val chargingDashboardWindow by lazy { ChargingDashboardWindow(this) }
    private var permissionResult: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var toneResult: MethodChannel.Result? = null
    private var toneRequestCode: Int? = null
    private var toneEvent: AlertTone = AlertTone.CHARGE
    private val audioWorker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        battery = BatteryEngine.get(this)
        ChargingDreamService.syncAvailability(this)
        network = NetworkMonitor(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"fittery/battery").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "acknowledgeRelease" -> { battery.acknowledgeRelease(call.arguments as String); result.success(null) }
                    "backgroundAlerts" -> {
                        if (call.arguments == true) withNotifications(result) {
                            val previous = MonitorPreference.alertsEnabled(this)
                            MonitorPreference.setAlerts(this, true)
                            try { MonitorPreference.start(this) } catch (e: RuntimeException) { MonitorPreference.setAlerts(this, previous); throw e }
                        } else {
                            MonitorPreference.setAlerts(this, false)
                            battery.setBackgroundAlerts(false)
                            if (MonitorPreference.requested(this)) MonitorPreference.start(this) else stopService(Intent(this, MonitorService::class.java))
                            result.success(null)
                        }
                    }
                    "initial" -> result.success(battery.snapshot())
                    "screenSaverSettings" -> {
                        open(Intent(Settings.ACTION_DREAM_SETTINGS), Intent(Settings.ACTION_DISPLAY_SETTINGS))
                        result.success(null)
                    }
                    "chargingDashboardVisible" -> {
                        if (call.arguments == true) {
                            check(battery.settings()["chargingDashboard"] == true) { "Enable the charging dashboard in Settings first." }
                            check((battery.snapshot()["plugged"] as? Number)?.toInt()?.let { it > 0 } == true) { "Connect a charger to open the dashboard." }
                            chargingDashboardWindow.show()
                        } else chargingDashboardWindow.dismiss()
                        result.success(null)
                    }
                    "completeOnboarding" -> battery.completeOnboarding(call.argument<Boolean>("showOnLaunch")
                        ?: error("Missing welcome preference")) { state, error ->
                        if (error == null) result.success(state) else result.error("ONBOARDING", error, null)
                    }
                    "refresh" -> result.success(battery.refresh())
                    "dismissSessionPrompt" -> {
                        battery.dismissSessionPrompt((call.arguments as Number).toLong())
                        result.success(null)
                    }
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
                        if (needsNotifications) withNotifications(result) { battery.updateSetting(key, value); ChargingDreamService.syncAvailability(this) }
                        else { battery.updateSetting(key, value); ChargingDreamService.syncAvailability(this); result.success(null) }
                    }
                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(mapOf("version" to info.versionName, "build" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong(), "package" to packageName))
                    }
                    "history" -> battery.history { data, error -> if (error == null) result.success(data) else result.error("HISTORY",error,null) }
                    "recordings", "recordingDetail", "renameRecording", "deleteRecording" -> battery.monitorQuery(
                        call.method, call.argument<Number>("id")?.toLong(), call.argument<Number>("since")?.toLong(),
                        call.argument<Number>("until")?.toLong(), call.argument<Number>("before")?.toLong(), call.argument<String>("name")
                    ) { data, error -> if (error == null) result.success(data) else result.error("RECORDING", error, null) }
                    "currentHistory" -> battery.currentHistory(call.argument<Number>("since")?.toLong()) { data, error ->
                        if (error == null) result.success(data) else result.error("CURRENT_HISTORY",error,null)
                    }
                    "settings" -> {
                        @Suppress("UNCHECKED_CAST") val values = call.arguments as Map<String,Any?>
                        battery.saveSettings(values)
                        ChargingDreamService.syncAvailability(this)
                        result.success(null)
                    }
                    "monitoring" -> {
                        if (call.arguments == true) {
                            withNotifications(result) { startMonitor() }
                        } else {
                            MonitorPreference.set(this, false)
                            battery.stopMonitoring()
                            if (MonitorPreference.requested(this)) MonitorPreference.start(this) else stopService(Intent(this,MonitorService::class.java))
                            result.success(null)
                        }
                    }
                    "pickTone" -> {
                        if (toneResult != null) result.error("BUSY","Tone picker is already open.",null)
                        else {
                            toneEvent = AlertTone.from(call.argument<String>("event"))
                            val current = battery.settings()
                            val selected = when (toneEvent.source(current)) {
                                "silent" -> null
                                "bundled" -> RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                                else -> toneEvent.selectedUri(current)?.let(Uri::parse)
                            }
                            val pick = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                                putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,RingtoneManager.TYPE_ALARM)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE,toneEvent.title)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,true)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,selected)
                            }
                            toneResult = result
                            toneRequestCode = 102
                            Alerts.get(this).stopPreview()
                            try { startActivityForResult(pick,102) } catch (e: Exception) { toneResult = null; toneRequestCode = null; throw e }
                        }
                    }
                    "pickAudioFile" -> {
                        if (toneResult != null) result.error("BUSY", "An alarm tone picker is already open.", null)
                        else {
                            toneEvent = AlertTone.from(call.argument<String>("event"))
                            toneResult = result
                            toneRequestCode = 103
                            Alerts.get(this).stopPreview()
                            try { startActivityForResult(AlarmAudioFile.pickerIntent(), 103) }
                            catch (e: Exception) { toneResult = null; toneRequestCode = null; throw e }
                        }
                    }
                    "defaultTone" -> {
                        val tone = AlertTone.from(call.argument<String>("event"))
                        battery.updateTone(null, tone.title, "bundled", tone)
                        result.success(null)
                    }
                    "silentTone" -> {
                        battery.updateTone(null, "Silent", "silent", AlertTone.from(call.argument<String>("event")))
                        result.success(null)
                    }
                    "previewAlarm" -> result.success(Alerts.get(this).startPreview(battery.settings(), AlertTone.from(call.argument<String>("event"))))
                    "stopPreview" -> { Alerts.get(this).stopPreview(); result.success(false) }
                    "clearHistory" -> battery.clear { error -> if (error == null) result.success(null) else result.error("HISTORY",error,null) }
                    "notificationSettings" -> {
                        if (Build.VERSION.SDK_INT >= 26) {
                            open(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName))
                        } else {
                            open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    }
                    "batteryOptimization" -> {
                        open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
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
                battery.listener = {
                    if (chargingDashboardWindow.visible &&
                        ((it["plugged"] as? Number)?.toInt()?.let { value -> value > 0 } != true || battery.settings()["chargingDashboard"] != true)) {
                        chargingDashboardWindow.dismiss()
                    }
                    events.success(it)
                }
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
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,"fittery/current").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                battery.setCurrentListener { events.success(it) }
            }
            override fun onCancel(arguments: Any?) { battery.setCurrentListener(null) }
        })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,"fittery/preview").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val alerts = Alerts.get(this@MainActivity)
                alerts.previewListener = { events.success(it) }
                events.success(alerts.previewPlaying)
            }
            override fun onCancel(arguments: Any?) { Alerts.get(this@MainActivity).previewListener = null }
        })
        handleSessionIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSessionIntent(intent)
    }

    private fun handleSessionIntent(intent: Intent?) {
        if (!::battery.isInitialized || intent == null) return
        when (intent.action) {
            Alerts.ENABLE_MONITOR -> {
                val snapshot = battery.snapshot()
                if (!battery.monitoring && (snapshot["plugged"] as? Number)?.toInt()?.let { it > 0 } == true) battery.offerSessionPrompt("enableMonitor")
            }
            Alerts.OPEN_REPORT -> {
                val id = intent.getLongExtra("recordingId", -1)
                if (id > 0) battery.offerSessionPrompt("openReport", mapOf(
                    "recordingId" to id, "startTime" to intent.getLongExtra("startTime", 0), "endTime" to intent.getLongExtra("endTime", 0)
                ))
            }
            else -> return
        }
        intent.action = null
    }
    private fun withNotifications(result: MethodChannel.Result, action: () -> Unit) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (permissionResult != null) result.error("BUSY", "A notification request is already open.", null)
            else { permissionResult = result; permissionAction = action; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101) }
        } else { action(); result.success(null) }
    }
    private fun startMonitor() {
        val previous = MonitorPreference.enabled(this)
        MonitorPreference.set(this, true)
        try { MonitorPreference.start(this) }
        catch (e: RuntimeException) { MonitorPreference.set(this, previous); throw e }
    }

    private fun open(intent: Intent, fallback: Intent? = null) {
        try { startActivity(intent) } catch (e: android.content.ActivityNotFoundException) {
            startActivity(fallback ?: Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))
        }
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        chargingDashboardWindow.onWindowFocusChanged(hasFocus)
    }

    override fun onResume() {
        super.onResume()
        if (::battery.isInitialized) {
            battery.setForeground(true)
            if (MonitorPreference.requested(this) && (!battery.monitoring && MonitorPreference.enabled(this) || !battery.backgroundAlertsRunning && MonitorPreference.alertsEnabled(this))) {
                try { MonitorPreference.start(this) }
                catch (e: RuntimeException) { android.util.Log.w("Fittery", "Monitoring could not resume", e) }
            }
        }
        if (::network.isInitialized) network.setForeground(true)
    }
    override fun onPause() {
        Alerts.get(this).stopPreview()
        if (::network.isInitialized) network.setForeground(false)
        if (::battery.isInitialized) battery.setForeground(false)
        super.onPause()
    }
    override fun onDestroy() {
        chargingDashboardWindow.clear()
        Alerts.get(this).stopPreview()
        Alerts.get(this).previewListener = null
        if (::network.isInitialized) network.listen(null)
        if (::battery.isInitialized) {
            battery.setCurrentListener(null)
            battery.listener = null
        }
        permissionResult?.error("CANCELLED","Activity closed during permission request.",null); permissionResult = null
        permissionAction = null
        toneResult?.error("CANCELLED","Activity closed during tone selection.",null); toneResult = null
        toneRequestCode = null
        audioWorker.shutdown()
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
        if (requestCode != toneRequestCode) return
        val result = toneResult ?: return
        val event = toneEvent
        if (requestCode == 103) {
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                toneResult = null; toneRequestCode = null; result.success(null)
                return
            }
            val files = AlarmAudioFile(applicationContext)
            audioWorker.execute {
                try {
                    val selection = files.select(uri)
                    runOnUiThread {
                        if (toneResult !== result) {
                            files.releaseIfUnused(uri, battery.settings())
                            return@runOnUiThread
                        }
                        try {
                            battery.updateTone(selection.uri.toString(), selection.name, "file", event)
                            result.success(null)
                        } catch (e: Exception) {
                            files.releaseIfUnused(selection.uri, battery.settings())
                            result.error("AUDIO_FILE", e.message, null)
                        }
                        finally { toneResult = null; toneRequestCode = null }
                    }
                } catch (e: Exception) {
                    runOnUiThread {
                        if (toneResult === result) {
                            toneResult = null; toneRequestCode = null
                            result.error("AUDIO_FILE", e.message, null)
                        }
                    }
                }
            }
        } else if (requestCode == 102) {
            try {
                if (resultCode == RESULT_OK && data != null) {
                    @Suppress("DEPRECATION") val uri = data.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                    val title = uri?.let { RingtoneManager.getRingtone(this,it)?.getTitle(this) } ?: "Silent"
                    battery.updateTone(uri?.toString(),title, "system", event)
                }
                result.success(null)
            } catch (e: Exception) { result.error("TONE", e.message, null) }
            finally { toneResult = null; toneRequestCode = null }
        }
    }
}
