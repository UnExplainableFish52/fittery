package com.fittery.tid52

internal object ChargingDreamPolicy {
    fun enabled(settings: Map<*, *>): Boolean = settings["chargingDashboard"] == true && settings["chargingScreenSaver"] == true
    fun allowed(reading: Map<String, Any?>): Boolean = enabled(reading["settings"] as? Map<*, *> ?: emptyMap<Any, Any>()) &&
        (reading["plugged"] as? Number)?.toInt()?.let { it > 0 } == true
}
