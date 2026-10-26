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
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.abs

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
    private var intent: Intent? = null
    private var snapshotSource = "unavailable"
    private var lastLoggedSnapshot: String? = null
    private var readingSequence = 0L
    private var registered = false
    private var initialSnapshotAfterGap = false
    private var foreground = false
    var monitoring = false
        private set
    var listener: ((Map<String, Any?>) -> Unit)? = null
    var serviceListener: ((Map<String, Any?>) -> Unit)? = null
    private var hardware = mapOf<String, Any?>()
    private var hardwareRequested = false
    private var lastRecord = 0L
    private var lastState = ""
    private var alertMask = prefs.getInt("alertMask", 0)
    private var latest = mapOf<String, Any?>()
    private var chargeStartCounter: Double? = null
    private var chargeStartLevel: Int? = null
    private val chargeTimeEstimator = ChargeTimeEstimator()
    private val currentNormalizer = CurrentNormalizer(prefs.getFloat("currentDivisor", 1000f).toDouble(), prefs.getBoolean("currentInverted", false))
    private var historyFailure: String? = null
    private var androidEtaValue: Long? = null
    private var androidEtaFinishAt = 0L
    private var currentMode: Pair<Double, Boolean>? = null

    fun settings(): Map<String, Any?> {
        val json = JSONObject(prefs.getString("values", "{}") ?: "{}")
        return json.keys().asSequence().associateWith { key -> json.get(key).let { if (it == JSONObject.NULL) null else it } }
    }
    fun updateSetting(key: String, value: Any?) {
        require(key in setOf("theme","fahrenheit","millivolts","dualCell","currentUnit","currentPolarity","chargeAlert","chargeLimit","lowAlert","lowLimit","heatAlert","heatLimit","sound","lockScreen","notificationFormat","networkEnabled")) { "Unknown setting" }
        val checked = when (key) {
            "networkEnabled" -> value as Boolean
            "chargeLimit" -> (value as Number).toInt().also { require(it in 50..100) }
            "lowLimit" -> (value as Number).toInt().also { require(it in 5..50) }
            "heatLimit" -> (value as Number).toInt().also { require(it in 35..50) }
            else -> value
        }
        if (key == "currentUnit" || key == "currentPolarity") {
            currentNormalizer.resetCalibration()
            prefs.edit().remove("currentDivisor").remove("currentInverted").apply()
        }
        saveSettings(settings() + (key to checked), key)
    }

    fun saveSettings(values: Map<String, Any?>, changedKey: String? = null) {
        val previous = settings()
        alertMask = BatteryMath.rearmForSettings(alertMask, previous, values, changedKey)
        prefs.edit().putString("values", JSONObject(values).toString()).putInt("alertMask", alertMask).apply()
        if (previous["toneUri"] != values["toneUri"] || previous.containsKey("toneUri") != values.containsKey("toneUri") || (previous["sound"] != false) != (values["sound"] != false)) Alerts.existing()?.stopPreview()
        seedSnapshotIfNeeded()
        sample(false)
    }
    fun updateTone(uri: String?, name: String) {
        val values = settings().toMutableMap().apply { put("toneUri", uri); put("toneName", name) }
        saveSettings(values)
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
        acceptBatteryIntent(received, initialSticky, afterObservationGap)
        sample(foreground || monitoring)
    }

    internal fun alarmSnapshot(received: Intent?, initialSticky: Boolean): Map<String, Any?> {
        if (received != null) acceptBatteryIntent(received, initialSticky)
        seedSnapshotIfNeeded()
        return read()
    }

    private fun read(): Map<String, Any?> {
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
        val fullCapacity = hardware["fullCapacityMah"] as? Double ?: prefs.getFloat("estimatedCapacity", -1f).takeIf { it > 0 }?.toDouble()
        val healthEstimate = BatteryHealthEstimate.calculate(
            hardware["designCapacityMah"] as? Double, hardware["fullCapacityMah"] as? Double,
            prefs.getFloat("estimatedCapacity", -1f).takeIf { it > 0 }?.toDouble(), counter, level
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
        if (remaining == null && status == "Discharging" && counter != null && current != null && current < -10) {
            remaining = (counter / abs(current) * 3600000).toLong()
            remainingSource = "Estimate at the current discharge rate"
        }
        if (status == "Full") { remaining = 0; remainingSource = "Battery is full"; remainingState = "full" }
        val result = mutableMapOf<String, Any?>(
            "time" to now, "sequence" to ++readingSequence, "level" to level, "status" to status, "plugged" to plugged,
            "batterySnapshotSource" to snapshotSource, "broadcastLevel" to rawLevel,
            "batteryBroadcastSequence" to broadcastSequence,
            "broadcastScale" to scale, "capacityProperty" to propertyLevel,
            "source" to when (plugged) { 1 -> "AC charger"; 2 -> "USB"; 4 -> "Wireless"; 8 -> "Dock"; 0 -> "Not plugged"; else -> "External power" },
            "voltageMv" to voltage, "currentMa" to current, "powerW" to power, "temperatureC" to temperature,
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
            "historyError" to historyFailure,
            "monitoring" to monitoring, "settings" to settings,
            "optimized" to (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(context.packageName),
            "notificationsAllowed" to (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
        )
        result.putAll(hardware)
        result["fullCapacityMah"] = fullCapacity
        result["fullCapacitySource"] = if (hardware["fullCapacityMah"] != null) "Hardware reported" else if (fullCapacity != null) "Estimated from charging" else "Unavailable"
        if (cycles != null) result["cycles"] = cycles
        return result
    }

    fun setForeground(value: Boolean) {
        foreground = value
        reconcile()
    }
    fun setMonitoring(value: Boolean) {
        monitoring = value
        reconcile()
    }
    private fun reconcile() {
        if (foreground || monitoring) {
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
            requestHardware()
            handler.removeCallbacks(tick)
            sample(true)
            handler.postDelayed(tick, if (foreground) 3000 else 30000)
        } else {
            if (registered) {
                context.unregisterReceiver(receiver)
                registered = false
                initialSnapshotAfterGap = true
            }
            handler.removeCallbacks(tick)
            chargeStartCounter = null; chargeStartLevel = null
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
            if (!foreground && !monitoring) return
            sample(true)
            handler.postDelayed(this, if (foreground) 3000 else 30000)
        }
    }

    private fun sample(record: Boolean) {
        val reading = read().toMutableMap()
        evaluateAlerts(reading)
        reading["chargeAlertLatched"] = alertMask and 1 != 0
        reading["alarmActive"] = Alerts.existing()?.alarmActive == true
        latest = reading
        listener?.invoke(reading)
        serviceListener?.invoke(reading)
        val now = reading["time"] as Long
        val state = "${reading["plugged"]}/${reading["status"]}/${reading["level"]}"
        if (record && (now - lastRecord >= (if (foreground) 3000 else 30000) || state != lastState)) {
            lastRecord = now; lastState = state
            worker.execute {
                try {
                    store.record(reading)
                    handler.post { historyFailure = null }
                } catch (e: Exception) {
                    android.util.Log.e("Fittery", "History write failed", e)
                    handler.post {
                        historyFailure = "History could not be saved. Check available device storage."
                        listener?.invoke(read())
                    }
                }
            }
        }
        estimateCapacity(reading)
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

    private fun evaluateAlerts(r: Map<String, Any?>) {
        val s = settings()
        Alerts.existing()?.reconcile((r["plugged"] as Int) > 0, r["level"] as Int?, r["temperatureC"] as Double?, s)
        val (newMask, fired) = BatteryMath.alertMask(
            alertMask, (r["plugged"] as Int) > 0, r["status"] == "Charging" || (r["status"] == "Full" && (r["plugged"] as Int) > 0), r["level"] as Int?, r["temperatureC"] as Double?,
            s["chargeAlert"] == true, (s["chargeLimit"] as? Number)?.toInt() ?: 80,
            s["lowAlert"] == true, (s["lowLimit"] as? Number)?.toInt() ?: 20,
            s["heatAlert"] == true, (s["heatLimit"] as? Number)?.toInt() ?: 40
        )
        if (newMask != alertMask) { alertMask = newMask; prefs.edit().putInt("alertMask",alertMask).apply() }
        if (fired and 1 != 0) Alerts.get(context).notify(11, "Charging target reached", "Battery is at ${r["level"]}%. You can unplug your charger.", s)
        if (fired and 2 != 0) Alerts.get(context).notify(12, "Battery is running low", "Battery is at ${r["level"]}%. Connect a charger soon.", s)
        if (fired and 4 != 0) Alerts.get(context).notify(13, "Battery temperature is high", "Battery temperature is ${r["temperatureC"]}°C. Let your phone cool down.", s)
    }

    private fun estimateCapacity(r: Map<String, Any?>) {
        if (r["status"] != "Charging") { chargeStartCounter = null; chargeStartLevel = null; return }
        val counter = r["chargeCounterMah"] as? Double ?: return
        val level = r["level"] as? Int ?: return
        if (chargeStartCounter == null) { chargeStartCounter = counter; chargeStartLevel = level; return }
        val gain = level - (chargeStartLevel ?: level)
        if (gain >= 20 && counter > chargeStartCounter!!) {
            val estimate = (counter - chargeStartCounter!!) * 100 / gain
            if (estimate in 500.0..30000.0) prefs.edit().putFloat("estimatedCapacity", estimate.toFloat()).apply()
        }
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
    fun clear(callback: (String?) -> Unit) {
        worker.execute {
            try { store.clear(); handler.post { lastRecord = 0; lastState = ""; sample(foreground || monitoring); callback(null) } }
            catch (e: Exception) { handler.post { callback(e.message) } }
        }
    }
}
