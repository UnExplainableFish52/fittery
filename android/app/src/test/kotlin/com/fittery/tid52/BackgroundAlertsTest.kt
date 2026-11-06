package com.fittery.tid52

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = Application::class)
class BackgroundAlertsTest {
    @Test fun existingInstallKeepsDashboardOffAndIntroductionAcknowledgmentSurvivesRecreation() {
        val context: Context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("release_preferences", 0).edit().clear().commit()
        context.getSharedPreferences("settings", 0).edit().clear().putBoolean("monitorEnabled", false).commit()
        val preferences = ReleasePreferences(context)
        assertFalse(preferences.dashboardDefault)
        assertFalse(preferences.state()["settingsIntroAcknowledged"]!!)
        preferences.acknowledge("settingsIntroAcknowledged")
        assertTrue(ReleasePreferences(context).state()["settingsIntroAcknowledged"]!!)
        assertFalse(ReleasePreferences(context).state()["backgroundAlertsOffered"]!!)
        assertFalse(MonitorPreference.alertsEnabled(context))
    }

    @Test fun alertOnlyDoesNotStartTelemetryAndModesStopIndependently() {
        val context: Context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("settings", 0).edit().clear().putBoolean("backgroundAlertsEnabled", true).commit()
        ReflectionHelpers.setStaticField(BatteryEngine::class.java, "instance", null)
        ReflectionHelpers.setStaticField(Alerts::class.java, "instance", null)
        val engine = BatteryEngine.get(context)
        val service = Robolectric.buildService(MonitorService::class.java).create()
        try {
            assertTrue(engine.backgroundAlertsRunning)
            assertFalse(engine.monitoring)
            assertFalse(ReflectionHelpers.getField<Boolean>(engine, "hardwareRequested"))
            val battery = Intent(Intent.ACTION_BATTERY_CHANGED).apply {
                putExtra(BatteryManager.EXTRA_LEVEL, 79); putExtra(BatteryManager.EXTRA_SCALE, 100)
                putExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_CHARGING)
                putExtra(BatteryManager.EXTRA_PLUGGED, BatteryManager.BATTERY_PLUGGED_USB)
                putExtra(BatteryManager.EXTRA_TEMPERATURE, 300)
            }
            engine.receiveBatteryIntent(battery)
            assertFalse(ReflectionHelpers.getField<Boolean>(engine, "hardwareRequested"))
            assertNull(engine.snapshot()["currentMa"])
            engine.receiveBatteryIntent(Intent(battery).putExtra(BatteryManager.EXTRA_LEVEL, 80))
            assertEquals(true, engine.snapshot()["alarmActive"])
            assertFalse(engine.monitoring)
            assertFalse(ReflectionHelpers.getField<Boolean>(engine, "hardwareRequested"))
            MonitorPreference.set(context, true)
            service.get().onStartCommand(null, 0, 1)
            assertTrue(engine.monitoring)
            service.get().onStartCommand(Intent().setAction("STOP"), 0, 2)
            assertFalse(engine.monitoring)
            assertTrue(engine.backgroundAlertsRunning)
            MonitorPreference.set(context, true)
            service.get().onStartCommand(null, 0, 3)
            service.get().onStartCommand(Intent().setAction("STOP_ALERTS"), 0, 4)
            assertTrue(engine.monitoring)
            assertFalse(engine.backgroundAlertsRunning)
            assertTrue(MonitorPreference.enabled(context))
            assertFalse(MonitorPreference.alertsEnabled(context))
        } finally {
            service.destroy()
            engine.worker.shutdown()
            engine.worker.awaitTermination(10, TimeUnit.SECONDS)
            Alerts.existing()?.stop()
        }
    }
}
