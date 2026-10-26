package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class BatteryHardwareValuesTest {
    @Test fun discoversGaugeCapacityAndConvertsMicroampHours() {
        val nodes = mapOf(
            "/sys/class/power_supply/bms/charge_full_design" to 5000000.0,
            "/sys/class/power_supply/bms/charge_full" to 4663000.0,
            "/sys/class/power_supply/bms/cycle_count" to 508.0
        )
        val result = BatteryHardwareValues.discover({ nodes[it] }, { error("Hardware capacity should take precedence") })
        assertEquals(5000.0, result["designCapacityMah"])
        assertEquals(4663.0, result["fullCapacityMah"])
        assertEquals(508, result["cycles"])
        assertEquals("Battery controller", result["designCapacitySource"])
    }

    @Test fun usesTheDeviceProfileWhenSysfsIsUnavailable() {
        val result = BatteryHardwareValues.discover({ null }, { 5000.0 })
        assertEquals(5000.0, result["designCapacityMah"])
        assertEquals("Device power profile", result["designCapacitySource"])
        assertNull(result["fullCapacityMah"])
    }

    @Test fun doesNotMislabelActualCapacityAsDesignCapacity() {
        val result = BatteryHardwareValues.discover({ path -> if (path.endsWith("battery/charge_full")) 4663000.0 else null }, { 0.0 })
        assertEquals(4663.0, result["fullCapacityMah"])
        assertNull(result["designCapacityMah"])
        assertNull(result["designCapacitySource"])
    }

    @Test fun rejectsUnsupportedValuesAndPreservesZeroCycles() {
        assertNull(BatteryHardwareValues.validCapacity(Double.NaN))
        assertNull(BatteryHardwareValues.validCapacity(Double.POSITIVE_INFINITY))
        assertNull(BatteryHardwareValues.validCapacity(-1.0))
        val result = BatteryHardwareValues.discover({ path -> if (path.endsWith("battery/cycle_count")) 0.0 else Double.NaN }, { null })
        assertEquals(0, result["cycles"])
        assertNull(result["designCapacityMah"])
    }
}
