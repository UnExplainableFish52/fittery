package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class NotificationPermissionPolicyTest {
    @Test fun localThresholdAndDisplaySettingsDoNotRequirePermission() {
        for ((key, value) in mapOf("chargeLimit" to 80, "lowLimit" to 20, "heatLimit" to 40,
            "heatReminderMinutes" to 5, "notificationElements" to listOf("Temperature"))) {
            assertFalse(NotificationPermission.requiredForSetting(key, value))
        }
    }

    @Test fun enablingAlertsRequiresPermissionButDisablingDoesNot() {
        for (key in listOf("chargeAlert", "lowAlert", "heatAlert")) {
            assertTrue(NotificationPermission.requiredForSetting(key, true))
            assertFalse(NotificationPermission.requiredForSetting(key, false))
        }
    }
}
