package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class CurrentNormalizerTest {
    @Test fun crossingFiftyThousandDoesNotCauseAThousandFoldSpike() {
        val normalizer = CurrentNormalizer()
        assertEquals(49.999, normalizer.normalize(0,49999,null,1,"Auto","Auto").ma!!,.0001)
        assertEquals(50.001, normalizer.normalize(3000,50001,null,1,"Auto","Auto").ma!!,.0001)
        assertEquals(40.0, normalizer.normalize(6000,40000,null,1,"Auto","Auto").ma!!,.0001)
    }
    @Test fun learnsNonstandardUnitsFromSustainedChargeCounterProgress() {
        val normalizer = CurrentNormalizer()
        var result: CurrentNormalizer.Result? = null
        for (i in 0..4) result = normalizer.normalize(i*30000L,600,2500.0 + i*5,1,"Auto","Auto")
        assertTrue(result!!.calibrated)
        assertEquals(1.0,result.divisor,.001)
        assertEquals(600.0,result.ma!!,.001)
    }
    @Test fun polarityCalibrationPreservesTemporaryNetDischargeWhilePluggedIn() {
        val normalizer = CurrentNormalizer()
        for (i in 0..4) normalizer.normalize(i*30000L,-600000,2500.0 + i*5,1,"Auto","Auto")
        val result = normalizer.normalize(150000,200000,2518.333,1,"Auto","Auto")
        assertTrue(result.inverted)
        assertEquals(-200.0,result.ma!!,.001)
    }
    @Test fun aSingleGaugeRecalibrationJumpCannotChangeTheCurrentUnit() {
        val normalizer = CurrentNormalizer()
        var result: CurrentNormalizer.Result? = null
        for (i in 0..40) result = normalizer.normalize(i*3000L,50000,if(i<20)2500.0 else 4000.0,1,"Auto","Auto")
        assertFalse(result!!.calibrated)
        assertEquals(1000.0,result.divisor,.001)
        assertEquals(50.0,result.ma!!,.001)
    }
    @Test fun unsupportedAndImplausibleSamplesRemainUnavailable() {
        val normalizer = CurrentNormalizer()
        assertNull(normalizer.normalize(0,Int.MIN_VALUE,null,1,"Auto","Auto").ma)
        assertNull(normalizer.normalize(0,Int.MAX_VALUE-1,null,1,"Auto","Auto").ma)
    }
}
