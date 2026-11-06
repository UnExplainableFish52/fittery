package com.fittery.tid52

import android.content.Context

class ReleasePreferences(context: Context) {
    private val prefs = context.getSharedPreferences("release_preferences", Context.MODE_PRIVATE)
    init {
        if (!prefs.contains("dashboardDefault")) {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val existing = context.getSharedPreferences("settings", Context.MODE_PRIVATE).all.isNotEmpty() ||
                context.getSharedPreferences("onboarding", Context.MODE_PRIVATE).all.isNotEmpty() ||
                info.lastUpdateTime > info.firstInstallTime || context.databaseList().isNotEmpty()
            check(prefs.edit().putBoolean("dashboardDefault", !existing).commit())
        }
    }
    val dashboardDefault get() = prefs.getBoolean("dashboardDefault", false)
    fun state() = mapOf("settingsIntroAcknowledged" to prefs.getBoolean("settingsIntroAcknowledged", false),
        "backgroundAlertsOffered" to prefs.getBoolean("backgroundAlertsOffered", false))
    fun acknowledge(key: String) {
        require(key in setOf("settingsIntroAcknowledged", "backgroundAlertsOffered"))
        check(prefs.edit().putBoolean(key, true).commit()) { "Could not save your preference. Please retry." }
    }
}
