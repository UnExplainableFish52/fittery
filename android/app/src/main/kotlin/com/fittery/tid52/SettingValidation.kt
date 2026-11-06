package com.fittery.tid52

/** Validate at the native boundary, including bulk updates, before any write. */
object SettingValidation {
    private val booleans = setOf("fahrenheit", "millivolts", "dualCell", "chargeAlert", "lowAlert", "heatAlert", "sound", "lockScreen", "networkEnabled", "keepRecordings", "chargingDashboard", "chargingScreenSaver")
    private val choices = mapOf("theme" to setOf("System default", "Dark", "AMOLED Black"), "currentUnit" to setOf("Auto", "µA", "mA"), "currentPolarity" to setOf("Auto", "Standard", "Inverted"), "notificationFormat" to setOf("All metrics", "Current", "Power", "Temperature", "Time remaining"))
    fun check(key: String, value: Any?, allowTone: Boolean): Any? {
        if (key in booleans) { require(value is Boolean) { "Expected a boolean for $key" }; return value }
        choices[key]?.let { require(value is String && value in it) { "Invalid choice for $key" }; return value }
        val range = when(key) { "chargeLimit" -> 50..100; "lowLimit" -> 5..50; "heatLimit" -> 35..50; "heatReminderMinutes" -> 1..30; "notificationIntervalSeconds" -> 1..5; else -> null }
        if (range != null) {
            require(value is Number && value.toDouble().isFinite() && value.toDouble() == value.toInt().toDouble() && value.toInt() in range) { "Invalid whole number for $key" }
            require(key != "notificationIntervalSeconds" || value.toInt() in setOf(1,3,5)) { "Invalid notification interval" }
            return value.toInt()
        }
        if (allowTone && AlertTone.entries.any { key in setOf(it.key + "ToneSource", it.key + "ToneName", it.key + "ToneUri") }) {
            when {
                key.endsWith("Source") -> require(value in setOf("bundled", "silent", "system", "file"))
                key.endsWith("Name") -> require(value is String && value.length <= 512)
                key.endsWith("Uri") -> require(value == null || value is String && value.length <= 4096 && android.net.Uri.parse(value).scheme in setOf("content", "android.resource", "file"))
                else -> throw IllegalArgumentException("Unknown tone setting")
            }
            return value
        }
        throw IllegalArgumentException("Unknown setting: $key")
    }
}
