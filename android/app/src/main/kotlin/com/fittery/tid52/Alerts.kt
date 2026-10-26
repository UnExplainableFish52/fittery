package com.fittery.tid52

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.os.BatteryManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper

class Alerts private constructor(private val context: Context) {
    companion object {
        private var instance: Alerts? = null
        fun get(context: Context): Alerts = instance ?: Alerts(context.applicationContext).also { instance = it }
        fun existing(): Alerts? = instance
        const val MONITOR_CHANNEL = "monitor"
        const val ALERT_CHANNEL = "battery_alerts"
    }
    private val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val handler = Handler(Looper.getMainLooper())
    private var alarmTone: Ringtone? = null
    private var alarmToneKey: String? = null
    private var activeAlarmMask = 0
    val alarmActive: Boolean get() = activeAlarmMask != 0
    private var alarmReceiverRegistered = false
    private val legacyAlarmLoop = object : Runnable {
        override fun run() {
            val player = alarmTone ?: return
            if (activeAlarmMask == 0) return
            try {
                if (!player.isPlaying) player.play()
                handler.postDelayed(this, 250)
            } catch (e: Exception) { stopAlarmSound(); android.util.Log.w("Fittery", "Alarm playback failed", e) }
        }
    }
    private val alarmReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val engine = BatteryEngine.get(context)
            val reading = engine.alarmSnapshot(intent, isInitialStickyBroadcast)
            val level = (reading["level"] as? Number)?.toInt()
            val temperature = (reading["temperatureC"] as? Number)?.toDouble()
            val plugged = when (intent.action) {
                Intent.ACTION_POWER_DISCONNECTED -> false
                Intent.ACTION_POWER_CONNECTED -> true
                else -> (reading["plugged"] as? Number)?.toInt()?.let { it > 0 } == true
            }
            reconcile(plugged, level, temperature, engine.settings())
        }
    }
    private var ringtone: Ringtone? = null
    private val stopSound = Runnable { stopPreviewSound() }
    var previewPlaying = false
        private set
    var previewListener: ((Boolean) -> Unit)? = null
    private val checkPlayback = object : Runnable {
        override fun run() {
            val playing = try { ringtone?.isPlaying == true } catch (_: Exception) { false }
            if (playing) handler.postDelayed(this, 150)
            else stopPreviewSound()
        }
    }

    private fun publishPreviewState(value: Boolean) {
        if (previewPlaying != value) {
            previewPlaying = value
            previewListener?.invoke(value)
        }
    }

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(MONITOR_CHANNEL, "Battery monitoring", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Live battery readings while background monitoring is enabled"
                setShowBadge(false)
            })
            manager.createNotificationChannel(NotificationChannel(ALERT_CHANNEL, "Battery alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Charging, low battery and temperature warnings"
                setSound(null, null)
                enableVibration(true)
            })
        }
    }

    private fun builder(channel: String): Notification.Builder =
        (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context))
            .setSmallIcon(R.drawable.ic_battery_notification)
            .setColor(0xFF35D0BD.toInt())
            .setContentIntent(PendingIntent.getActivity(context,0,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))

    fun persistent(r: Map<String, Any?>): Notification {
        val s = r["settings"] as? Map<*,*> ?: emptyMap<Any,Any>()
        val dual = if (s["dualCell"] == true) 2 else 1
        val fahrenheit = s["fahrenheit"] == true
        val current = (r["currentMa"] as? Number)?.let { "%.0f mA".format(it.toDouble()) } ?: "Current unavailable"
        val power = (r["powerW"] as? Number)?.let { "%.2f W".format(it.toDouble() * dual) } ?: "Power unavailable"
        val temperature = (r["temperatureC"] as? Number)?.let { "%.1f %s".format(if (fahrenheit) it.toDouble() * 1.8 + 32 else it.toDouble(), if (fahrenheit) "°F" else "°C") } ?: "Temperature unavailable"
        val remaining = (r["remainingMs"] as? Number)?.toLong()?.let {
            val min = it / 60000
            "${min / 60}h ${min % 60}m ${if (r["status"] == "Charging") "until full" else "remaining"}"
        } ?: "Time estimate unavailable"
        val detail = when (s["notificationFormat"]) {
            "Current" -> current; "Power" -> power; "Temperature" -> temperature; "Time remaining" -> remaining
            else -> "$current · $power · $temperature · $remaining"
        }
        val stop = PendingIntent.getService(context,1,Intent(context,MonitorService::class.java).setAction("STOP"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder(MONITOR_CHANNEL)
            .setContentTitle("${r["level"] ?: "—"}% · ${r["status"] ?: "Monitoring"}")
            .setContentText(detail).setStyle(Notification.BigTextStyle().bigText(detail))
            .setVisibility(if (s["lockScreen"] != false) Notification.VISIBILITY_PUBLIC else Notification.VISIBILITY_SECRET)
            .setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false)
            .addAction(Notification.Action.Builder(null, "Stop monitoring", stop).build())
            .build()
    }

    fun notify(id: Int, title: String, message: String, settings: Map<String, Any?>) {
        val dismiss = PendingIntent.getBroadcast(context,id,Intent(context,AlarmDismissReceiver::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = builder(ALERT_CHANNEL).setContentTitle(title).setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setPriority(Notification.PRIORITY_HIGH).setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(if (settings["lockScreen"] != false) Notification.VISIBILITY_PUBLIC else Notification.VISIBILITY_SECRET)
            .setAutoCancel(false).setOngoing(true).setOnlyAlertOnce(true).setDeleteIntent(dismiss)
            .addAction(Notification.Action.Builder(null,"Silence",dismiss).build()).build()
        manager.notify(id,n)
        activeAlarmMask = activeAlarmMask or when (id) { 11 -> 1; 12 -> 2; 13 -> 4; else -> 0 }
        if (!alarmReceiverRegistered) {
            val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED).apply {
                addAction(Intent.ACTION_POWER_CONNECTED); addAction(Intent.ACTION_POWER_DISCONNECTED)
            }
            alarmReceiverRegistered = true
            try {
                if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(alarmReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                else context.registerReceiver(alarmReceiver, filter)
            } catch (e: Exception) { alarmReceiverRegistered = false; android.util.Log.w("Fittery", "Alarm stop receiver unavailable", e) }
        }
        syncAlarmSound(settings)
    }

    fun reconcile(plugged: Boolean, level: Int?, temperature: Double?, settings: Map<String, Any?>) {
        val previous = activeAlarmMask
        activeAlarmMask = BatteryMath.retainActiveAlerts(previous, plugged, level, temperature, settings)
        for ((bit, id) in listOf(1 to 11, 2 to 12, 4 to 13)) {
            if (previous and bit != 0 && activeAlarmMask and bit == 0) manager.cancel(id)
        }
        syncAlarmSound(settings)
        if (activeAlarmMask == 0) releaseAlarmReceiver()
    }

    fun silence() {
        for (id in listOf(11, 12, 13)) manager.cancel(id)
        activeAlarmMask = 0
        stopAlarmSound()
        releaseAlarmReceiver()
    }

    private fun releaseAlarmReceiver() {
        if (alarmReceiverRegistered) { context.unregisterReceiver(alarmReceiver); alarmReceiverRegistered = false }
    }

    private fun syncAlarmSound(settings: Map<String, Any?>) {
        val selected = settings["toneUri"] as? String
        val silent = settings.containsKey("toneUri") && selected == null
        if (activeAlarmMask == 0 || settings["sound"] == false || silent) { stopAlarmSound(); return }
        val uri = selected?.let(Uri::parse) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        val key = uri.toString()
        if (alarmTone != null && alarmToneKey == key) return
        stopPreview()
        stopAlarmSound()
        try {
            val player = RingtoneManager.getRingtone(context, uri) ?: return
            player.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            if (Build.VERSION.SDK_INT >= 28) player.isLooping = true
            alarmTone = player
            alarmToneKey = key
            player.play()
            // Older Android versions lack Ringtone looping; replay only after
            // the complete tone ends. Modern versions loop in the audio system.
            if (Build.VERSION.SDK_INT < 28) handler.postDelayed(legacyAlarmLoop, 250)
        } catch (e: Exception) { stopAlarmSound(); android.util.Log.w("Fittery", "Alarm sound could not be played", e) }
    }

    private fun stopAlarmSound() {
        handler.removeCallbacks(legacyAlarmLoop)
        try { alarmTone?.stop() } catch (e: Exception) { android.util.Log.w("Fittery", "Alarm sound could not be stopped", e) }
        finally { alarmTone = null; alarmToneKey = null }
    }

    fun startPreview(settings: Map<String, Any?>): Boolean {
        check(!alarmActive) { "Silence the active battery alarm before previewing another tone." }
        return play(settings, 3000, preview = true)
    }

    fun stopPreview() { if (previewPlaying) stopPreviewSound() }

    private fun play(settings: Map<String, Any?>, millis: Long, preview: Boolean = false): Boolean {
        stopPreviewSound()
        val selected = settings["toneUri"] as? String
        // A null URI from the picker means the user selected Silent.
        if (settings.containsKey("toneUri") && selected == null) return false
        val uri = selected?.let(Uri::parse) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        return try {
            val player = RingtoneManager.getRingtone(context,uri) ?: return false
            ringtone = player
            player.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            player.play()
            publishPreviewState(preview)
            handler.postDelayed(checkPlayback, 150)
            handler.postDelayed(stopSound,millis)
            true
        } catch (e: Exception) {
            stopPreviewSound()
            android.util.Log.w("Fittery", "Alarm sound could not be played", e)
            false
        }
    }
    fun stop() { stopPreviewSound(); silence() }

    private fun stopPreviewSound() {
        handler.removeCallbacks(stopSound)
        handler.removeCallbacks(checkPlayback)
        try { ringtone?.stop() }
        catch (e: Exception) { android.util.Log.w("Fittery", "Alarm sound could not be stopped", e) }
        finally { ringtone = null; publishPreviewState(false) }
    }
}
