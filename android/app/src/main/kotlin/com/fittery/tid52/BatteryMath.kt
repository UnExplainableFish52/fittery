package com.fittery.tid52

/** No Android dependencies, so normalization and alert rules can be unit tested. */
object BatteryMath {
    fun power(voltageMv: Int?, currentMa: Double?): Double? =
        if (voltageMv == null || currentMa == null) null else voltageMv * currentMa / 1000000.0

    fun rearmForSettings(mask: Int, before: Map<String, Any?>, after: Map<String, Any?>, explicitlyChanged: String? = null): Int {
        var result = mask
        for ((bit, keys, default) in listOf(
            Triple(1, Pair("chargeAlert", "chargeLimit"), 80),
            Triple(2, Pair("lowAlert", "lowLimit"), 20),
            Triple(4, Pair("heatAlert", "heatLimit"), 40)
        )) {
            val enabledChanged = (before[keys.first] == true) != (after[keys.first] == true)
            val oldLimit = (before[keys.second] as? Number)?.toInt() ?: default
            val newLimit = (after[keys.second] as? Number)?.toInt() ?: default
            if (enabledChanged || oldLimit != newLimit || explicitlyChanged == keys.first || explicitlyChanged == keys.second) result = result and bit.inv()
        }
        return result
    }

    fun retainActiveAlerts(mask: Int, plugged: Boolean, level: Int?, temperature: Double?, settings: Map<String, Any?>): Int {
        var result = mask
        val chargeLimit = (settings["chargeLimit"] as? Number)?.toInt() ?: 80
        val lowLimit = (settings["lowLimit"] as? Number)?.toInt() ?: 20
        val heatLimit = (settings["heatLimit"] as? Number)?.toInt() ?: 40
        if (!plugged || settings["chargeAlert"] != true || level != null && level < chargeLimit) result = result and 1.inv()
        if (plugged || settings["lowAlert"] != true || level != null && level > lowLimit) result = result and 2.inv()
        if (settings["heatAlert"] != true || temperature != null && temperature < heatLimit - 2) result = result and 4.inv()
        return result
    }

    fun alertMask(
        previous: Int, plugged: Boolean, charging: Boolean, level: Int?, temperature: Double?,
        chargeEnabled: Boolean, chargeLimit: Int, lowEnabled: Boolean, lowLimit: Int,
        heatEnabled: Boolean, heatLimit: Int
    ): Pair<Int, Int> {
        var mask = previous
        if (!plugged) mask = mask and 1.inv()
        if (plugged) mask = mask and 2.inv()
        if (temperature != null && temperature < heatLimit - 2) mask = mask and 4.inv()
        var fired = 0
        if (chargeEnabled && plugged && level != null && level >= chargeLimit && mask and 1 == 0) fired = fired or 1
        if (lowEnabled && !plugged && level != null && level <= lowLimit && mask and 2 == 0) fired = fired or 2
        if (heatEnabled && temperature != null && temperature >= heatLimit && mask and 4 == 0) fired = fired or 4
        return Pair(mask or fired, fired)
    }
}
