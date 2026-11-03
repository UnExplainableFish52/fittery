package com.fittery.tid52

import kotlin.math.exp

/** Time-weighted load, independent of UI refresh frequency. Times are monotonic. */
class DischargeTimeEstimator {
    private data class Sample(val time: Long, val current: Double)
    private val samples = ArrayDeque<Sample>()
    private var convention: String? = null
    private var lastUpdate = 0L
    private var endEstimate: Double? = null
    private var published: Long? = null

    fun reset() {
        samples.clear(); lastUpdate = 0; endEstimate = null; published = null
    }

    fun estimate(time: Long, discharging: Boolean, remainingMah: Double?, currentMa: Double?, mode: String): Long? {
        val previous = samples.lastOrNull()
        if (!discharging || remainingMah == null || !remainingMah.isFinite() || remainingMah <= 0 ||
            currentMa == null || !currentMa.isFinite() || currentMa > 0) {
            reset(); return null
        }
        if (convention != mode || previous != null && (time < previous.time || time - previous.time > 15000)) reset()
        convention = mode
        if (samples.lastOrNull()?.time != time) samples.addLast(Sample(time, -currentMa))
        // Retain the sample just before the window boundary for interpolation.
        val boundary = time - 120000
        while (samples.size > 2 && samples.elementAt(1).time <= boundary) samples.removeFirst()
        if (samples.size < 3 || time - samples.first().time < 30000) return null
        if (endEstimate != null && time - lastUpdate < 10000) return published?.let { (it - (time - lastUpdate)).coerceAtLeast(0) }
        var area = 0.0
        var duration = 0L
        samples.zipWithNext().forEach { (a, b) ->
            val start = maxOf(a.time, boundary)
            val dt = b.time - start
            if (dt > 0) {
                val atStart = a.current + (b.current - a.current) * (start - a.time).toDouble() / (b.time - a.time)
                area += (atStart + b.current) * .5 * dt
                duration += dt
            }
        }
        val average = if (duration > 0) area / duration else return null
        if (average < 10) { endEstimate = null; published = null; return null }
        val raw = remainingMah / average * 3600000
        if (!raw.isFinite() || raw !in 1000.0..604800000.0) return null
        val target = time + raw
        val old = endEstimate
        val weight = if (old == null) 1.0 else 1 - exp(-(time - lastUpdate).toDouble() / 90000)
        endEstimate = if (old == null) target else old + weight * (target - old)
        lastUpdate = time
        published = (endEstimate!! - time).toLong().coerceAtLeast(0)
        return published
    }
}
