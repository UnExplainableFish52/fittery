package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class NotificationElementsTest {
    @Test fun legacySelectionsRemainCompatible() {
        assertEquals(NotificationElements.metrics, NotificationElements.selected(emptyMap<String, Any?>()))
        for (metric in NotificationElements.metrics) assertEquals(listOf(metric), NotificationElements.selected(mapOf("notificationFormat" to metric)))
    }

    @Test fun acceptsAllOrOneToThreeDistinctElements() {
        assertTrue(NotificationElements.valid(listOf("All metrics")))
        assertTrue(NotificationElements.valid(listOf("Temperature")))
        assertTrue(NotificationElements.valid(listOf("Temperature", "Current", "Power")))
        for (invalid in listOf(emptyList(), NotificationElements.metrics, listOf("All metrics", "Power"), listOf("Power", "Power"), listOf("Unknown"))) {
            assertFalse(NotificationElements.valid(invalid))
            try { SettingValidation.check("notificationElements", invalid, false); fail("Invalid selection accepted") }
            catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun selectedElementsHaveConsistentOrderAndOverrideLegacyValue() {
        assertEquals(listOf("Current", "Temperature"), NotificationElements.selected(mapOf("notificationElements" to listOf("Temperature", "Current"), "notificationFormat" to "Power")))
    }
}
