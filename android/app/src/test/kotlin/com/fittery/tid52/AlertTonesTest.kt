package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class AlertTonesTest {
    @Test fun eachNewAlertUsesItsOwnBundledVoice() {
        val settings = AlertTone.migrate(emptyMap())
        for (tone in AlertTone.entries) {
            assertEquals("bundled", tone.source(settings))
            assertEquals(tone.title, settings["${tone.key}ToneName"])
        }
        assertEquals(3, AlertTone.entries.map { it.resource }.distinct().size)
    }

    @Test fun existingExplicitToneChoicesSurviveTheUpgradeAndDefaultResetIsIndependent() {
        val migrated = AlertTone.migrate(mapOf("toneUri" to "content://audio/song", "toneSource" to "file", "toneName" to "My voice"))
        assertFalse(migrated.containsKey("toneUri"))
        for (tone in AlertTone.entries) {
            assertEquals("file", tone.source(migrated))
            assertEquals("content://audio/song", tone.selectedUri(migrated))
        }
        val changed = migrated + mapOf("chargeToneSource" to "bundled", "chargeToneUri" to null)
        assertEquals("bundled", AlertTone.CHARGE.source(changed))
        assertEquals("file", AlertTone.HEAT.source(changed))
        assertEquals(changed, AlertTone.migrate(changed))
    }

    @Test fun legacySilentIsPreservedAndHeatTakesPriorityAmongAudibleAlerts() {
        val silent = AlertTone.migrate(mapOf("toneUri" to null))
        assertNull(AlertTone.active(7, silent))
        assertEquals(AlertTone.HEAT, AlertTone.active(7, emptyMap()))
        assertEquals(AlertTone.LOW, AlertTone.active(7, mapOf("heatToneSource" to "silent")))
    }
}
