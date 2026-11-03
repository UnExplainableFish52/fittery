package com.fittery.tid52

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.view.WindowManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 28], manifest = Config.NONE)
class ChargingDashboardWindowTest {
    class DashboardHost : Activity() {
        var movedBehindLock = false
        var modernVisibility = false
        override fun moveTaskToBack(nonRoot: Boolean): Boolean {
            movedBehindLock = true
            return true
        }
        override fun setShowWhenLocked(showWhenLocked: Boolean) {
            modernVisibility = showWhenLocked
        }
    }

    @Test fun dismissalRemovesVisibilityAndNeverHoldsTheScreenOn() {
        val host = Robolectric.buildActivity(DashboardHost::class.java).setup()
        val activity = host.get()
        val dashboard = ChargingDashboardWindow(activity)
        dashboard.show()
        assertTrue(dashboard.visible)
        assertEquals(0, activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        dashboard.dismiss()
        assertFalse(dashboard.visible)
        assertFalse(activity.modernVisibility)
        @Suppress("DEPRECATION")
        assertEquals(0, activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        host.pause().stop().destroy()
    }

    @Test fun lockedDismissalPutsOrdinaryAppUiBehindKeyguard() {
        val host = Robolectric.buildActivity(DashboardHost::class.java).setup()
        val activity = host.get()
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        shadowOf(keyguard).setKeyguardLocked(true)
        val dashboard = ChargingDashboardWindow(activity)
        dashboard.show()
        dashboard.dismiss()
        assertTrue(activity.movedBehindLock)
        assertTrue(keyguard.isKeyguardLocked)
        assertFalse(dashboard.visible)
        host.pause().stop().destroy()
    }

    @Test fun unlockedDismissalKeepsThePreviousScreenAvailable() {
        val host = Robolectric.buildActivity(DashboardHost::class.java).setup()
        val activity = host.get()
        shadowOf(activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).setKeyguardLocked(false)
        val dashboard = ChargingDashboardWindow(activity)
        dashboard.show()
        dashboard.dismiss()
        assertFalse(activity.movedBehindLock)
        host.pause().stop().destroy()
    }
}
