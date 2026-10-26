package com.fittery.tid52

import kotlin.math.exp

/** Small rolling window, using measured progress rather than a fixed ETA. */
class ChargeTimeEstimator {
    data class Sample(val time: Long, val level: Int?, val counter: Double?, val source: Int, val charging: Boolean, val currentMa: Double? = null)
    data class Estimate(val millis: Long, val source: String)
    private val samples = ArrayDeque<Sample>()
    private var smoothedEnd: Double? = null
    private var lastEstimateAt = 0L
    val observedSeconds: Long get() = if (samples.size < 2) 0 else (samples.last().time - samples.first().time) / 1000
    val recentMedianCurrent: Double? get() {
        val last = samples.lastOrNull() ?: return null
        val recent = samples.filter { it.time >= last.time - 60000 && it.currentMa?.isFinite() == true }
        if (recent.size < 8 || recent.last().time - recent.first().time < 30000) return null
        val values = recent.map { it.currentMa!! }.sorted()
        return values[values.size / 2]
    }

    fun observe(sample: Sample) {
        val previous = samples.lastOrNull()
        if (!sample.charging || sample.source == 0) { reset(); return }
        if (previous != null && (sample.time < previous.time || sample.time - previous.time > 120000 || sample.source != previous.source)) reset()
        val last = samples.lastOrNull()
        if (last != null && sample.time - last.time < 1000 && sample.level == last.level) return
        samples.addLast(sample)
        while (samples.size > 600 || (samples.firstOrNull()?.time ?: sample.time) < sample.time - 600000) samples.removeFirst()
    }

    fun restore(past: List<Sample>) {
        val merged = (past + samples).distinctBy { it.time }.sortedBy { it.time }
        reset()
        merged.forEach(::observe)
    }

    fun forgetCurrentRates() {
        val retained = samples.map { it.copy(currentMa = null) }
        samples.clear(); samples.addAll(retained)
        smoothedEnd = null; lastEstimateAt = 0
    }

    private fun reset() { samples.clear(); smoothedEnd = null; lastEstimateAt = 0 }

    fun estimate(fullCapacityMah: Double?): Estimate? {
        val first = samples.firstOrNull() ?: return null
        val last = samples.last()
        if (last.level == null || last.level >= 100) return null
        val medianCurrent = recentMedianCurrent
        if (medianCurrent != null && medianCurrent <= 0) return null
        // One average per 30 seconds prevents foreground's denser sampling from
        // outweighing background readings. Regression smooths quantized gauges.
        fun slope(value: (Sample) -> Double?): Double? {
            val buckets = samples.groupBy { it.time / 30000 }.values.mapNotNull { bucket ->
                val valid = bucket.mapNotNull { sample -> value(sample)?.takeIf(Double::isFinite)?.let { Pair(sample.time.toDouble(), it) } }
                if (valid.isEmpty()) null else Pair(valid.map { it.first - first.time }.average(), valid.map { it.second }.average())
            }
            if (buckets.size < 4) return null
            val x = buckets.map { it.first }.average()
            val y = buckets.map { it.second }.average()
            val variance = buckets.sumOf { (it.first - x) * (it.first - x) }
            if (variance <= 0) return null
            return (buckets.sumOf { (it.first - x) * (it.second - y) } / variance).takeIf { it > 0 && it.isFinite() }
        }
        var duration: Double? = null
        var source = ""
        val full = BatteryHardwareValues.validCapacity(fullCapacityMah)
        val counter = last.counter?.takeIf { it.isFinite() && it > 0 }
        val earlier = samples.lastOrNull { it.time <= last.time - 90000 }
        if (observedSeconds >= 120 && full != null && counter != null && counter < full && earlier?.counter != null && counter > earlier.counter) {
            val rate = slope { it.counter }
            if (rate != null) { duration = (full - counter) / rate; source = "Recent charge-counter progress; charging may slow near full" }
        }
        if (duration == null && observedSeconds >= 120 && first.level != null && last.level - first.level >= 2 && earlier?.level != null && last.level > earlier.level) {
            val rate = slope { it.level?.toDouble() }
            if (rate != null) { duration = (100 - last.level) / rate; source = "Recent battery-level progress; charging may slow near full" }
        }
        if (duration == null && full != null && medianCurrent != null && medianCurrent > 10) {
            val remaining = if (counter != null && counter < full) full - counter else full * (100 - last.level) / 100
            duration = remaining / medianCurrent * 3600000
            source = "Provisional estimate at recent net current; charging can slow near full"
        }
        val raw = duration?.takeIf { it.isFinite() && it in 1000.0..259200000.0 } ?: return null
        val end = last.time + raw
        val previousEnd = smoothedEnd
        val weight = if (previousEnd == null) 1.0 else 1 - exp(-(last.time - lastEstimateAt).coerceAtLeast(0) / 60000.0)
        smoothedEnd = if (previousEnd == null) end else previousEnd + weight * (end - previousEnd)
        lastEstimateAt = last.time
        return Estimate((smoothedEnd!! - last.time).toLong().coerceAtLeast(0), source)
    }
}
