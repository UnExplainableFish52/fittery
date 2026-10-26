package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class BatteryHealthEstimateTest {
    @Test fun prefersFullCapacityOverProvisionalGaugeReadings() {
        val result = BatteryHealthEstimate.calculate(5000.0, 4663.0, 4800.0, 2500.0, 50)!!
        assertEquals(93.26, result.percent, .001)
        assertFalse(result.rough)
        assertEquals("Full-capacity estimate", result.source)
    }
    @Test fun usesAChargingSessionBeforeTheGaugeFallback() {
        val result = BatteryHealthEstimate.calculate(5000.0, null, 4800.0, 2350.0, 50)!!
        assertEquals(96.0, result.percent, .001)
        assertEquals("Charging-session estimate", result.source)
    }
    @Test fun calculatesAClearlyLabeledRoughPercentage() {
        val result = BatteryHealthEstimate.calculate(5000.0, null, null, 2350.0, 50)!!
        assertEquals(94.0, result.percent, .001)
        assertTrue(result.rough)
        assertEquals("Estimated", result.source)
    }
    @Test fun missingOrInconsistentMeasurementsDoNotBecomeAHealthPercentage() {
        assertNull(BatteryHealthEstimate.calculate(null, 4663.0, null, null, 50))
        assertNull(BatteryHealthEstimate.calculate(5000.0, null, null, null, 50))
        assertNull(BatteryHealthEstimate.calculate(5000.0, null, null, 235.0, 5))
        assertNull(BatteryHealthEstimate.calculate(5000.0, null, null, 5000.0, 50))
        assertNull(BatteryHealthEstimate.calculate(5000.0, null, null, Double.NaN, 50))
    }
}
