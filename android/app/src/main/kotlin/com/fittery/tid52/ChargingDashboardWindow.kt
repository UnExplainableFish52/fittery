package com.fittery.tid52

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.view.Window
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

internal fun hideChargingDashboardBars(window: Window) {
    WindowCompat.getInsetsController(window, window.decorView).apply {
        systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        hide(WindowInsetsCompat.Type.systemBars())
    }
    if (Build.VERSION.SDK_INT >= 28) {
        window.attributes = window.attributes.apply {
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }
}

/** Visibility only: never dismisses keyguard, wakes the display, or holds it on. */
internal class ChargingDashboardWindow(private val activity: Activity) {
    var visible = false
        private set
    private var previousUiFlags = 0
    private var previousBarsBehavior = 0
    private var previousCutoutMode = 0

    fun show() {
        if (!visible) {
            @Suppress("DEPRECATION")
            previousUiFlags = activity.window.decorView.systemUiVisibility
            previousBarsBehavior = WindowCompat.getInsetsController(activity.window, activity.window.decorView).systemBarsBehavior
            if (Build.VERSION.SDK_INT >= 28) previousCutoutMode = activity.window.attributes.layoutInDisplayCutoutMode
        }
        visible = true
        applyVisibility(true)
        hideChargingDashboardBars(activity.window)
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        if (hasFocus && visible) hideChargingDashboardBars(activity.window)
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
        val wasVisible = visible
        visible = false
        applyVisibility(false)
        if (wasVisible) {
            WindowCompat.getInsetsController(activity.window, activity.window.decorView).apply {
                show(WindowInsetsCompat.Type.systemBars())
                systemBarsBehavior = previousBarsBehavior
            }
            @Suppress("DEPRECATION")
            activity.window.decorView.systemUiVisibility = previousUiFlags
            if (Build.VERSION.SDK_INT >= 28) {
                activity.window.attributes = activity.window.attributes.apply {
                    layoutInDisplayCutoutMode = previousCutoutMode
                }
            }
        }
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
