package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class HistoryIntervalTest {
    @Test fun unplugRetainsTheFinalChargingIntervalAndGain() {
        val interval = HistoryInterval.between(100000L, 1, 79, 117000L, 0, 80)
        assertTrue(interval.sourceChanged)
        assertFalse(interval.gap)
        assertEquals(17000L, interval.pluggedMs)
        assertEquals(1, interval.chargedPercent)
    }

    @Test fun pluggingInDoesNotCountThePrecedingDischargeTimeAsCharging() {
        val interval = HistoryInterval.between(100000L, 0, 50, 120000L, 1, 49)
        assertTrue(interval.sourceChanged)
        assertEquals(0L, interval.pluggedMs)
        assertEquals(0, interval.chargedPercent)
    }

    @Test fun gapsAndClockChangesDoNotInventHistory() {
        for (time in listOf(99999L, 221000L)) {
            val interval = HistoryInterval.between(100000L, 1, 20, time, 1, 80)
            assertTrue(interval.gap)
            assertEquals(0L, interval.pluggedMs)
            assertEquals(0, interval.chargedPercent)
        }
        val first = HistoryInterval.between(null, null, null, 100000L, 1, 80)
        assertEquals(0L, first.pluggedMs)
        assertEquals(0, first.chargedPercent)
    }

    @Test fun changingChargerTypePreservesObservedPluggedTime() {
        val interval = HistoryInterval.between(100000L, 1, 79, 130000L, 2, 80)
        assertTrue(interval.sourceChanged)
        assertEquals(30000L, interval.pluggedMs)
        assertEquals(1, interval.chargedPercent)
    }
}
