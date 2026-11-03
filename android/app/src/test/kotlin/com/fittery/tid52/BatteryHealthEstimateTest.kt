package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class BatteryHealthEstimateTest {
    @Test fun pairedHardwareCapacityIsExplicitlyAnEstimate() {
        val result = BatteryHealthEstimate.calculate(5000.0, 4663.0)!!
        assertEquals(93.26, result.percent, .001)
        assertTrue(result.rough)
        assertEquals("Hardware capacity estimate", result.source)
    }
    @Test fun missingHardwareDoesNotFallBackToRemainingChargeOrOldSessionGuesses() {
        assertNull(BatteryHealthEstimate.calculate(5000.0, null))
    }
    @Test fun valuesFromDifferentControllersAreNotCompared() {
        assertNull(BatteryHealthEstimate.calculate(5000.0, 4200.0, pairedHardware = false))
    }
    @Test fun missingOrInconsistentMeasurementsDoNotBecomeAHealthPercentage() {
        assertNull(BatteryHealthEstimate.calculate(null, 4663.0))
        assertNull(BatteryHealthEstimate.calculate(5000.0, 4663000.0))
        assertNull(BatteryHealthEstimate.calculate(5000.0, 7000.0))
        assertNull(BatteryHealthEstimate.calculate(5000.0, Double.NaN))
    }
}
