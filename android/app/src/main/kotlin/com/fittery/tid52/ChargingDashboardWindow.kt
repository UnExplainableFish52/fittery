package com.fittery.tid52

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager

/** Visibility only: never dismisses keyguard, wakes the display, or holds it on. */
internal class ChargingDashboardWindow(private val activity: Activity) {
    var visible = false
        private set

    fun show() {
        visible = true
        applyVisibility(true)
    }

    fun dismiss() {
        if (visible) {
            val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            // Put the task behind keyguard before returning to ordinary app UI.
            if (keyguard.isKeyguardLocked) activity.moveTaskToBack(true)
        }
        clear()
    }

    fun clear() {
        visible = false
        applyVisibility(false)
    }

    private fun applyVisibility(show: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) activity.setShowWhenLocked(show)
        else {
            @Suppress("DEPRECATION")
            if (show) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
            else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }
}
