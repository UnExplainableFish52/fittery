package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class TrafficRateTrackerTest {
    @Test fun ratesUseActualElapsedTimeAndKeepDirectionsSeparate() {
        val rates = TrafficRateTracker()
        assertNull(rates.sample(1000, 2000, 500))
        assertEquals(1000.0 to 250.0, rates.sample(6000, 3250, 5500))
        assertEquals(0.0 to 0.0, rates.sample(6000, 3250, 8500))
    }

    @Test fun unsupportedCountersAndInterfaceResetsNeverProduceNegativeRatesOrSpikes() {
        val rates = TrafficRateTracker()
        rates.sample(10000, 20000, 1000)
        assertNull(rates.sample(100, 200, 4000))
        assertEquals(100.0 to 200.0, rates.sample(400, 800, 7000))
        assertNull(rates.sample(-1, 900, 10000))
        assertNull(rates.sample(1000, 1200, 13000))
        assertEquals(100.0 to 100.0, rates.sample(1300, 1500, 16000))
    }

    @Test fun resumeAndInvalidTimeNeedAFreshBaseline() {
        val rates = TrafficRateTracker()
        rates.sample(100, 100, 1000)
        assertNull(rates.sample(200, 200, 1000))
        rates.reset()
        assertNull(rates.sample(100000, 100000, 100000))
        assertEquals(100.0 to 0.0, rates.sample(100300, 100000, 103000))
    }
}
