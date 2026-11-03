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
        engine.dreamListener = null
        engine.setDreaming(false)
        engine.setMonitoring(false)
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

    @Test fun connectionMetadataDistinguishesAnObservedPlugInFromAStartupSnapshot() {
        fun reading(sequence: Int, source: Int) = Intent(Intent.ACTION_BATTERY_CHANGED).apply {
            putExtra("seq", sequence); putExtra(BatteryManager.EXTRA_LEVEL, 50); putExtra(BatteryManager.EXTRA_SCALE, 100)
            putExtra(BatteryManager.EXTRA_PLUGGED, source)
            putExtra(BatteryManager.EXTRA_STATUS, if (source > 0) BatteryManager.BATTERY_STATUS_CHARGING else BatteryManager.BATTERY_STATUS_DISCHARGING)
        }
        engine.receiveBatteryIntent(reading(1, 0))
        assertNull(engine.snapshot()["chargeConnectedAt"])
        engine.receiveBatteryIntent(reading(2, BatteryManager.BATTERY_PLUGGED_USB))
        val snapshot = engine.snapshot()
        assertTrue(snapshot["chargeConnectionConfirmed"] == true)
        assertNotNull(snapshot["elapsedRealtimeMs"])
        assertNotNull(snapshot["chargeConnectedDurationMs"])
        engine.setForeground(true)
        engine.setForeground(false)
        assertFalse(engine.snapshot()["chargeConnectionConfirmed"] == true)
    }

    @Test fun perAlertToneChoicesPersistIndependentlyAndDefaultResetKeepsOtherSettings() {
        engine.updateSetting("chargingScreenSaver", true)
        engine.updateTone("content://audio/charge", "Charge song", "file", AlertTone.CHARGE)
        engine.updateTone("content://audio/heat", "Heat song", "file", AlertTone.HEAT)
        engine.updateTone(null, "Silent", "silent", AlertTone.LOW)
        assertEquals("content://audio/charge", AlertTone.CHARGE.selectedUri(engine.settings()))
        assertEquals("content://audio/heat", AlertTone.HEAT.selectedUri(engine.settings()))
        engine.updateTone(null, AlertTone.CHARGE.title, "bundled", AlertTone.CHARGE)
        val json = org.json.JSONObject(context.getSharedPreferences("settings", Context.MODE_PRIVATE).getString("values", "{}")!!)
        assertEquals("bundled", json.getString("chargeToneSource"))
        assertEquals("content://audio/heat", json.getString("heatToneUri"))
        assertEquals("silent", json.getString("lowToneSource"))
        assertTrue(engine.settings()["chargingScreenSaver"] == true)
        assertTrue(engine.settings()["chargingDashboard"] == true)
    }

    @Test fun dreamViewingSharesThreeSecondSamplesWithoutStartingARecording() {
        battery(BatteryManager.BATTERY_STATUS_CHARGING)
        var activityEvents = 0
        var dreamEvents = 0
        engine.listener = { activityEvents++ }
        engine.dreamListener = { dreamEvents++ }
        engine.setDreaming(true)
        shadowOf(Looper.getMainLooper()).idleFor(6, TimeUnit.SECONDS)
        assertTrue(dreamEvents >= 3)
        assertEquals(activityEvents, dreamEvents)
        assertEquals(3000L, engine.snapshot()["sampleIntervalMs"])
        assertFalse(engine.monitoring)
        val stored = BatteryStore(context)
        try { assertTrue((stored.history(false)["points"] as List<*>).isEmpty()) }
        finally { stored.close() }
        engine.setForeground(false)
        assertTrue(ReflectionHelpers.getField<Boolean>(engine, "registered"))
        engine.setDreaming(false)
        assertFalse(ReflectionHelpers.getField<Boolean>(engine, "registered"))
        val previous = dreamEvents
        shadowOf(Looper.getMainLooper()).idleFor(6, TimeUnit.SECONDS)
        assertEquals(previous, dreamEvents)
    }

    @Test fun endingDreamDoesNotDisconnectActivityOrStopBackgroundMonitoring() {
        battery(BatteryManager.BATTERY_STATUS_CHARGING)
        var activityEvents = 0
        engine.listener = { activityEvents++ }
        engine.setForeground(true)
        engine.setDreaming(true)
        engine.setMonitoring(true)
        engine.setDreaming(false)
        engine.dreamListener = null
        val previous = activityEvents
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        assertTrue(activityEvents > previous)
        assertTrue(engine.monitoring)
        assertTrue(ReflectionHelpers.getField<Boolean>(engine, "registered"))
    }

    @Test fun screenSaverOptInEnablesDashboardAndMasterOffClearsBoth() {
        assertEquals(false, engine.settings()["chargingScreenSaver"])
        engine.updateSetting("chargingScreenSaver", true)
        assertEquals(true, engine.settings()["chargingDashboard"])
        assertEquals(true, engine.settings()["chargingScreenSaver"])
        assertFalse(engine.monitoring)
        engine.updateSetting("chargingDashboard", false)
        assertEquals(false, engine.settings()["chargingDashboard"])
        assertEquals(false, engine.settings()["chargingScreenSaver"])
    }

    @Test fun chargingDashboardIsOptInAndPersistsWithoutEnablingMonitoring() {
        assertEquals(false, engine.settings()["chargingDashboard"])
        engine.updateSetting("chargingDashboard", true)
        assertEquals(true, engine.settings()["chargingDashboard"])
        assertFalse(engine.monitoring)
        val recreated = BatteryEngine(context)
        try { assertEquals(true, recreated.settings()["chargingDashboard"]) }
        finally { recreated.worker.shutdown(); recreated.worker.awaitTermination(10, TimeUnit.SECONDS) }
        engine.updateSetting("chargingDashboard", false)
        assertEquals(false, engine.settings()["chargingDashboard"])
    }

    @Test fun defaultChargeAndHeatAlarmsFireAtEightyAndThirtyEightButLowBatteryStaysOff() {
        val settings = engine.settings()
        assertEquals(true, settings["chargeAlert"])
        assertEquals(80, settings["chargeLimit"])
        assertEquals(true, settings["heatAlert"])
        assertEquals(38, settings["heatLimit"])
        assertEquals(false, settings["lowAlert"])
        engine.receiveBatteryIntent(snapshotIntent(79, true, 1).putExtra(BatteryManager.EXTRA_TEMPERATURE, 379))
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        assertFalse(notifications.activeNotifications.any { it.id in 11..13 })
        engine.receiveBatteryIntent(snapshotIntent(80, true, 2).putExtra(BatteryManager.EXTRA_TEMPERATURE, 380))
        assertTrue(notifications.activeNotifications.any { it.id == 11 })
        assertTrue(notifications.activeNotifications.any { it.id == 13 })
        engine.receiveBatteryIntent(snapshotIntent(10, false, 3).putExtra(BatteryManager.EXTRA_TEMPERATURE, 300))
        assertFalse(notifications.activeNotifications.any { it.id == 12 })
        engine.updateSetting("chargeAlert", false)
        engine.updateSetting("heatAlert", false)
        engine.updateSetting("heatLimit", 42)
        engine.updateSetting("theme", "Dark")
        assertEquals(false, engine.settings()["chargeAlert"])
        assertEquals(false, engine.settings()["heatAlert"])
        assertEquals(42, engine.settings()["heatLimit"])
    }

    @Test fun liveCurrentUsesOneSecondNativeSamplesWithoutSpeedingUpTheDashboardOrBackground() {
        val manager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val sensor = shadowOf(manager)
        sensor.setIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW, 352000)
        battery(BatteryManager.BATTERY_STATUS_CHARGING)
        val current = mutableListOf<Map<String, Any?>>()
        var dashboardEvents = 0
        engine.listener = { dashboardEvents++ }
        engine.setForeground(true)
        engine.setCurrentListener { current.add(it) }
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        assertTrue(current.size >= 4)
        assertTrue(dashboardEvents < current.size)
        assertEquals(352.0, current.last()["currentMa"])
        assertEquals(352000, current.last()["rawCurrent"])
        assertEquals(4283, current.last()["voltageMv"])
        assertEquals(1000L, current.last()["sampleIntervalMs"])
        sensor.setIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW, -545000)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(-545.0, current.last()["currentMa"])
        sensor.setIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW, Int.MIN_VALUE)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertNull(current.last()["currentMa"])
        engine.setForeground(false)
        val count = current.size
        engine.setMonitoring(true)
        shadowOf(Looper.getMainLooper()).idleFor(30, TimeUnit.SECONDS)
        assertEquals(count, current.size)
        engine.setCurrentListener(null)
        engine.setMonitoring(false)
    }


    private fun snapshotIntent(level: Int, charging: Boolean, sequence: Int? = null) = Intent(Intent.ACTION_BATTERY_CHANGED).apply {
        putExtra(BatteryManager.EXTRA_LEVEL, level); putExtra(BatteryManager.EXTRA_SCALE, 100)
        putExtra(BatteryManager.EXTRA_STATUS, if (charging) BatteryManager.BATTERY_STATUS_CHARGING else BatteryManager.BATTERY_STATUS_DISCHARGING)
        putExtra(BatteryManager.EXTRA_PLUGGED, if (charging) BatteryManager.BATTERY_PLUGGED_USB else 0)
        if (sequence != null) putExtra("seq", sequence)
    }

    @Test fun chargerReminderAppearsOncePerConnectionAndNeverStartsMonitoring() {
        engine.receiveBatteryIntent(snapshotIntent(50, false, 1))
        engine.setForeground(true)
        engine.receiveBatteryIntent(snapshotIntent(50, true, 2))
        val first = engine.snapshot()["sessionPrompt"] as Map<*, *>
        assertEquals("enableMonitor", first["kind"])
        assertFalse(engine.monitoring)
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val reminder = notifications.activeNotifications.single { it.id == 20 }.notification
        assertEquals(Alerts.ENABLE_MONITOR, shadowOf(reminder.contentIntent).savedIntent.action)
        engine.dismissSessionPrompt((first["token"] as Number).toLong())
        engine.receiveBatteryIntent(snapshotIntent(51, true, 3))
        assertNull(engine.snapshot()["sessionPrompt"])
        engine.receiveBatteryIntent(snapshotIntent(51, false, 4))
        assertFalse(notifications.activeNotifications.any { it.id == 20 })
        engine.receiveBatteryIntent(snapshotIntent(51, true, 5))
        assertEquals("enableMonitor", (engine.snapshot()["sessionPrompt"] as Map<*, *>)["kind"])
        engine.setMonitoring(true)
        assertNull(engine.snapshot()["sessionPrompt"])
        assertFalse(notifications.activeNotifications.any { it.id == 20 })
    }

    @Test fun unplugReportIsPublishedAfterSavingAndMonitoringContinues() {
        context.deleteDatabase("monitor.db")
        engine.receiveBatteryIntent(snapshotIntent(50, true, 1))
        engine.setForeground(true)
        engine.setMonitoring(true)
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        engine.receiveBatteryIntent(snapshotIntent(51, false, 2))
        engine.worker.submit {}.get(10, TimeUnit.SECONDS)
        shadowOf(Looper.getMainLooper()).idle()
        val report = engine.snapshot()["sessionPrompt"] as Map<*, *>
        assertEquals("chargingReport", report["kind"])
        assertTrue(engine.monitoring)
        val notification = (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .activeNotifications.single { it.id >= 100 }.notification
        val target = shadowOf(notification.contentIntent).savedIntent
        assertEquals(Alerts.OPEN_REPORT, target.action)
        assertEquals((report["recordingId"] as Number).toLong(), target.getLongExtra("recordingId", -1))
        assertEquals((report["startTime"] as Number).toLong(), target.getLongExtra("startTime", -1))
        engine.dismissSessionPrompt((report["token"] as Number).toLong())
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        engine.worker.submit {}.get(10, TimeUnit.SECONDS)
        shadowOf(Looper.getMainLooper()).idle()
        assertNull(engine.snapshot()["sessionPrompt"])
    }

    @Test fun monitorRecordingUsesThreeSecondBackgroundSamplesAndOneIdentityAcrossPowerChanges() {
        context.deleteDatabase("monitor.db")
        engine.receiveBatteryIntent(snapshotIntent(50, false))
        engine.setForeground(true)
        engine.worker.submit {}.get(10, TimeUnit.SECONDS)
        assertFalse(context.getDatabasePath("monitor.db").exists())
        engine.setMonitoring(true)
        engine.setForeground(false)
        shadowOf(Looper.getMainLooper()).idleFor(6, TimeUnit.SECONDS)
        engine.receiveBatteryIntent(snapshotIntent(51, true))
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        engine.receiveBatteryIntent(snapshotIntent(51, false))
        engine.stopMonitoring()
        engine.worker.submit {}.get(10, TimeUnit.SECONDS)
        var response: Map<String, Any?>? = null
        engine.monitorQuery("recordings", null, null, null, null, null) { data, error ->
            assertNull(error); response = data
        }
        engine.worker.submit {}.get(10, TimeUnit.SECONDS)
        shadowOf(Looper.getMainLooper()).idle()
        @Suppress("UNCHECKED_CAST") val records = response!!["recordings"] as List<Map<String, Any?>>
        assertEquals(1, records.size)
        assertEquals(0L, records.single()["active"])
        assertTrue((records.single()["sampleCount"] as Number).toInt() >= 4)
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
