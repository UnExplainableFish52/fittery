package com.fittery.tid52

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

object NotificationPermission {
    fun requiredForSetting(key: String, value: Any?): Boolean =
        key in setOf("chargeAlert", "lowAlert", "heatAlert") && value == true

    fun allowed(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()

    fun status(activity: Activity): Map<String, Boolean> {
        val asked = activity.getSharedPreferences("settings", Context.MODE_PRIVATE).getBoolean("notificationPermissionAsked", false)
        return mapOf("allowed" to allowed(activity), "asked" to asked,
            "canRequest" to (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                (!asked || activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))))
    }

    fun markAsked(context: Context) {
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putBoolean("notificationPermissionAsked", true).apply()
    }
}
