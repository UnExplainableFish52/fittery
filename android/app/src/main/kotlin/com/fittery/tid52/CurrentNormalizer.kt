package com.fittery.tid52

import kotlin.math.abs

/** Uses one stable unit/polarity convention; never guesses from one sample's magnitude. */
class CurrentNormalizer(initialDivisor: Double = 1000.0, initialInverted: Boolean = false) {
    data class Result(val ma: Double?, val divisor: Double, val inverted: Boolean, val calibrated: Boolean, val note: String?)
    private data class Observation(val time: Long, val raw: Int, val counter: Double, val source: Int)
    private val observations = ArrayDeque<Observation>()
    var divisor = initialDivisor
        private set
    var inverted = initialInverted
        private set
    private var calibrated = false
    private var candidate: Pair<Double, Boolean>? = null
    private var confirmations = 0

    fun resetCalibration() { divisor = 1000.0; inverted = false; calibrated = false; observations.clear(); candidate = null; confirmations = 0 }

    fun normalize(time: Long, raw: Int, counterMah: Double?, source: Int, unit: String, polarity: String): Result {
        if (raw == Int.MIN_VALUE || raw == Int.MAX_VALUE) return Result(null, divisor, inverted, calibrated, "Current sensor unavailable")
        if (!calibrated && counterMah != null && counterMah.isFinite() && counterMah > 0) {
            val previous = observations.lastOrNull()
            if (previous != null && (time < previous.time || time - previous.time > 120000 || source != previous.source)) observations.clear()
            if (observations.lastOrNull()?.let { time - it.time >= 3000 } != false) observations.addLast(Observation(time, raw, counterMah, source))
            while (observations.size > 120 || (observations.firstOrNull()?.time ?: time) < time - 180000) observations.removeFirst()
            val first = observations.firstOrNull()
            if (first != null && time - first.time >= 60000 && abs(counterMah - first.counter) >= 2) {
                var integral = 0.0
                for (i in 1 until observations.size) {
                    val a = observations[i-1]; val b = observations[i]
                    integral += (a.raw.toDouble() + b.raw) / 2 * (b.time - a.time)
                }
                val meanRaw = integral / (time - first.time)
                val counterRateMa = (counterMah - first.counter) * 3600000 / (time - first.time)
                val ratio = abs(meanRaw / counterRateMa)
                val detected = when (ratio) { in 200.0..5000.0 -> 1000.0; in .2..5.0 -> 1.0; else -> null }
                val steps = observations.zipWithNext().map { (a,b) -> b.counter - a.counter }.filter { abs(it) > .001 }
                val consistent = steps.size >= 3 && steps.count { it * counterRateMa > 0 } >= steps.size * .8
                if (detected != null && abs(meanRaw) > 0 && consistent) {
                    val next = detected to (meanRaw * counterRateMa < 0)
                    if (next == candidate) confirmations++ else { candidate = next; confirmations = 1 }
                    if (confirmations >= 2) { divisor = next.first; inverted = next.second; calibrated = true }
                } else { candidate = null; confirmations = 0 }
            }
        }
        val scale = when (unit) { "mA" -> 1.0; "µA" -> 1000.0; else -> divisor }
        val reverse = when (polarity) { "Inverted" -> true; "Standard" -> false; else -> inverted }
        val current = raw / scale * if (reverse) -1 else 1
        // Unsupported sentinels or incompatible overrides must not appear as
        // spectacular smartphone power readings. Keep the raw value in diagnostics.
        val valid = current.takeIf { it.isFinite() && abs(it) <= 50000 }
        return Result(valid, scale, reverse, calibrated, if (valid == null) "Current outside supported range; check unit override" else null)
    }
}
