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
        handler.postDelayed(refreshNotification, refreshMs)
    }
    private val refreshNotification = object : Runnable {
        override fun run() { publish(engine.snapshot()) }
    }
    override fun onCreate() {
        super.onCreate()
        engine = BatteryEngine.get(this)
        val initial = engine.snapshot()
        refreshMs = interval(initial)
        lastState = state(initial)
        lastSettings = initial["settings"]
        val notification = Alerts.get(this).persistent(initial)
        if (Build.VERSION.SDK_INT >= 34) startForeground(1,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1,notification)
        engine.serviceListener = { r ->
            // Meaningful state/settings changes remain immediate. Routine
            // telemetry is refreshed independently of the UI and recorder.
            if (state(r) != lastState || r["settings"] != lastSettings) publish(r)
        }
        engine.setMonitoring(true)
        handler.removeCallbacks(refreshNotification)
        handler.postDelayed(refreshNotification, refreshMs)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") { engine.stopMonitoring(); stopSelf(); return START_NOT_STICKY }
        return START_STICKY
    }
    override fun onDestroy() {
        handler.removeCallbacks(refreshNotification)
        engine.serviceListener = null
        engine.setMonitoring(false)
        Alerts.get(this).stop()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}

class AlarmDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Alerts.get(context).silence()
        // Keep the threshold latch: acknowledging heat must not retrigger on
        // the next hot reading. Publish now so the monitoring action clears.
        BatteryEngine.get(context).refresh()
    }
}
