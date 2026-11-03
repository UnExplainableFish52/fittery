package com.fittery.tid52

import org.junit.Assert.*
import org.junit.Test

class ChargingConnectionTest {
    @Test fun firstObservationDoesNotInventAConnectionTime() {
        val connection = ChargingConnection()
        assertEquals(0L, connection.observe(true, 100000, 1000))
        assertEquals(100000L, connection.startedAt)
        assertFalse(connection.confirmed)
    }
    @Test fun observedConnectionKeepsItsTimeAndUsesMonotonicDuration() {
        val connection = ChargingConnection()
        connection.connected(100000, 1000)
        assertEquals(5000L, connection.observe(true, 500000, 6000))
        assertTrue(connection.confirmed)
        assertEquals(100000L, connection.startedAt)
        assertNull(connection.observe(false, 500000, 7000))
        assertNull(connection.startedAt)
        assertFalse(connection.confirmed)
    }
    @Test fun observationGapsAndMonotonicResetsLoseTheirConnectionClaim() {
        val connection = ChargingConnection()
        connection.connected(100000, 1000)
        connection.reset()
        connection.observe(true, 200000, 5000)
        assertFalse(connection.confirmed)
        assertEquals(200000L, connection.startedAt)
        assertEquals(0L, connection.observe(true, 300000, 100))
        assertEquals(300000L, connection.startedAt)
    }
}
