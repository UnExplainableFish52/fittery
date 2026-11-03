package com.fittery.tid52

/** Reports a known connection only when its transition was observed. */
class ChargingConnection {
    var startedAt: Long? = null
        private set
    private var startedElapsed: Long? = null
    var confirmed = false
        private set

    fun reset() { startedAt = null; startedElapsed = null; confirmed = false }
    fun connected(wall: Long, elapsed: Long) {
        startedAt = wall; startedElapsed = elapsed; confirmed = true
    }
    fun observe(plugged: Boolean, wall: Long, elapsed: Long): Long? {
        if (!plugged) { reset(); return null }
        if (startedAt == null || elapsed < (startedElapsed ?: elapsed)) {
            startedAt = wall; startedElapsed = elapsed; confirmed = false
        }
        return (elapsed - (startedElapsed ?: elapsed)).coerceAtLeast(0)
    }
}
