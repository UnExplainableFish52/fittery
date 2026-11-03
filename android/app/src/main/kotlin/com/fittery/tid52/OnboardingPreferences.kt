package com.fittery.tid52

import android.content.Context

/** Separate keys keep tutorial completion independent of alarm settings and recordings. */
class OnboardingPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("onboarding", Context.MODE_PRIVATE)

    fun snapshot(): Map<String, Boolean> = mapOf(
        "onboardingCompleted" to prefs.getBoolean("onboardingCompleted", false),
        "showOnboardingOnLaunch" to prefs.getBoolean("showOnboardingOnLaunch", true)
    )

    /** Called on BatteryEngine's worker; both values reach disk before navigation succeeds. */
    fun complete(showOnLaunch: Boolean): Map<String, Boolean> {
        check(prefs.edit().putBoolean("onboardingCompleted", true)
            .putBoolean("showOnboardingOnLaunch", showOnLaunch).commit()) {
            "Your welcome preference could not be saved. Please try again."
        }
        return snapshot()
    }
}
