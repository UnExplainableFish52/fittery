package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class ChargeTimeEstimatorTest {
    @Test fun aFlatPercentageCanUseStableNetCurrentWithoutInventingPercentageProgress() {
        val estimator = ChargeTimeEstimator()
        for (i in 0..11) estimator.observe(ChargeTimeEstimator.Sample(1000000 + i*3000L,88,4143.0,1,true,50.0))
        val result = estimator.estimate(4700.0)!!
        assertEquals(40104000.0,result.millis.toDouble(),1000.0)
        assertTrue(result.source.contains("Provisional"))
    }
    @Test fun sustainedNetDischargeCannotProduceAChargingEta() {
        val estimator = ChargeTimeEstimator()
        for (i in 0..11) estimator.observe(ChargeTimeEstimator.Sample(1000000 + i*3000L,88,4143.0,1,true,-50.0))
        assertNull(estimator.estimate(4700.0))
        assertEquals(-50.0,estimator.recentMedianCurrent!!,.001)
    }

    @Test fun requiresObservedProgressInsteadOfInventingAnEta() {
        val estimator = ChargeTimeEstimator()
        estimator.observe(ChargeTimeEstimator.Sample(1000000, 50, 2500.0, 1, true))
        assertNull(estimator.estimate(5000.0))
        for (i in 1..5) estimator.observe(ChargeTimeEstimator.Sample(1000000 + i * 30000L, 50, 2500.0, 1, true))
        assertNull(estimator.estimate(5000.0))
    }
    @Test fun counterProgressProducesTheExpectedTimeAndCountsDown() {
        val estimator = ChargeTimeEstimator()
        for (i in 0..4) estimator.observe(ChargeTimeEstimator.Sample(1000000 + i * 30000L, 50 + i, 2500.0 + i * 50, 1, true))
        assertEquals(1380000.0, estimator.estimate(5000.0)!!.millis.toDouble(), 1000.0)
        estimator.observe(ChargeTimeEstimator.Sample(1150000, 55, 2750.0, 1, true))
        assertEquals(1350000.0, estimator.estimate(5000.0)!!.millis.toDouble(), 1000.0)
    }
    @Test fun fallsBackToPercentageProgressWhenNoCounterIsAvailable() {
        val estimator = ChargeTimeEstimator()
        for (i in 0..4) estimator.observe(ChargeTimeEstimator.Sample(1000000 + i * 30000L, 50 + i, null, 1, true))
        val result = estimator.estimate(null)!!
        assertEquals(1380000.0, result.millis.toDouble(), 1000.0)
        assertTrue(result.source.contains("battery-level"))
    }
    @Test fun plugChangesGapsAndDischargingResetTheWindow() {
        val estimator = ChargeTimeEstimator()
        for (i in 0..4) estimator.observe(ChargeTimeEstimator.Sample(1000000 + i * 30000L, 50 + i, 2500.0 + i * 50, 1, true))
        assertNotNull(estimator.estimate(5000.0))
        estimator.observe(ChargeTimeEstimator.Sample(1150000, 55, 2750.0, 2, true))
        assertNull(estimator.estimate(5000.0))
        estimator.observe(ChargeTimeEstimator.Sample(1400000, 60, 3000.0, 2, true))
        assertNull(estimator.estimate(5000.0))
        estimator.observe(ChargeTimeEstimator.Sample(1430000, 59, 2950.0, 0, false))
        assertNull(estimator.estimate(5000.0))
    }
}
