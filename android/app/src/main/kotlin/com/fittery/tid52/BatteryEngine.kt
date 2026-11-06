package com.fittery.tid52

import android.Manifest
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

class BatteryEngine internal constructor(private val context: Context) {
    companion object {
        @Volatile private var instance: BatteryEngine? = null
        fun get(context: Context): BatteryEngine = instance ?: synchronized(this) {
            instance ?: BatteryEngine(context.applicationContext).also { instance = it }
        }
    }
    val handler = Handler(Looper.getMainLooper())
    val worker = Executors.newSingleThreadExecutor()
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
    private val store by lazy { BatteryStore(context) }
    private val monitorStore by lazy { MonitorStore(context) }
    private val release = ReleasePreferences(context)
    private val onboarding by lazy { OnboardingPreferences(context) }
    private var intent: Intent? = null
    private var snapshotSource = "unavailable"
    private var lastLoggedSnapshot: String? = null
    private var readingSequence = 0L
    private var registered = false
    private var initialSnapshotAfterGap = false
    private var foreground = false
    private var dreaming = false
    internal var dreamListener: ((Map<String, Any?>) -> Unit)? = null
    var backgroundAlertsRunning = false
        private set
    fun setBackgroundAlerts(value: Boolean) { if (backgroundAlertsRunning == value) return; backgroundAlertsRunning = value; reconcile() }
    fun acknowledgeRelease(key: String) { release.acknowledge(key) }
    var monitoring = false
        private set
    var listener: ((Map<String, Any?>) -> Unit)? = null
    var serviceListener: ((Map<String, Any?>) -> Unit)? = null
    private var currentListener: ((Map<String, Any?>) -> Unit)? = null
    private var lastUiPublish = 0L
    private var lastUiState = ""
    private var currentGapPending = true
    private var lastCurrentPublish: Long? = null
    private val sampleIntervalMs: Long
        get() = if (foreground && currentListener != null) 1000 else 3000
    private var hardware = mapOf<String, Any?>()
    private var hardwareRequested = false
    private var lastRecord = 0L
    private var lastState = ""
    private var lastMonitorRecord = Long.MIN_VALUE
    private var lastMonitorState = ""
    private var alertMask = prefs.getInt("alertMask", 0) and prefs.getInt("activeAlarmMask", 0).inv()
    private var latest = mapOf<String, Any?>()
    private val chargeTimeEstimator = ChargeTimeEstimator()
    private val dischargeTimeEstimator = DischargeTimeEstimator()
    private val currentNormalizer = CurrentNormalizer(prefs.getFloat("currentDivisor", 1000f).toDouble(), prefs.getBoolean("currentInverted", false))
    private var historyFailure: String? = null
    private var monitorHistoryFailure: String? = null
    private var androidEtaValue: Long? = null
    private var androidEtaFinishAt = 0L
    private var currentMode: Pair<Double, Boolean>? = null
    private var observedPlugged: Boolean? = null
    private var promptSequence = 0L
    private var sessionPrompt: Map<String, Any?>? = null
    private val chargingConnection = ChargingConnection()
    private val appInfo by lazy { context.packageManager.getPackageInfo(context.packageName, 0) }

    private fun publishUi(reading: Map<String, Any?>) {
        listener?.invoke(reading)
        dreamListener?.invoke(reading)
    }

    internal fun setDreaming(value: Boolean) {
        if (dreaming == value) return
        dreaming = value
        reconcile()
    }

    fun offerSessionPrompt(kind: String, report: Map<String, Any?> = emptyMap(), publish: Boolean = true) {
        sessionPrompt = report + mapOf("kind" to kind, "token" to ++promptSequence)
        if (publish) publishUi(read())
    }

    fun dismissSessionPrompt(token: Long) {
        if ((sessionPrompt?.get("token") as? Number)?.toLong() == token) sessionPrompt = null
    }

