package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class ChargingDreamPolicyTest {
    @Test fun requiresBothPreferencesAndARealPowerConnection() {
        fun reading(master: Boolean, dream: Boolean, plugged: Int) = mapOf<String, Any?>(
            "settings" to mapOf("chargingDashboard" to master, "chargingScreenSaver" to dream), "plugged" to plugged
        )
        assertFalse(ChargingDreamPolicy.allowed(emptyMap()))
        assertFalse(ChargingDreamPolicy.allowed(reading(false, false, 1)))
        assertFalse(ChargingDreamPolicy.allowed(reading(true, false, 1)))
        assertFalse(ChargingDreamPolicy.allowed(reading(false, true, 1)))
        assertFalse(ChargingDreamPolicy.allowed(reading(true, true, 0)))
        assertTrue(ChargingDreamPolicy.allowed(reading(true, true, 1)))
        assertTrue(ChargingDreamPolicy.allowed(reading(true, true, 4) + ("status" to "Full")))
        assertTrue(ChargingDreamPolicy.allowed(reading(true, true, 2) + ("status" to "Not charging")))
    }
}
