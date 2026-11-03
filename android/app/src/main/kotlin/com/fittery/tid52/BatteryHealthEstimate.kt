package com.fittery.tid52

data class BatteryHealthEstimate(val percent: Double, val source: String, val rough: Boolean) {
    companion object {
        fun calculate(
            designMah: Double?, hardwareFullMah: Double?, pairedHardware: Boolean = true
        ): BatteryHealthEstimate? {
            val design = BatteryHardwareValues.validCapacity(designMah) ?: return null
            fun estimate(full: Double?, source: String, rough: Boolean): BatteryHealthEstimate? {
                val capacity = BatteryHardwareValues.validCapacity(full) ?: return null
                // Reject incompatible units and obviously inconsistent gauge data.
                if (capacity < design * .1 || capacity > design * 1.2) return null
                return BatteryHealthEstimate((capacity / design * 100).coerceIn(0.0, 100.0), source, rough)
            }
            // Remaining charge / state of charge is not a battery-health test.
            // A single partial charging session is not enough evidence either.
            // Only compare full and design capacities from the same controller.
            if (!pairedHardware) return null
            return estimate(hardwareFullMah, "Hardware capacity estimate", true)
        }
    }
}