    fun settings(): Map<String, Any?> {
        val json = JSONObject(prefs.getString("values", "{}") ?: "{}")
        val saved = json.keys().asSequence().associateWith { key -> json.get(key).let { if (it == JSONObject.NULL) null else it } }
        return AlertTone.migrate(mapOf("chargeAlert" to true, "chargeLimit" to 80, "heatAlert" to true, "heatLimit" to 38,
            "heatReminderMinutes" to 5, "lowAlert" to false, "lowLimit" to 20, "chargingDashboard" to release.dashboardDefault, "chargingScreenSaver" to false) + saved)
    }
    fun updateSetting(key: String, value: Any?) {
        val checked = SettingValidation.check(key, value, allowTone = false)
        if (key == "currentUnit" || key == "currentPolarity") {
            currentNormalizer.resetCalibration()
            prefs.edit().remove("currentDivisor").remove("currentInverted").apply()
        }
        val next = (settings() + (key to checked)).toMutableMap()
        if (key == "chargingDashboard" && checked == false) next["chargingScreenSaver"] = false
        if (key == "chargingScreenSaver" && checked == true) next["chargingDashboard"] = true
        saveSettings(next, key)
    }

    fun saveSettings(values: Map<String, Any?>, changedKey: String? = null) {
        values.forEach { (key, value) -> SettingValidation.check(key, value, allowTone = true) }
        val previous = settings()
        if (previous["heatLimit"] != values["heatLimit"] || values["heatAlert"] != true) clearTemperatureSnooze()
        alertMask = BatteryMath.rearmForSettings(alertMask, previous, values, changedKey)
        prefs.edit().putString("values", JSONObject(values).toString()).putInt("alertMask", alertMask).apply()
        if (previous["keepRecordings"] != values["keepRecordings"]) worker.execute { monitorStore.cleanup(values["keepRecordings"] == true, force = true) }
        if (AlertTone.entries.any { tone -> listOf("Uri", "Source").any { previous["${tone.key}Tone$it"] != values["${tone.key}Tone$it"] } } || (previous["sound"] != false) != (values["sound"] != false)) Alerts.existing()?.stopPreview()
        seedSnapshotIfNeeded()
        sample(false)
    }
    fun updateTone(uri: String?, name: String, source: String = "system", tone: AlertTone = AlertTone.CHARGE) {
        val previous = settings()
        val values = previous.toMutableMap().apply {
            put("${tone.key}ToneUri", uri); put("${tone.key}ToneName", name)
            put("${tone.key}ToneSource", if (uri == null && source != "bundled") "silent" else source)
        }
        saveSettings(values)
        AlarmAudioFile(context).releaseUnused(previous, values)
    }

    fun snapshot(): Map<String, Any?> {
        seedSnapshotIfNeeded()
        return read()
    }

