package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class DischargeTimeEstimatorTest {
    private fun DischargeTimeEstimator.read(time: Long, current: Double? = -500.0, mode: String = "default", onBattery: Boolean = true) = estimate(time, onBattery, 2500.0, current, mode)
    @Test fun waitsForEvidenceThenPredictsConstantLoad() {
        val estimator = DischargeTimeEstimator()
        for (t in 0..27 step 3) assertNull(estimator.read(t * 1000L))
        assertEquals(5 * 3600000L, estimator.read(30000))
    }
    @Test fun briefSpikeDoesNotTurnFiveHoursIntoOneHour() {
        val estimator = DischargeTimeEstimator()
        for (t in 0..120 step 3) estimator.read(t * 1000L)
        val before = estimator.read(123000)!!
        estimator.read(126000, -2500.0)
        estimator.read(129000)
        val after = estimator.read(132000)!!
        assertTrue(after > before * .9)
    }
    @Test fun sustainedLoadChangesEventuallyAdapt() {
        val estimator = DischargeTimeEstimator()
        for (t in 0..120 step 3) estimator.read(t * 1000L)
        var remaining: Long? = null
        for (t in 123..720 step 3) remaining = estimator.read(t * 1000L, -1000.0)
        assertEquals(9000000.0, remaining!!.toDouble(), 300000.0)
    }
    @Test fun invalidReadingsSourceChangesAndObservationGapsResetLearning() {
        val estimator = DischargeTimeEstimator()
        for (t in 0..30 step 3) estimator.read(t * 1000L)
        assertNull(estimator.read(33000, mode = "changed"))
        for (t in 36..66 step 3) estimator.read(t * 1000L, mode = "changed")
        assertNull(estimator.read(90000, mode = "changed"))
        assertNull(estimator.read(93000, onBattery = false))
        assertNull(estimator.read(96000, current = Double.NaN))
        assertNull(estimator.read(99000, current = null))
    }
    @Test fun repeatedUiReadsDoNotCreateAnArtificialObservationWindow() {
        val estimator = DischargeTimeEstimator()
        repeat(100) { assertNull(estimator.read(0)) }
        assertNull(estimator.read(3000))
    }
}
