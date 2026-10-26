package com.fittery.tid52

/** Describes the observed interval ending at a sample or power-source event. */
data class HistoryInterval(
    val elapsed: Long,
    val gap: Boolean,
    val sourceChanged: Boolean,
    val chargedPercent: Int,
    val pluggedMs: Long
) {
    companion object {
        fun between(
            previousTime: Long?, previousSource: Int?, previousLevel: Int?,
            time: Long, source: Int, level: Int?
        ): HistoryInterval {
            val elapsed = previousTime?.let { time - it } ?: 0L
            val gap = previousTime != null && (elapsed < 0 || elapsed > 120000)
            val observed = previousTime != null && previousSource != null && !gap
            // The previous power state held until the new event. In particular,
            // retain the final charging interval when the charger is unplugged.
            val wasPlugged = observed && previousSource!! > 0
            val gain = if (wasPlugged && previousLevel != null && level != null)
                (level - previousLevel).coerceAtLeast(0) else 0
            return HistoryInterval(
                elapsed, gap, previousSource != null && previousSource != source,
                gain, if (wasPlugged) elapsed else 0L
            )
        }
    }
}
