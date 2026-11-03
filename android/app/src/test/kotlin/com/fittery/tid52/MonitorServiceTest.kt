package com.fittery.tid52

import android.app.Application
import android.app.Notification
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
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = Application::class, shadows = [AlarmRingtoneManagerShadow::class, AlarmRingtoneShadow::class])
class MonitorServiceTest {
    private lateinit var context: Context
    private lateinit var engine: BatteryEngine
    private lateinit var service: ServiceController<MonitorService>
    private lateinit var manager: BatteryManager
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        Alerts.existing()?.stop()
        ReflectionHelpers.setStaticField(Alerts::class.java, "instance", null)
        ReflectionHelpers.setStaticField(BatteryEngine::class.java, "instance", null)
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().clear().commit()
        AlarmRingtoneManagerShadow.players.clear()
        AlarmRingtoneManagerShadow.uris.clear()
        context.deleteDatabase("monitor.db")
        manager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        shadowOf(manager).setIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW, -200000)
        @Suppress("DEPRECATION")
        context.sendStickyBroadcast(Intent(Intent.ACTION_BATTERY_CHANGED).apply {
            putExtra(BatteryManager.EXTRA_LEVEL, 50); putExtra(BatteryManager.EXTRA_SCALE, 100)
            putExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_DISCHARGING)
            putExtra(BatteryManager.EXTRA_PLUGGED, 0); putExtra(BatteryManager.EXTRA_VOLTAGE, 4000)
        })
        engine = BatteryEngine.get(context)
        service = Robolectric.buildService(MonitorService::class.java).create()
    }
    @After fun cleanup() {
        service.destroy()
        Alerts.existing()?.stop()
        engine.worker.shutdown()
        assertTrue(engine.worker.awaitTermination(10, TimeUnit.SECONDS))
    }
    private fun text(): String = (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        .activeNotifications.first { it.id == 1 }.notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString()

    private fun notification(id: Int): Notification? = (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        .activeNotifications.firstOrNull { it.id == id }?.notification

    private fun temperature(value: Int, sequence: Int, plugged: Boolean = false) {
        engine.receiveBatteryIntent(Intent(Intent.ACTION_BATTERY_CHANGED).apply {
            putExtra("seq", sequence)
            putExtra(BatteryManager.EXTRA_LEVEL, 50); putExtra(BatteryManager.EXTRA_SCALE, 100)
            putExtra(BatteryManager.EXTRA_STATUS, if (plugged) BatteryManager.BATTERY_STATUS_CHARGING else BatteryManager.BATTERY_STATUS_DISCHARGING)
            putExtra(BatteryManager.EXTRA_PLUGGED, if (plugged) BatteryManager.BATTERY_PLUGGED_USB else 0)
            putExtra(BatteryManager.EXTRA_TEMPERATURE, value)
        })
    }

    @Test fun monitoringSilenceStopsHeatWithoutStoppingMonitoringOrRetriggeringWhileHot() {
        engine.updateSetting("notificationIntervalSeconds", 5)
        // Also exercise the UI's normal telemetry throttle: an alarm change
        // must reach the notification immediately despite an unchanged level.
        engine.setCurrentListener { }
        temperature(370, 1)
        assertEquals(listOf("Stop monitoring"), notification(1)!!.actions.map { it.title.toString() })
        temperature(400, 2)
        val heat = AlarmRingtoneManagerShadow.players.last()
        assertTrue(heat.isPlaying)
        assertTrue(heat.isLooping)
        val silence = notification(1)!!.actions.first { it.title == "Silence" }
        assertTrue(notification(13)!!.actions.any { it.title == "Silence" })
        silence.actionIntent.send()
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(heat.isPlaying)
        assertFalse(Alerts.get(context).alarmActive)
        assertNull(notification(13))
        assertTrue(engine.monitoring)
        assertEquals(listOf("Stop monitoring"), notification(1)!!.actions.map { it.title.toString() })
        val playerCount = AlarmRingtoneManagerShadow.players.size
        for ((sequence, value) in listOf(410, 390, 380, 360).withIndex()) temperature(value, sequence + 3)
        shadowOf(Looper.getMainLooper()).idleFor(10, TimeUnit.SECONDS)
        assertNull(notification(13))
        assertEquals(playerCount, AlarmRingtoneManagerShadow.players.size)
        // Existing two-degree recovery margin prevents repeated warnings
        // around the threshold; cooling below 36 rearms a 38-degree limit.
        temperature(359, 7)
        temperature(380, 8)
        assertNotNull(notification(13))
        assertTrue(AlarmRingtoneManagerShadow.players.last().isPlaying)
        assertTrue(notification(1)!!.actions.any { it.title == "Silence" })
    }

    @Test fun temperatureNotificationCanSilenceACustomLimitWhileCharging() {
        engine.updateSetting("heatLimit", 35)
        temperature(400, 1, plugged = true)
        val heat = AlarmRingtoneManagerShadow.players.last()
        assertTrue(heat.isPlaying)
        notification(13)!!.actions.single { it.title == "Silence" }.actionIntent.send()
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(heat.isPlaying)
        assertNull(notification(13))
        temperature(410, 2, plugged = true)
        assertNull(notification(13))
        assertTrue(engine.monitoring)
    }

    @Test fun defaultNotificationUpdatesEverySecondWithoutRecordingEverySecond() {
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertTrue(text().contains("-200 mA"))
        shadowOf(manager).setIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW, -600000)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertTrue(text().contains("-600 mA"))
        engine.worker.submit {}.get(10, TimeUnit.SECONDS)
        val count = engine.worker.submit<Int> {
            context.openOrCreateDatabase("monitor.db", Context.MODE_PRIVATE, null).use { db ->
                db.rawQuery("SELECT COUNT(*) FROM samples", null).use { c -> c.moveToFirst(); c.getInt(0) }
            }
        }.get(10, TimeUnit.SECONDS)
        assertEquals(1, count)
    }
    @Test fun changingIntervalReschedulesImmediatelyAndRoutineEngineSamplesDoNotBypassIt() {
        engine.updateSetting("notificationIntervalSeconds", 5)
        assertTrue(text().contains("-200 mA"))
        shadowOf(manager).setIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW, -600000)
        shadowOf(Looper.getMainLooper()).idleFor(4, TimeUnit.SECONDS)
        assertTrue(text().contains("-200 mA"))
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertTrue(text().contains("-600 mA"))
        engine.updateSetting("notificationIntervalSeconds", 3)
        shadowOf(manager).setIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW, -900000)
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        assertTrue(text().contains("-600 mA"))
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertTrue(text().contains("-900 mA"))
    }
    @Test fun unsupportedIntervalsAreRejected() {
        for (value in listOf(0, 2, 60, 3.5)) {
            try { engine.updateSetting("notificationIntervalSeconds", value); fail("Accepted $value") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
