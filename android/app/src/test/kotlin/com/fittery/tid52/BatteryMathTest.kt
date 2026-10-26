package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class BatteryMathTest {
    @Test fun ongoingAlarmsEndOnlyWhenTheirConditionResolvesOrTheyAreDisabled() {
        val settings = mapOf<String, Any?>("chargeAlert" to true, "chargeLimit" to 80, "lowAlert" to true, "lowLimit" to 20, "heatAlert" to true, "heatLimit" to 40)
        assertEquals(1, BatteryMath.retainActiveAlerts(1, true, 85, 30.0, settings))
        assertEquals(0, BatteryMath.retainActiveAlerts(1, false, 85, 30.0, settings))
        assertEquals(0, BatteryMath.retainActiveAlerts(1, true, 85, 30.0, settings + ("chargeAlert" to false)))
        assertEquals(0, BatteryMath.retainActiveAlerts(1, true, 85, 30.0, settings + ("chargeLimit" to 90)))
        assertEquals(2, BatteryMath.retainActiveAlerts(2, false, 15, 30.0, settings))
        assertEquals(0, BatteryMath.retainActiveAlerts(2, true, 15, 30.0, settings))
        assertEquals(4, BatteryMath.retainActiveAlerts(4, false, 60, 39.0, settings))
        assertEquals(0, BatteryMath.retainActiveAlerts(4, false, 60, 37.0, settings))
    }

    @Test fun changingATargetRearmsItsAlertWithoutResettingOtherAlerts() {
        val before = mapOf<String, Any?>("chargeAlert" to true, "chargeLimit" to 80, "heatAlert" to true, "heatLimit" to 40)
        assertEquals(6, BatteryMath.rearmForSettings(7, before, before + ("chargeLimit" to 85)))
        assertEquals(3, BatteryMath.rearmForSettings(7, before, before + ("heatLimit" to 45)))
        assertEquals(7, BatteryMath.rearmForSettings(7, before, before + ("chargeLimit" to 80L) + ("sound" to false)))
        val disabled = before + ("chargeAlert" to false)
        assertEquals(6, BatteryMath.rearmForSettings(7, disabled, before))
    }

    @Test fun usesConsistentSignedUnitsAndTheElectricalPowerFormula() {
        fun current(raw: Int, unit: String) = CurrentNormalizer().normalize(0, raw, null, 1, unit, "Standard").ma
        assertEquals(545.0, current(545000,"Auto")!!, .001)
        assertEquals(-3200.0, current(-3200000,"Auto")!!, .001)
        assertEquals(-545.0, current(-545,"mA")!!, .001)
        assertEquals(12.0, current(12000,"µA")!!, .001)
        assertNull(current(Int.MIN_VALUE,"Auto"))
        assertEquals(-2.273195, BatteryMath.power(4171,-545.0)!!, .000001)
    }

    @Test fun explicitlySelectingAnAlreadyReachedTargetRearmsIt() {
        val settings = mapOf<String, Any?>("chargeAlert" to true, "chargeLimit" to 80)
        val mask = BatteryMath.rearmForSettings(1, settings, settings, "chargeLimit")
        assertEquals(0, mask)
        assertEquals(1, BatteryMath.alertMask(mask, true, false, 88, 30.0, true, 80, false, 20, false, 40).second)
        assertEquals(1, BatteryMath.rearmForSettings(1, settings, settings, "fahrenheit"))
    }
    @Test fun firesOncePerSessionAndCatchesSkippedThresholds() {
        fun evaluate(mask: Int, plugged: Boolean, charging: Boolean, level: Int, temp: Double = 30.0) =
            BatteryMath.alertMask(mask,plugged,charging,level,temp,true,80,true,20,true,40)
        val first = evaluate(0,true,true,81)
        assertEquals(1,first.second)
        assertEquals(0,evaluate(first.first,true,true,81).second)
        val unplugged = evaluate(first.first,false,false,79)
        assertEquals(0,unplugged.first and 1)
        assertEquals(1,evaluate(unplugged.first,true,true,80).second)
        val low = evaluate(0,false,false,19)
        assertEquals(2,low.second)
        assertEquals(0,evaluate(low.first,false,false,18).second)
        val hot = evaluate(0,true,true,50,41.0)
        assertEquals(4,hot.second)
        assertEquals(0,evaluate(hot.first,true,true,50,40.0).second)
        val cooled = evaluate(hot.first,true,true,50,37.0)
        assertEquals(4,evaluate(cooled.first,true,true,50,41.0).second)
    }
}
