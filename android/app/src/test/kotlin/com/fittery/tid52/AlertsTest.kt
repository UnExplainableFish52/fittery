package com.fittery.tid52

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ProviderInfo
import android.os.Looper
import android.net.Uri
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.AudioAttributes
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadow.api.Shadow
import org.robolectric.Robolectric
import org.robolectric.shadows.ShadowContentResolver
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE, application = Application::class, shadows = [AlarmRingtoneManagerShadow::class, AlarmRingtoneShadow::class])
class AlertsTest {
    private lateinit var context: Context
    private lateinit var alerts: Alerts
    private val settings = mapOf<String, Any?>("chargeAlert" to true, "chargeLimit" to 80, "sound" to false)

    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString("values", JSONObject(settings).toString()).commit()
        alerts = Alerts.get(context)
        alerts.stop()
        AlarmRingtoneManagerShadow.players.clear()
        AlarmRingtoneManagerShadow.uris.clear()
        ShadowContentResolver.registerProviderInternal("audio.test", Robolectric.buildContentProvider(LocalAudioProvider::class.java).create(ProviderInfo().apply { authority = "audio.test" }).get())
    }
    @After fun cleanup() { alerts.stop() }

    @Test fun eachAlertPreviewsItsDedicatedVoiceWithoutLooping() {
        for (tone in AlertTone.entries) {
            assertTrue(alerts.startPreview(emptyMap(), tone))
            assertEquals(tone.defaultUri(context), AlarmRingtoneManagerShadow.uris.last())
            assertFalse(AlarmRingtoneManagerShadow.players.last().isLooping)
            alerts.stopPreview()
            assertFalse(AlarmRingtoneManagerShadow.players.last().isPlaying)
        }
    }

    @Test fun temperatureAlarmInterruptsChargeAndChargeResumesWhenTemperatureRecovers() {
        val audible = settings + mapOf("sound" to true, "heatAlert" to true, "heatLimit" to 38)
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString("values", JSONObject(audible).toString()).commit()
        alerts.notify(11, "Charge", "Target", audible)
        val charge = AlarmRingtoneManagerShadow.players.last()
        alerts.notify(13, "Heat", "Warm", audible)
        assertFalse(charge.isPlaying)
        assertEquals(AlertTone.HEAT.defaultUri(context), AlarmRingtoneManagerShadow.uris.last())
        val heat = AlarmRingtoneManagerShadow.players.last()
        alerts.reconcile(true, 80, 30.0, audible)
        assertFalse(heat.isPlaying)
        assertEquals(AlertTone.CHARGE.defaultUri(context), AlarmRingtoneManagerShadow.uris.last())
        assertTrue(AlarmRingtoneManagerShadow.players.last().isPlaying)
    }

    private fun notification(): Notification? = (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        .activeNotifications.firstOrNull { it.id == 11 }?.notification

    @Test fun thresholdNotificationDoesNotExpireAfterThePreviewDuration() {
        alerts.notify(11, "Charging target reached", "Battery is at 80%", settings)
        shadowOf(Looper.getMainLooper()).idleFor(30, TimeUnit.SECONDS)
        assertTrue(alerts.alarmActive)
        assertNotNull(notification())
        assertTrue(notification()!!.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(0, notification()!!.flags and Notification.FLAG_AUTO_CANCEL)
        AlarmDismissReceiver().onReceive(context, Intent())
        assertFalse(alerts.alarmActive)
        assertNull(notification())
    }

    @Test fun unpluggingStopsTheChargingAlarmThroughItsOwnReceiver() {
        alerts.notify(11, "Charging target reached", "Battery is at 80%", settings)
        assertTrue(alerts.alarmActive)
        context.sendBroadcast(Intent(Intent.ACTION_POWER_DISCONNECTED))
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(alerts.alarmActive)
        assertNull(notification())
    }

    @Test fun aPreviewEndingCannotSilenceAThresholdAlert() {
        assertTrue(alerts.startPreview(settings))
        alerts.notify(11, "Charging target reached", "Battery is at 80%", settings)
        shadowOf(Looper.getMainLooper()).idleFor(5, TimeUnit.SECONDS)
        assertFalse(alerts.previewPlaying)
        assertTrue(alerts.alarmActive)
        assertNotNull(notification())
    }

    @Test fun theCompleteAlarmToneLoopsUntilManuallySilenced() {
        val audible = settings + ("sound" to true)
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString("values", JSONObject(audible).toString()).commit()
        alerts.notify(11, "Charging target reached", "Battery is at 80%", audible)
        val player = AlarmRingtoneManagerShadow.players.last()
        assertTrue(player.isPlaying)
        assertTrue(player.isLooping)
        shadowOf(Looper.getMainLooper()).idleFor(30, TimeUnit.SECONDS)
        assertTrue(player.isPlaying)
        AlarmDismissReceiver().onReceive(context, Intent())
        assertFalse(player.isPlaying)
    }

    @Test fun aLocalSongUsesTheSameSelectionForPreviewAndLoopingAlarm() {
        val uri = Uri.parse("content://audio.test/song")
        val custom = settings + mapOf("toneUri" to uri.toString(), "toneSource" to "file", "sound" to true)
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString("values", JSONObject(custom).toString()).commit()
        assertTrue(alerts.startPreview(custom))
        val preview = AlarmRingtoneManagerShadow.players.last()
        assertEquals(uri, AlarmRingtoneManagerShadow.uris.last())
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        assertTrue(preview.isPlaying) // Long voices must not be cut off at three seconds.
        shadowOf(Looper.getMainLooper()).idleFor(27, TimeUnit.SECONDS)
        assertFalse(preview.isPlaying)
        assertFalse(alerts.previewPlaying)
        alerts.notify(11, "Charging target reached", "Battery is at 80%", custom)
        val alarm = AlarmRingtoneManagerShadow.players.last()
        assertEquals(uri, AlarmRingtoneManagerShadow.uris.last())
        assertTrue(alarm.isLooping)
        assertTrue(alarm.isPlaying)
        alerts.silence()
        assertFalse(alarm.isPlaying)
    }

    @Test fun removedSongHasAPreviewErrorButActualAlarmsFallBackToTheDefaultTone() {
        val custom = settings + mapOf("toneUri" to "content://audio.test/missing", "toneSource" to "file", "sound" to true)
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString("values", JSONObject(custom).toString()).commit()
        try { alerts.startPreview(custom); fail("Missing preview should fail") }
        catch (e: IllegalArgumentException) { assertTrue(e.message!!.contains("Choose it again")) }
        alerts.notify(11, "Charging target reached", "Battery is at 80%", custom)
        assertEquals(AlertTone.CHARGE.defaultUri(context), AlarmRingtoneManagerShadow.uris.last())
        assertTrue(AlarmRingtoneManagerShadow.players.last().isPlaying)
    }
}

// Audio is simulated so these tests can exercise real notification, receiver,
// and timer behavior without a physical speaker or media-provider database.
@Implements(RingtoneManager::class)
class AlarmRingtoneManagerShadow {
    companion object {
        val players = mutableListOf<Ringtone>()
        val uris = mutableListOf<Uri?>()
        @JvmStatic @Implementation fun getDefaultUri(type: Int): Uri = Uri.parse("content://test/alarm")
        @JvmStatic @Implementation fun getRingtone(context: Context, uri: Uri?): Ringtone =
            Shadow.newInstanceOf(Ringtone::class.java).also { players.add(it); uris.add(uri) }
    }
}

@Implements(Ringtone::class)
class AlarmRingtoneShadow {
    private var playingState = false
    private var loopingState = false
    @Implementation fun play() { playingState = true }
    @Implementation fun stop() { playingState = false }
    @Implementation fun isPlaying(): Boolean = playingState
    @Implementation fun setAudioAttributes(attributes: AudioAttributes) = Unit
    @Implementation(minSdk = 28) fun setLooping(looping: Boolean) { loopingState = looping }
    @Implementation(minSdk = 28) fun isLooping(): Boolean = loopingState
}