    private fun seedSnapshotIfNeeded() {
        if (intent != null) return
        context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))?.takeIf(::isBatteryIntentForApp)?.let {
            intent = Intent(it)
            snapshotSource = "initial sticky broadcast"
        }
    }

    private fun isBatteryIntentForApp(received: Intent): Boolean =
        received.action == Intent.ACTION_BATTERY_CHANGED &&
            (received.`package` == null || received.`package` == context.packageName)

    private fun broadcastSequence(received: Intent?): Int? =
        received?.getIntExtra("seq", -1)?.takeIf { it >= 0 }

    private fun acceptBatteryIntent(received: Intent, initialSticky: Boolean, afterObservationGap: Boolean = false) {
        // Some devices replay sticky snapshots addressed to other packages.
        // They are not observations for this app, even if their sequence is high.
        if (!isBatteryIntentForApp(received)) return
        // AOSP attaches the optional "seq" update number to battery broadcasts.
        // Read the extra directly; no hidden API or reflection is required.
        val incoming = broadcastSequence(received)
        val current = broadcastSequence(intent)
        val newer = if (incoming != null && current != null) {
            if (incoming <= current) return
            true
        } else false
        // An actual initial callback may be newer than the cached query result.
        // Without sequence metadata, rebase only after we stopped observing,
        // or while startup still has only an unconfirmed sticky query.
        if (initialSticky && intent != null && snapshotSource != "initial sticky broadcast" && !newer && !afterObservationGap) return
        intent = Intent(received)
        snapshotSource = if (initialSticky) "initial receiver broadcast" else "live battery broadcast"
        if (!initialSticky) initialSnapshotAfterGap = false
    }

    internal fun receiveBatteryIntent(received: Intent, initialSticky: Boolean = false, afterObservationGap: Boolean = false) {
        val previous = intent
        acceptBatteryIntent(received, initialSticky, afterObservationGap)
        if (intent !== previous && !initialSticky &&
            previous?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) == 0 &&
            (intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) > 0) {
            chargingConnection.connected(System.currentTimeMillis(), SystemClock.elapsedRealtime())
        }
        sample(foreground || monitoring)
    }

    internal fun alarmSnapshot(received: Intent?, initialSticky: Boolean): Map<String, Any?> {
        if (received != null) acceptBatteryIntent(received, initialSticky)
        seedSnapshotIfNeeded()
        return read()
    }

    private fun alertReading(): Map<String, Any?> {
        seedSnapshotIfNeeded()
        val b = intent
        val raw = b?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = b?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status = when (b?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"
            BatteryManager.BATTERY_STATUS_FULL -> "Full"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "Discharging"
            else -> "Not charging"
        }
        return mapOf("time" to System.currentTimeMillis(), "level" to if (raw >= 0 && scale > 0) (100.0 * raw / scale).toInt().coerceIn(0, 100) else null,
            "plugged" to (b?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0), "status" to status,
            "temperatureC" to b?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)?.takeIf { it != Int.MIN_VALUE }?.div(10.0),
            "settings" to settings(), "monitoring" to monitoring, "monitoringEnabled" to MonitorPreference.enabled(context),
            "backgroundAlertsEnabled" to MonitorPreference.alertsEnabled(context), "backgroundAlertsRunning" to backgroundAlertsRunning,
            "releasePreferences" to release.state(), "alarmActive" to (Alerts.existing()?.alarmActive == true))
    }

    private fun read(): Map<String, Any?> {
        if (backgroundAlertsRunning && !foreground && !dreaming && !monitoring) return alertReading()

        val now = System.currentTimeMillis()
        val b = intent
        val settings = settings()
        val statusCode = b?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val status = when (statusCode) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "Discharging"
            BatteryManager.BATTERY_STATUS_FULL -> "Full"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Not charging"
            else -> "Unknown"
        }
        val plugged = b?.getIntExtra(BatteryManager.EXTRA_PLUGGED,0) ?: 0
        val elapsed = SystemClock.elapsedRealtime()
        val connectedDuration = chargingConnection.observe(plugged > 0, now, elapsed)
        val rawLevel = b?.getIntExtra(BatteryManager.EXTRA_LEVEL,-1) ?: -1
        val scale = b?.getIntExtra(BatteryManager.EXTRA_SCALE,100) ?: 100
        val level = if (rawLevel >= 0 && scale > 0) (100.0 * rawLevel / scale).toInt().coerceIn(0,100) else null
        val propertyLevel = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).takeIf { it in 0..100 }
        val broadcastSequence = broadcastSequence(b)
        val signature = "$snapshotSource/$broadcastSequence/$rawLevel/$scale/$statusCode/$plugged/$propertyLevel"
        if (signature != lastLoggedSnapshot) {
            lastLoggedSnapshot = signature
            android.util.Log.i("FitteryBattery", "source=$snapshotSource broadcastSequence=$broadcastSequence level=$level raw=$rawLevel/$scale status=$status plugged=$plugged capacityProperty=$propertyLevel")
        }
        val voltage = b?.getIntExtra(BatteryManager.EXTRA_VOLTAGE,0)?.takeIf { it > 0 }
        val temperature = b?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE,Int.MIN_VALUE)?.takeIf { it != Int.MIN_VALUE }?.div(10.0)
        val counter = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER).takeIf { it > 0 && it != Int.MAX_VALUE }?.div(1000.0)
        val rawCurrent = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        val normalized = currentNormalizer.normalize(now, rawCurrent, counter, plugged, settings["currentUnit"] as? String ?: "Auto", settings["currentPolarity"] as? String ?: "Auto")
        val mode = normalized.divisor to normalized.inverted
        if (currentMode != null && currentMode != mode) chargeTimeEstimator.forgetCurrentRates()
        currentMode = mode
        if (normalized.calibrated && (prefs.getFloat("currentDivisor", 1000f).toDouble() != currentNormalizer.divisor || prefs.getBoolean("currentInverted", false) != currentNormalizer.inverted)) {
            prefs.edit().putFloat("currentDivisor", currentNormalizer.divisor.toFloat()).putBoolean("currentInverted", currentNormalizer.inverted).apply()
        }
        val current = normalized.ma
        val power = BatteryMath.power(voltage,current)
        val health = when (b?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheating"
            BatteryManager.BATTERY_HEALTH_DEAD -> "Degraded"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Overvoltage"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Failure"
            BatteryManager.BATTERY_HEALTH_COLD -> "Cold"
            else -> "Unavailable"
        }
        val cycles = if (Build.VERSION.SDK_INT >= 34) b?.getIntExtra(BatteryManager.EXTRA_CYCLE_COUNT, -1)?.takeIf { it >= 0 } else null
        val fullCapacity = hardware["fullCapacityMah"] as? Double
        val healthEstimate = BatteryHealthEstimate.calculate(
            hardware["designCapacityMah"] as? Double, hardware["fullCapacityMah"] as? Double,
            hardware["capacityPairReliable"] == true
        )
        var remaining: Long? = null
        var remainingState = if (plugged > 0) "learning" else "unavailable"
        var remainingSource = if (plugged > 0) "Collecting recent net charging readings" else "Not enough data for an estimate"
        chargeTimeEstimator.observe(ChargeTimeEstimator.Sample(now, level, counter, plugged, plugged > 0 && status != "Full", current))
        if (plugged > 0 && status != "Full") {
            val design = hardware["designCapacityMah"] as? Double
            val gaugeCapacity = if (design != null && healthEstimate != null) design * healthEstimate.percent / 100 else null
            val eligibleFull = fullCapacity?.takeIf { design == null || it in design * .1..design * 1.2 }
            val estimate = chargeTimeEstimator.estimate(eligibleFull ?: gaugeCapacity ?: design)
            remaining = estimate?.millis
            if (estimate != null) { remainingSource = estimate.source; remainingState = "estimated" }
            else if (chargeTimeEstimator.recentMedianCurrent?.let { it <= 0 } == true) {
                remainingState = "notGaining"
                remainingSource = "Recent net current is not adding charge; the connected source may not cover phone use"
            } else if (Build.VERSION.SDK_INT >= 28 && chargeTimeEstimator.observedSeconds < 120 && current?.let { it > 0 } == true) {
                val reported = manager.computeChargeTimeRemaining().takeIf { it > 0 }
                if (reported != null) {
                    if (reported != androidEtaValue) { androidEtaValue = reported; androidEtaFinishAt = now + reported }
                    remaining = (androidEtaFinishAt - now).takeIf { it > 0 }
                    if (remaining != null) { remainingSource = "Android estimate; waiting for observed charging rate"; remainingState = "estimated" }
                }
            }
            if (remaining == null && remainingState == "learning" && chargeTimeEstimator.observedSeconds >= 120) {
                remainingState = "tooSlow"
                remainingSource = "No reliable positive progress yet; try a stronger power source or reduce phone use"
            }
        } else {
            androidEtaValue = null; androidEtaFinishAt = 0
        }
        val dischargeEstimate = dischargeTimeEstimator.estimate(SystemClock.elapsedRealtime(), plugged == 0 && status == "Discharging", counter, current, "${normalized.divisor}/${normalized.inverted}")
        if (plugged == 0 && status == "Discharging") {
            remaining = dischargeEstimate
            remainingState = if (remaining == null) "learning" else "estimated"
            remainingSource = if (remaining == null) "Learning recent battery use; at least 30 seconds of continuous readings needed" else "Based on recent average battery use; adapts as your usage changes"
        }
        if (status == "Full") { remaining = 0; remainingSource = "Battery is full"; remainingState = "full" }
        val result = mutableMapOf<String, Any?>(
            "time" to now, "sequence" to ++readingSequence, "level" to level, "status" to status, "plugged" to plugged,
            "elapsedRealtimeMs" to elapsed, "chargeConnectedAt" to chargingConnection.startedAt,
            "chargeConnectedDurationMs" to connectedDuration, "chargeConnectionConfirmed" to chargingConnection.confirmed,
            "appVersion" to appInfo.versionName,
            "appBuild" to (if (Build.VERSION.SDK_INT >= 28) appInfo.longVersionCode else @Suppress("DEPRECATION") appInfo.versionCode.toLong()),
            "batterySnapshotSource" to snapshotSource, "broadcastLevel" to rawLevel,
            "batteryBroadcastSequence" to broadcastSequence,
            "broadcastScale" to scale, "capacityProperty" to propertyLevel,
            "source" to when (plugged) { 1 -> "AC charger"; 2 -> "USB"; 4 -> "Wireless"; 8 -> "Dock"; 0 -> "Not plugged"; else -> "External power" },
            "voltageMv" to voltage, "currentMa" to current, "powerW" to power, "temperatureC" to temperature,
            "sampleIntervalMs" to sampleIntervalMs,
            "currentConvention" to "${normalized.divisor}/${normalized.inverted}",
            "rawCurrent" to rawCurrent.takeIf { it != Int.MIN_VALUE && it != Int.MAX_VALUE },
            "currentDivisor" to normalized.divisor, "currentInverted" to normalized.inverted,
            "currentCalibrated" to normalized.calibrated, "currentNote" to normalized.note,
            "chargeAlertLatched" to (alertMask and 1 != 0), "alarmActive" to (Alerts.existing()?.alarmActive == true),
            "health" to health, "healthPercent" to healthEstimate?.percent,
            "healthEstimateSource" to healthEstimate?.source, "healthEstimateRough" to healthEstimate?.rough,
            "cycles" to cycles, "technology" to b?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY),
            "model" to Build.MODEL, "manufacturer" to Build.MANUFACTURER, "board" to Build.BOARD,
            "chargeCounterMah" to counter, "remainingMs" to remaining, "remainingSource" to remainingSource,
            "remainingState" to remainingState, "chargeObservationSeconds" to chargeTimeEstimator.observedSeconds,
            "historyError" to (monitorHistoryFailure ?: historyFailure),
            "releasePreferences" to release.state(), "backgroundAlertsEnabled" to MonitorPreference.alertsEnabled(context), "backgroundAlertsRunning" to backgroundAlertsRunning, "monitoring" to monitoring, "monitoringEnabled" to MonitorPreference.enabled(context), "settings" to settings,
            "onboarding" to onboarding.snapshot(),
            "sessionPrompt" to sessionPrompt,
            "optimized" to (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(context.packageName),
            "notificationsAllowed" to (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
        )
        result.putAll(hardware)
        result["fullCapacityMah"] = fullCapacity
        result["fullCapacitySource"] = if (fullCapacity != null) "Hardware reported" else "Unavailable"
        if (cycles != null) result["cycles"] = cycles
        return result
    }

    fun setForeground(value: Boolean) {
        if (!value && !monitoring) currentGapPending = true
        foreground = value
        reconcile()
    }
    fun setCurrentListener(value: ((Map<String, Any?>) -> Unit)?) {
        currentListener = value
        lastCurrentPublish = null
        if (foreground) {
            handler.removeCallbacks(tick)
            sample(true)
            handler.postDelayed(tick, sampleIntervalMs)
        }
    }
    fun setMonitoring(value: Boolean) {
        if (value) {
            Alerts.existing()?.cancelMonitorReminder()
            if (sessionPrompt?.get("kind") == "enableMonitor") sessionPrompt = null
        }
        if (value && !monitoring) {
            lastMonitorRecord = Long.MIN_VALUE
            lastMonitorState = ""
            val time = System.currentTimeMillis()
            worker.execute { try { monitorStore.begin(time) } catch (e: Exception) { monitorFailure(e) } }
        }
        monitoring = value
        reconcile()
    }
    fun stopMonitoring() {
        if (!backgroundAlertsRunning) clearTemperatureSnooze()
        if (monitoring) sample(true)
        setMonitoring(false)
        val time = System.currentTimeMillis()
        worker.execute { try { monitorStore.finish(time) } catch (e: Exception) { monitorFailure(e) } }
    }
    private fun monitorFailure(e: Exception) {
        android.util.Log.e("Fittery", "Monitor recording failed", e)
        handler.post { monitorHistoryFailure = "Monitor recording could not be saved. Check device storage."; publishUi(read()) }
    }
    private fun reconcile() {
        if (foreground || dreaming || monitoring || backgroundAlertsRunning) {
            if (!registered) {
                val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED).apply {
                    addAction(Intent.ACTION_POWER_CONNECTED); addAction(Intent.ACTION_POWER_DISCONNECTED)
                }
                val registeredSnapshot = if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED) else context.registerReceiver(receiver, filter)
                if (intent == null && registeredSnapshot != null && isBatteryIntentForApp(registeredSnapshot)) {
                    intent = Intent(registeredSnapshot)
                    snapshotSource = "initial sticky broadcast"
                }
                registered = true
            }
            handler.removeCallbacks(tick)
            if (foreground || dreaming || monitoring) requestHardware()
            sample(foreground || monitoring)
            if (foreground || dreaming || monitoring) handler.postDelayed(tick, sampleIntervalMs)
        } else {
            if (registered) {
                context.unregisterReceiver(receiver)
                registered = false
                initialSnapshotAfterGap = true
                chargingConnection.reset()
            }
            handler.removeCallbacks(tick)
            worker.execute { store.endSession() }
        }
    }
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, received: Intent) {
            // Only this receiver's first valid callback can rebase an
            // unversioned snapshot after foreground-only observation paused.
            val afterGap = isInitialStickyBroadcast && initialSnapshotAfterGap
            if (isBatteryIntentForApp(received)) initialSnapshotAfterGap = false
            receiveBatteryIntent(received, isInitialStickyBroadcast, afterGap)
        }
    }
    private val tick = object : Runnable {
        override fun run() {
            if (!foreground && !dreaming && !monitoring) return
            sample(foreground || monitoring)
            handler.postDelayed(this, sampleIntervalMs)
        }
    }

    private fun sample(record: Boolean) {
        val reading = read().toMutableMap()
        val plugged = (reading["plugged"] as? Number)?.toInt()?.let { it > 0 } == true
        if (plugged && observedPlugged != true && foreground && !monitoring) {
            Alerts.get(context).monitorReminder(settings())
            offerSessionPrompt("enableMonitor", publish = false)
        }
        if (!plugged) {
            Alerts.existing()?.cancelMonitorReminder()
            if (sessionPrompt?.get("kind") == "enableMonitor") sessionPrompt = null
        }
        observedPlugged = plugged
        reading["sessionPrompt"] = sessionPrompt
        evaluateAlerts(reading)
        reading["chargeAlertLatched"] = alertMask and 1 != 0
        reading["alarmActive"] = Alerts.existing()?.alarmActive == true
        latest = reading
        // Scheduling must survive wall-clock corrections. Recorded timestamps
        // still use civil time, while cadence follows Android's elapsed clock.
        val now = SystemClock.elapsedRealtime()
        val state = "${reading["plugged"]}/${reading["status"]}/${reading["level"]}"
        val monitorState = "$state/${(reading["temperatureC"] as? Number)?.toDouble()?.let { it > 35 }}/${reading["currentConvention"]}/${settings()["dualCell"]}"
        if (record && monitoring && (lastMonitorRecord == Long.MIN_VALUE || now - lastMonitorRecord >= 3000 || monitorState != lastMonitorState)) {
            lastMonitorRecord = now; lastMonitorState = monitorState
            val options = settings()
            val multiplier = if (options["dualCell"] == true) 2 else 1
            val saved = reading.toMutableMap().apply {
                put("elapsed", now)
                put("convention", "${reading["currentConvention"]}/$multiplier")
                for (key in listOf("powerW", "voltageMv")) put(key, (reading[key] as? Number)?.toDouble()?.times(multiplier))
            }
            worker.execute {
                try {
                    val report = monitorStore.record(saved)
                    monitorStore.cleanup(options["keepRecordings"] == true)
                    handler.post {
                        monitorHistoryFailure = null
                        if (report != null) {
                            Alerts.get(context).chargingReport(report, options)
                            offerSessionPrompt("chargingReport", report)
                        }
                    }
                }
                catch (e: Exception) { monitorFailure(e) }
            }
        }
        // One-second chart events do not rebuild the dashboard or update the
        // foreground notification every second. Explicit refresh/settings and
        // battery state changes still publish immediately.
        val uiState = "$state/${reading["alarmActive"]}"
        if (currentListener == null || !record || now - lastUiPublish >= 3000 || uiState != lastUiState) {
            lastUiPublish = now; lastUiState = uiState
            publishUi(reading)
            serviceListener?.invoke(reading)
        }
        if (foreground && (!record || lastCurrentPublish == null || now - lastCurrentPublish!! >= 900)) currentListener?.let { send ->
            lastCurrentPublish = now
            send(mapOf(
                "time" to reading["time"], "currentMa" to reading["currentMa"],
                "voltageMv" to reading["voltageMv"], "sampleIntervalMs" to sampleIntervalMs,
                "currentConvention" to reading["currentConvention"],
                "rawCurrent" to reading["rawCurrent"],
                "gapBefore" to currentGapPending, "historyError" to historyFailure
            ))
            currentGapPending = false
        }
        if (record && (now - lastRecord >= sampleIntervalMs || state != lastState)) {
            lastRecord = now; lastState = state
            worker.execute {
                try {
                    store.record(reading)
                    handler.post { historyFailure = null }
                } catch (e: Exception) {
                    android.util.Log.e("Fittery", "History write failed", e)
                    handler.post {
                        historyFailure = "History could not be saved. Check available device storage."
                        publishUi(read())
                    }
                }
            }
        }
    }

    fun refresh(): Map<String, Any?> {
        // Compare sources for diagnosis, without assigning the query result to
        // the canonical live snapshot used by UI, alarms, and notifications.
        val queried = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        android.util.Log.i("FitteryBatteryRefresh", "cachedLevel=${intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)} queriedLevel=${queried?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)} queriedStatus=${queried?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)}")
        seedSnapshotIfNeeded()
        sample(false)
        return latest
    }

    private val bootCount: Int get() = android.provider.Settings.Global.getInt(context.contentResolver, android.provider.Settings.Global.BOOT_COUNT, 0)
    private fun clearTemperatureSnooze() { prefs.edit().remove("heatSnoozeUntil").remove("heatSnoozeBoot").apply() }
    fun snoozeTemperature() {
        if (Alerts.existing()?.temperatureActive != true) return
        val minutes = (settings()["heatReminderMinutes"] as? Number)?.toInt() ?: 5
        prefs.edit().putLong("heatSnoozeUntil", SystemClock.elapsedRealtime() + minutes * 60000L).putInt("heatSnoozeBoot", bootCount).apply()
    }

    private fun evaluateAlerts(r: Map<String, Any?>) {
        val s = settings()
        val temperature = (r["temperatureC"] as? Number)?.toDouble()
        val limit = (s["heatLimit"] as Number).toInt()
        val until = prefs.getLong("heatSnoozeUntil", 0)
        val newBoot = prefs.getInt("heatEpisodeBoot", -1) != bootCount
        if (newBoot || temperature != null && (temperature < limit - 2 || until > 0 && SystemClock.elapsedRealtime() >= until)) {
            alertMask = alertMask and 4.inv()
            clearTemperatureSnooze()
            prefs.edit().putInt("alertMask", alertMask).putInt("heatEpisodeBoot", bootCount).apply()
        }
        Alerts.existing()?.reconcile((r["plugged"] as Int) > 0, r["level"] as Int?, r["temperatureC"] as Double?, s)
        val (newMask, fired) = BatteryMath.alertMask(
            alertMask, (r["plugged"] as Int) > 0, r["status"] == "Charging" || (r["status"] == "Full" && (r["plugged"] as Int) > 0), r["level"] as Int?, r["temperatureC"] as Double?,
            s["chargeAlert"] == true, (s["chargeLimit"] as? Number)?.toInt() ?: 80,
            s["lowAlert"] == true, (s["lowLimit"] as? Number)?.toInt() ?: 20,
            s["heatAlert"] == true, (s["heatLimit"] as? Number)?.toInt() ?: 38
        )
        if (newMask != alertMask) { alertMask = newMask; prefs.edit().putInt("alertMask",alertMask).apply() }
        if (fired and 1 != 0) Alerts.get(context).notify(11, "Charging target reached", "Battery is at ${r["level"]}%. You can unplug your charger.", s)
        if (fired and 2 != 0) Alerts.get(context).notify(12, "Battery is running low", "Battery is at ${r["level"]}%. Connect a charger soon.", s)
        if (fired and 4 != 0) Alerts.get(context).notify(13, "Battery temperature is high", "Battery temperature is ${r["temperatureC"]}°C. Let your phone cool down.", s)
    }

    private fun requestHardware() {
        if (hardwareRequested) return
        hardwareRequested = true
        worker.execute {
            val values = BatteryHardwareValues.discover(
                read = { path -> try { File(path).takeIf { it.canRead() }?.readText()?.trim()?.toDoubleOrNull() } catch (_: Exception) { null } },
                profileCapacity = { DevicePowerProfile.batteryCapacity(context) }
            )
            android.util.Log.i("FitteryHardware", "Design capacity: ${values["designCapacityMah"] ?: "unavailable"} mAh (${values["designCapacitySource"] ?: "not exposed"})")
            val past = try { store.recentChargingSamples() } catch (_: Exception) { emptyList() }
            handler.post {
                hardware = values
                chargeTimeEstimator.restore(past)
                if (foreground || monitoring) sample(false)
            }
        }
    }

    fun history(callback: (Map<String, Any?>?, String?) -> Unit) {
        val recording = foreground || monitoring
        worker.execute {
            try { val data = store.history(recording); handler.post { callback(data,null) } }
            catch (e: Exception) { handler.post { callback(null,e.message) } }
        }
    }
    fun currentHistory(since: Long?, callback: (List<Map<String, Any?>>?, String?) -> Unit) {
        worker.execute {
            try { val data = store.currentHistory(since); handler.post { callback(data,null) } }
            catch (e: Exception) { handler.post { callback(null,e.message) } }
        }
    }

    fun completeOnboarding(showOnLaunch: Boolean, callback: (Map<String, Boolean>?, String?) -> Unit) {
        worker.execute {
            try {
                val state = onboarding.complete(showOnLaunch)
                handler.post { publishUi(read()); callback(state, null) }
            } catch (e: Exception) { handler.post { callback(null, e.message) } }
        }
    }
    fun clear(callback: (String?) -> Unit) {
        val resume = monitoring
        val time = System.currentTimeMillis()
        worker.execute {
            try { store.clear(); monitorStore.clear(); if (resume) monitorStore.begin(time); handler.post { lastMonitorRecord = Long.MIN_VALUE; lastRecord = 0; lastState = ""; sample(foreground || monitoring); callback(null) } }
            catch (e: Exception) { handler.post { callback(e.message) } }
        }
    }
    fun monitorQuery(operation: String, id: Long?, since: Long?, until: Long?, before: Long?, name: String?, callback: (Map<String, Any?>?, String?) -> Unit) {
        val keep = settings()["keepRecordings"] == true
        worker.execute {
            try {
                monitorStore.cleanup(keep, force = true)
                val result = when (operation) {
                    "recordings" -> monitorStore.list(since, until, before)
                    "recordingDetail" -> monitorStore.detail(requireNotNull(id), since, until)
                    "renameRecording" -> { monitorStore.rename(requireNotNull(id), requireNotNull(name)); emptyMap() }
                    "deleteRecording" -> { monitorStore.delete(requireNotNull(id)); emptyMap() }
                    else -> error("Unknown recording operation")
                }
                handler.post { callback(result, null) }
            } catch (e: Exception) { handler.post { callback(null, e.message) } }
        }
    }
}
