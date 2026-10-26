package com.fittery.tid52

data class BatteryHealthEstimate(val percent: Double, val source: String, val rough: Boolean) {
    companion object {
        fun calculate(
            designMah: Double?, hardwareFullMah: Double?, sessionMah: Double?,
            remainingMah: Double?, level: Int?
        ): BatteryHealthEstimate? {
            val design = BatteryHardwareValues.validCapacity(designMah) ?: return null
            fun estimate(full: Double?, source: String, rough: Boolean): BatteryHealthEstimate? {
                val capacity = BatteryHardwareValues.validCapacity(full) ?: return null
                // Reject incompatible units and obviously inconsistent gauge data.
                if (capacity < design * .1 || capacity > design * 1.2) return null
                return BatteryHealthEstimate((capacity / design * 100).coerceIn(0.0, 100.0), source, rough)
            }
            estimate(hardwareFullMah, "Full-capacity estimate", false)?.let { return it }
            estimate(sessionMah, "Charging-session estimate", false)?.let { return it }
            // Low state of charge magnifies rounding and gauge errors. A gauge
            // estimate is provisional, rather than an independent health test.
            if (level == null || level !in 20..100 || remainingMah == null || !remainingMah.isFinite() || remainingMah <= 0) return null
            return estimate(remainingMah * 100 / level, "Estimated", true)
        }
    }
}
