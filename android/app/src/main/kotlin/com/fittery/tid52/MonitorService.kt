package com.fittery.tid52

import android.app.Service
import android.app.NotificationManager
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class MonitorService : Service() {
    private lateinit var engine: BatteryEngine
    override fun onCreate() {
        super.onCreate()
        engine = BatteryEngine.get(this)
        val notification = Alerts.get(this).persistent(engine.snapshot())
        if (Build.VERSION.SDK_INT >= 34) startForeground(1,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1,notification)
        engine.serviceListener = { r ->
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1,Alerts.get(this).persistent(r))
        }
        engine.setMonitoring(true)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") { stopSelf(); return START_NOT_STICKY }
        return START_STICKY
    }
    override fun onDestroy() {
        engine.serviceListener = null
        engine.setMonitoring(false)
        Alerts.get(this).stop()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}

class AlarmDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { Alerts.get(context).silence() }
}
