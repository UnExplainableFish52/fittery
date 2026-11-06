package com.fittery.tid52

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Durable user intent; service lifecycle must never clear this implicitly. */
object MonitorPreference {
    fun enabled(context: Context) = context.getSharedPreferences("settings", Context.MODE_PRIVATE).getBoolean("monitorEnabled", false)
    fun set(context: Context, value: Boolean) {
        check(context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putBoolean("monitorEnabled", value).commit()) { "Could not save monitoring preference" }
    }
    fun alertsEnabled(context: Context) = context.getSharedPreferences("settings", Context.MODE_PRIVATE).getBoolean("backgroundAlertsEnabled", false)
    fun setAlerts(context: Context, value: Boolean) {
        check(context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putBoolean("backgroundAlertsEnabled", value).commit())
    }
    fun requested(context: Context) = enabled(context) || alertsEnabled(context)
    fun start(context: Context) {
        val intent = Intent(context, MonitorService::class.java)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
    }
}

class MonitorRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED) || !MonitorPreference.requested(context)) return
        try { MonitorPreference.start(context) }
        catch (e: RuntimeException) { android.util.Log.w("Fittery", "Monitoring restoration unavailable; open Fittery to retry", e) }
    }
}
