package com.fittery.tid52

/** Hardware discovery rules, independent of Android for deterministic tests. */
object BatteryHardwareValues {
    private val supplies = listOf("battery", "bms", "mtk-gauge", "fuelgauge", "fg", "main")
    fun validCapacity(mah: Double?): Double? = mah?.takeIf { it.isFinite() && it in 500.0..30000.0 }

    fun discover(read: (String) -> Double?, profileCapacity: () -> Double?): Map<String, Any?> {
        fun capacity(name: String): Double? {
            for (supply in supplies) {
                // Linux CHARGE_* attributes are microamp-hours, not percentages
                // or energy. Never substitute charge_full for factory design.
                val value = read("/sys/class/power_supply/$supply/$name")
                validCapacity(value?.div(1000))?.let { return it }
            }
            return null
        }
        val result = mutableMapOf<String, Any?>()
        for (supply in supplies) {
            val cycles = read("/sys/class/power_supply/$supply/cycle_count")
            if (cycles != null && cycles.isFinite() && cycles in 0.0..1000000.0) {
                result["cycles"] = cycles.toInt()
                break
            }
        }
        // Multi-cell phones can expose pack and cell values on different nodes.
        // Never calculate health by mixing those nodes or a device profile.
        val pair = supplies.firstNotNullOfOrNull { supply ->
            val full = validCapacity(read("/sys/class/power_supply/$supply/charge_full")?.div(1000))
            val design = validCapacity(read("/sys/class/power_supply/$supply/charge_full_design")?.div(1000))
            if (full != null && design != null) Triple(supply, full, design) else null
        }
        if (pair != null) {
            result["fullCapacityMah"] = pair.second
            result["designCapacityMah"] = pair.third
            result["designCapacitySource"] = "Battery controller"
            result["capacityPairReliable"] = true
            result["capacityController"] = pair.first
            return result
        }
        result["capacityPairReliable"] = false
        capacity("charge_full")?.let { result["fullCapacityMah"] = it }
        val design = capacity("charge_full_design")
        if (design != null) {
            result["designCapacityMah"] = design
            result["designCapacitySource"] = "Battery controller"
        } else {
            validCapacity(profileCapacity())?.let {
                result["designCapacityMah"] = it
                result["designCapacitySource"] = "Device power profile"
            }
        }
        return result
    }
}
