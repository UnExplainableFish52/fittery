package com.fittery.tid52

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Looper
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE, application = Application::class)
class BatteryEngineTest {
    private lateinit var context: Context
    private lateinit var engine: BatteryEngine
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        Alerts.existing()?.stop()
        ReflectionHelpers.setStaticField(Alerts::class.java, "instance", null)
        ReflectionHelpers.setStaticField(BatteryEngine::class.java, "instance", null)
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().clear().commit()
        engine = BatteryEngine.get(context)
    }
    @After fun cleanup() {
        engine.setForeground(false)
        Alerts.existing()?.stop()
        // Let foreground history work finish instead of interrupting native
        // SQLite initialization and contaminating the next test's runtime.
        engine.worker.shutdown()
        assertTrue(engine.worker.awaitTermination(10, TimeUnit.SECONDS))
    }

    private fun battery(status: Int) {
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(Intent(Intent.ACTION_BATTERY_CHANGED).apply {
            putExtra(BatteryManager.EXTRA_LEVEL, 88); putExtra(BatteryManager.EXTRA_SCALE, 100)
            putExtra(BatteryManager.EXTRA_STATUS, status); putExtra(BatteryManager.EXTRA_PLUGGED, BatteryManager.BATTERY_PLUGGED_USB)
            putExtra(BatteryManager.EXTRA_VOLTAGE, 4283); putExtra(BatteryManager.EXTRA_TEMPERATURE, 300)
        })
        engine.snapshot()
    }
    private fun activeNotification(): Boolean = (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).activeNotifications.any { it.id == 11 }


    private fun snapshotIntent(level: Int, charging: Boolean, sequence: Int? = null) = Intent(Intent.ACTION_BATTERY_CHANGED).apply {
        putExtra(BatteryManager.EXTRA_LEVEL, level); putExtra(BatteryManager.EXTRA_SCALE, 100)
        putExtra(BatteryManager.EXTRA_STATUS, if (charging) BatteryManager.BATTERY_STATUS_CHARGING else BatteryManager.BATTERY_STATUS_DISCHARGING)
        putExtra(BatteryManager.EXTRA_PLUGGED, if (charging) BatteryManager.BATTERY_PLUGGED_USB else 0)
        if (sequence != null) putExtra("seq", sequence)
    }

    @Test fun startupQueryAndCallbacksForOtherPackagesCannotSeedTheBatterySnapshot() {
        val foreign = snapshotIntent(56, false, 300).setPackage("com.example.other")
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(foreign)
        assertNull(engine.snapshot()["level"])
        engine.receiveBatteryIntent(foreign, initialSticky = true)
        assertNull(engine.snapshot()["level"])
        engine.receiveBatteryIntent(snapshotIntent(86, true, 200), initialSticky = true)
        assertEquals(86, engine.snapshot()["level"])
        engine.receiveBatteryIntent(foreign)
        assertEquals(86, engine.snapshot()["level"])
        engine.receiveBatteryIntent(snapshotIntent(87, true, 201).setPackage(context.packageName))
        assertEquals(87, engine.snapshot()["level"])
    }

    @Test fun currentInitialCallbackReplacesStaleRegistrationReturnButOlderCallbacksDoNot() {
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(snapshotIntent(56, false, 100))
        engine.snapshot()
        engine.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        engine.receiveBatteryIntent(snapshotIntent(86, true, 200), initialSticky = true)
        engine.receiveBatteryIntent(snapshotIntent(60, false, 150), initialSticky = true)
        engine.receiveBatteryIntent(snapshotIntent(55, false, 90))
        assertEquals(86, engine.snapshot()["level"])
        assertEquals("Charging", engine.snapshot()["status"])
    }

    @Test fun resumeAcceptsANewerInitialSnapshotAfterBatteryChangesWhileMonitoringIsOff() {
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(snapshotIntent(92, true, 100))
        engine.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        engine.receiveBatteryIntent(snapshotIntent(92, true, 101))
        engine.setForeground(false)
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(snapshotIntent(91, false, 102))
        engine.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(91, engine.snapshot()["level"])
        assertEquals("Discharging", engine.snapshot()["status"])
    }

    @Test fun resumeWithoutSequenceMetadataUsesTheActualCallbackAfterAnObservationGap() {
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(snapshotIntent(92, true))
        engine.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        engine.receiveBatteryIntent(snapshotIntent(92, true))
        engine.setForeground(false)
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(snapshotIntent(91, false))
        engine.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(91, engine.snapshot()["level"])
        assertEquals("Discharging", engine.snapshot()["status"])
    }

    @Test fun startupSeedsFromStickyAndRegisteredReceiverPublishesNewBatteryBroadcasts() {
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(snapshotIntent(56, false))
        assertEquals(56, engine.snapshot()["level"])
        engine.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        var ui: Map<String, Any?>? = null
        var monitor: Map<String, Any?>? = null
        engine.listener = { ui = it }
        engine.serviceListener = { monitor = it }
        context.sendBroadcast(snapshotIntent(92, true))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(92, ui!!["level"])
        assertEquals("Charging", ui!!["status"])
        assertEquals(BatteryManager.BATTERY_PLUGGED_USB, ui!!["plugged"])
        assertEquals(ui, monitor)
        assertEquals("92% · Charging", Alerts.get(context).persistent(monitor!!).extras.getString("android.title"))
        assertEquals(92, engine.refresh()["level"])
    }

    @Test fun registeringOnResumeCannotReplaceALiveReadingWithStaleStickyData() {
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(snapshotIntent(56, false, 100))
        engine.receiveBatteryIntent(snapshotIntent(92, true, 200))
        repeat(2) {
            engine.setForeground(true)
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(92, engine.snapshot()["level"])
            assertEquals("Charging", engine.snapshot()["status"])
            engine.setForeground(false)
        }
    }

    @Test fun delayedInitialCallbacksCannotReplaceLiveDataButNewLiveUpdatesCan() {
        engine.receiveBatteryIntent(snapshotIntent(92, true))
        val sequence = engine.snapshot()["sequence"] as Long
        val stale = snapshotIntent(56, false)
        engine.receiveBatteryIntent(stale, initialSticky = true)
        val alarm = engine.alarmSnapshot(stale, initialSticky = true)
        assertEquals(92, alarm["level"])
        assertEquals("Charging", alarm["status"])
        assertTrue((alarm["sequence"] as Long) > sequence)

        var ui: Map<String, Any?>? = null
        var monitor: Map<String, Any?>? = null
        engine.listener = { ui = it }
        engine.serviceListener = { monitor = it }
        engine.receiveBatteryIntent(snapshotIntent(91, false))
        assertEquals(91, ui!!["level"])
        assertEquals("Discharging", ui!!["status"])
        assertEquals(ui, monitor)
        assertEquals("91% · Discharging", Alerts.get(context).persistent(monitor!!).extras.getString("android.title"))
        assertTrue((ui!!["sequence"] as Long) > (alarm["sequence"] as Long))
    }

    @Test fun staleFiftySixPercentStickyQueryCannotOverwriteLiveChargingOnRefresh() {
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(Intent(Intent.ACTION_BATTERY_CHANGED).apply {
            putExtra(BatteryManager.EXTRA_LEVEL, 56); putExtra(BatteryManager.EXTRA_SCALE, 100)
            putExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_DISCHARGING)
            putExtra(BatteryManager.EXTRA_PLUGGED, 0)
        })
        assertEquals(56, engine.snapshot()["level"])
        val live = Intent(Intent.ACTION_BATTERY_CHANGED).apply {
            putExtra(BatteryManager.EXTRA_LEVEL, 92); putExtra(BatteryManager.EXTRA_SCALE, 100)
            putExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_CHARGING)
            putExtra(BatteryManager.EXTRA_PLUGGED, BatteryManager.BATTERY_PLUGGED_USB)
        }
        engine.receiveBatteryIntent(live)
        // Framework-owned Intent objects must not remain mutable app state.
        live.putExtra(BatteryManager.EXTRA_LEVEL, 56)
        repeat(3) {
            assertEquals(92, engine.snapshot()["level"])
            val refreshed = engine.refresh()
            assertEquals(92, refreshed["level"])
            assertEquals("Charging", refreshed["status"])
            val notification = Alerts.get(context).persistent(refreshed)
            assertEquals("92% · Charging", notification.extras.getString("android.title"))
        }
        engine.updateSetting("sound", false)
        engine.updateSetting("chargeAlert", true)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(activeNotification())
        assertEquals(92, engine.refresh()["level"])
    }

    @Test fun targetEightyAtEightyEightTriggersImmediatelyAndCanBeExplicitlyRearmed() {
        battery(BatteryManager.BATTERY_STATUS_CHARGING)
        engine.updateSetting("sound", false)
        engine.updateSetting("chargeAlert", true)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(activeNotification())
        Alerts.get(context).silence()
        assertFalse(activeNotification())
        engine.updateSetting("chargeLimit", 80)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(activeNotification())
        assertEquals(true, engine.refresh()["alarmActive"])
    }

    @Test fun pluggedInPausedChargingStillHonorsAnAlreadyReachedTarget() {
        battery(BatteryManager.BATTERY_STATUS_NOT_CHARGING)
        engine.updateSetting("sound", false)
        engine.updateSetting("chargeAlert", true)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(activeNotification())
    }
}
