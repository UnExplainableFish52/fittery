package com.fittery.tid52

import android.app.Service
import android.app.NotificationManager
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper

class MonitorService : Service() {
    private lateinit var engine: BatteryEngine
    private val handler = Handler(Looper.getMainLooper())
    private var lastState: String? = null
    private var lastSettings: Any? = null
    private var refreshMs = 1000L
    private fun interval(reading: Map<String, Any?>): Long {
        val seconds = ((reading["settings"] as? Map<*, *>)?.get("notificationIntervalSeconds") as? Number)?.toInt()
        return (seconds?.takeIf { it in setOf(1, 3, 5) } ?: 1) * 1000L
    }
    private fun state(reading: Map<String, Any?>) = "${reading["plugged"]}/${reading["status"]}/${reading["level"]}/${reading["alarmActive"]}"
    private fun publish(reading: Map<String, Any?>) {
        refreshMs = interval(reading)
        lastState = state(reading)
        lastSettings = reading["settings"]
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1, Alerts.get(this).persistent(reading))
        handler.removeCallbacks(refreshNotification)
        if (engine.monitoring) handler.postDelayed(refreshNotification, refreshMs)
    }
    private val refreshNotification = object : Runnable {
        override fun run() { publish(engine.snapshot()) }
    }
    override fun onCreate() {
        super.onCreate()
        engine = BatteryEngine.get(this)
        if (!MonitorPreference.requested(this)) { stopSelf(); return }
        Alerts.get(this)
        syncModes()
    }
    private fun syncModes() {
        val alerts = MonitorPreference.alertsEnabled(this)
        val monitor = MonitorPreference.enabled(this)
        engine.setBackgroundAlerts(alerts)
        if (engine.monitoring != monitor) {
            if (monitor) engine.setMonitoring(true) else engine.stopMonitoring()
        }
        handler.removeCallbacks(refreshNotification)
        if (!monitor && !alerts) { stopSelf(); return }
        val notification = if (monitor) Alerts.get(this).persistent(engine.snapshot()) else Alerts.get(this).backgroundStatus()
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1, notification)
        engine.serviceListener = { r ->
            if (engine.monitoring && (state(r) != lastState || r["settings"] != lastSettings)) publish(r)
        }
        if (monitor) publish(engine.snapshot())
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "STOP" -> MonitorPreference.set(this, false)
            "STOP_ALERTS" -> MonitorPreference.setAlerts(this, false)
        }
        syncModes()
        return if (MonitorPreference.requested(this)) START_STICKY else START_NOT_STICKY
    }
    override fun onDestroy() {
        handler.removeCallbacks(refreshNotification)
        engine.serviceListener = null
        engine.setMonitoring(false)
        engine.setBackgroundAlerts(false)
        Alerts.get(this).stop()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}

class AlarmDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        BatteryEngine.get(context).snoozeTemperature()
        Alerts.get(context).silence()
        // Keep the threshold latch: acknowledging heat must not retrigger on
        // the next hot reading. Publish now so the monitoring action clears.
        BatteryEngine.get(context).refresh()
    }
}
