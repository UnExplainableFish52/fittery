package com.fittery.tid52

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import kotlin.math.abs

/** Raw monitor recordings are independent of the legacy dashboard cache and its caps.
 * All calls run on BatteryEngine's serial worker. No bitmap graphs are stored. */
class MonitorStore(context: Context, private val clock: () -> Long = System::currentTimeMillis) :
    SQLiteOpenHelper(context, "monitor.db", null, 1) {
    companion object {
        const val RETENTION_MS = 30L * 86400000
        const val MAX_INTERVAL_MS = 15000L
        const val MIN_CHARGE_MS = 5L * 60000
        const val MIN_CHARGE_GAIN = 5
        private val metrics = listOf("temperatureC", "powerW", "currentMa", "voltageMv", "chargeCounterMah", "level")
    }
    private var forceGap = false
    private var lastCleanup: Long? = null

    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""CREATE TABLE recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, startTime INTEGER NOT NULL,
            endTime INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1,
            sampleCount INTEGER NOT NULL DEFAULT 0, startLevel INTEGER, endLevel INTEGER,
            observedMs INTEGER NOT NULL DEFAULT 0, gapCount INTEGER NOT NULL DEFAULT 0,
            maxTemperatureC REAL, peakTemperatureTime INTEGER, minPowerW REAL, maxPowerW REAL,
            powerWms REAL NOT NULL DEFAULT 0, powerMs INTEGER NOT NULL DEFAULT 0,
            above35Ms REAL NOT NULL DEFAULT 0, temperatureMs INTEGER NOT NULL DEFAULT 0,
            chargeMah REAL NOT NULL DEFAULT 0, dischargeMah REAL NOT NULL DEFAULT 0,
            currentMs INTEGER NOT NULL DEFAULT 0)""")
        db.execSQL("CREATE UNIQUE INDEX one_active_recording ON recordings(active) WHERE active=1")
        db.execSQL("CREATE INDEX recording_expiry ON recordings(active,startTime)")
        db.execSQL("""CREATE TABLE samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recordingId INTEGER NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
            time INTEGER NOT NULL, elapsed INTEGER NOT NULL, level INTEGER, plugged INTEGER NOT NULL,
            status TEXT, temperatureC REAL, powerW REAL, currentMa REAL, voltageMv REAL,
            chargeCounterMah REAL, convention TEXT, gapBefore INTEGER NOT NULL DEFAULT 0)""")
        db.execSQL("CREATE INDEX recording_samples ON samples(recordingId,id)")
        db.execSQL("CREATE INDEX recording_sample_time ON samples(recordingId,time)")
        db.execSQL("""CREATE TABLE charging (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recordingId INTEGER NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
            startTime INTEGER NOT NULL, endTime INTEGER NOT NULL, startLevel INTEGER, endLevel INTEGER,
            ended INTEGER NOT NULL DEFAULT 0, partial INTEGER NOT NULL DEFAULT 0,
            activeMs INTEGER NOT NULL DEFAULT 0, fullAt INTEGER,
            powerWms REAL NOT NULL DEFAULT 0, powerMs INTEGER NOT NULL DEFAULT 0)""")
        db.execSQL("CREATE INDEX recording_charging ON charging(recordingId,id)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    private fun Cursor.row(): MutableMap<String, Any?> = (0 until columnCount).associate { i ->
        getColumnName(i) to when {
            isNull(i) -> null
            getType(i) == Cursor.FIELD_TYPE_STRING -> getString(i)
            getType(i) == Cursor.FIELD_TYPE_INTEGER -> getLong(i)
            else -> getDouble(i)
        }
    }.toMutableMap()
    private fun Map<String, Any?>.n(key: String): Double? = (get(key) as? Number)?.toDouble()?.takeIf { it.isFinite() }
    private fun active(): MutableMap<String, Any?>? = readableDatabase.rawQuery("SELECT * FROM recordings WHERE active=1", null).use { if (it.moveToFirst()) it.row() else null }

    fun begin(time: Long = clock()): Long {
        active()?.let { forceGap = true; return (it["id"] as Number).toLong() }
        forceGap = false
        return writableDatabase.insertOrThrow("recordings", null, ContentValues().apply { put("startTime", time); put("endTime", time) })
    }

    fun finish(time: Long = clock()): Long? {
        val record = active() ?: return null
        val id = (record["id"] as Number).toLong()
        val db = writableDatabase
        db.beginTransaction()
        try {
            // A stop is an event, not an invented battery observation.
            db.execSQL("UPDATE recordings SET active=0,endTime=MAX(endTime,?) WHERE id=?", arrayOf(time, id))
            db.execSQL("UPDATE charging SET ended=1 WHERE recordingId=? AND ended=0", arrayOf(id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return id
    }

    fun cleanup(keepForever: Boolean, force: Boolean = false) {
        val now = clock()
        if (keepForever || !force && lastCleanup?.let { now - it in 0 until 3600000 } == true) return
        // Strictly never before creation + 30 days. Active recordings are protected.
        writableDatabase.delete("recordings", "active=0 AND startTime<=?", arrayOf((now - RETENTION_MS).toString()))
        lastCleanup = now
    }

    /** Integrals retain the sign, including a linear zero crossing. */
    private fun positiveArea(a: Double, b: Double, duration: Long): Double = when {
        a >= 0 && b >= 0 -> (a + b) * .5 * duration
        a <= 0 && b <= 0 -> 0.0
        a > 0 -> .5 * a * duration * a / (a - b)
        else -> .5 * b * duration * b / (b - a)
    }

    fun record(reading: Map<String, Any?>): Map<String, Any?>? {
        val db = writableDatabase
        val record = active() ?: return null
        val id = (record["id"] as Number).toLong()
        val time = (reading["time"] as Number).toLong()
        val elapsed = (reading["elapsed"] as Number).toLong()
        val plugged = (reading["plugged"] as Number).toInt()
        val prev = db.rawQuery("SELECT * FROM samples WHERE recordingId=? ORDER BY id DESC LIMIT 1", arrayOf(id.toString())).use { if (it.moveToFirst()) it.row() else null }
        val dt = elapsed - (prev?.n("elapsed")?.toLong() ?: elapsed)
        val wallDt = time - (prev?.n("time")?.toLong() ?: time)
        val changed = prev != null && (prev.n("plugged")?.toInt() != plugged || prev["status"] != reading["status"] ||
            prev.n("level") != reading.n("level") || prev["convention"] != reading["convention"] ||
            ((prev.n("temperatureC") ?: 0.0) > 35) != ((reading.n("temperatureC") ?: 0.0) > 35))
        if (!forceGap && prev != null && dt in 0 until 3000 && !changed) return null
        val continuous = prev != null && !forceGap && dt in 1..MAX_INTERVAL_MS && abs(wallDt - dt) < 2000 && prev["convention"] == reading["convention"]
        val gap = prev != null && !continuous
        val temp = reading.n("temperatureC")
        val power = reading.n("powerW")
        val current = reading.n("currentMa")
        val oldPower = prev?.n("powerW")
        val oldCurrent = prev?.n("currentMa")
        val oldTemp = prev?.n("temperatureC")
        val level = reading.n("level")?.toInt()
        var completedReport: Map<String, Any?>? = null
        db.beginTransaction()
        try {
            val sample = ContentValues().apply {
                put("recordingId", id); put("time", time); put("elapsed", elapsed); put("plugged", plugged)
                put("status", reading["status"] as? String); put("convention", reading["convention"] as? String)
                put("gapBefore", if (gap) 1 else 0)
                for (key in metrics) reading.n(key)?.let { put(key, it) }
            }
            db.insertOrThrow("samples", null, sample)
            val update = ContentValues().apply {
                put("endTime", maxOf(time, record.n("endTime")!!.toLong()))
                put("sampleCount", record.n("sampleCount")!!.toLong() + 1)
                put("endLevel", level)
                if (record.n("sampleCount") == 0.0) put("startLevel", level)
                put("gapCount", record.n("gapCount")!!.toLong() + if (gap) 1 else 0)
                if (temp != null && (record.n("maxTemperatureC") == null || temp > record.n("maxTemperatureC")!!)) {
                    put("maxTemperatureC", temp); put("peakTemperatureTime", time)
                }
                if (power != null) {
                    put("minPowerW", minOf(power, record.n("minPowerW") ?: power))
                    put("maxPowerW", maxOf(power, record.n("maxPowerW") ?: power))
                }
                if (continuous) {
                    put("observedMs", record.n("observedMs")!!.toLong() + dt)
                    if (oldPower != null && power != null) {
                        put("powerWms", record.n("powerWms")!! + (oldPower + power) * .5 * dt)
                        put("powerMs", record.n("powerMs")!!.toLong() + dt)
                    }
                    if (oldCurrent != null && current != null) {
                        put("chargeMah", record.n("chargeMah")!! + positiveArea(oldCurrent, current, dt) / 3600000)
                        put("dischargeMah", record.n("dischargeMah")!! + positiveArea(-oldCurrent, -current, dt) / 3600000)
                        put("currentMs", record.n("currentMs")!!.toLong() + dt)
                    }
                    if (oldTemp != null && temp != null) {
                        val fraction = when {
                            oldTemp > 35 && temp > 35 -> 1.0
                            oldTemp <= 35 && temp <= 35 -> 0.0
                            else -> (maxOf(oldTemp, temp) - 35) / abs(temp - oldTemp)
                        }
                        put("above35Ms", record.n("above35Ms")!! + dt * fraction)
                        put("temperatureMs", record.n("temperatureMs")!!.toLong() + dt)
                    }
                }
            }
            db.update("recordings", update, "id=?", arrayOf(id.toString()))
            val segment = db.rawQuery("SELECT * FROM charging WHERE recordingId=? AND ended=0", arrayOf(id.toString())).use { if (it.moveToFirst()) it.row() else null }
            if (segment != null) {
                if (plugged == 0) completedReport = mapOf(
                    "id" to segment["id"], "recordingId" to id, "startTime" to segment["startTime"],
                    "endTime" to if (continuous) time else prev!!.n("time")!!.toLong()
                )
                val values = ContentValues().apply {
                    put("endTime", if (continuous) time else prev!!.n("time")!!.toLong())
                    put("endLevel", if (continuous) level else prev?.n("level")?.toInt())
                    if (gap || plugged == 0) put("ended", 1)
                    if (gap) put("partial", 1)
                    if (continuous) {
                        if (prev?.get("status") == "Charging") put("activeMs", segment.n("activeMs")!!.toLong() + dt)
                        if (oldPower != null) {
                            val average = if (plugged > 0 && power != null) (oldPower + power) * .5 else oldPower
                            put("powerWms", segment.n("powerWms")!! + average * dt)
                            put("powerMs", segment.n("powerMs")!!.toLong() + dt)
                        }
                        if (reading["status"] == "Full" && segment["fullAt"] == null) put("fullAt", time)
                    }
                }
                db.update("charging", values, "id=?", arrayOf(segment["id"].toString()))
            }
            if (plugged > 0 && (segment == null || gap)) db.insertOrThrow("charging", null, ContentValues().apply {
                put("recordingId", id); put("startTime", time); put("endTime", time)
                put("startLevel", level); put("endLevel", level)
                put("partial", if (gap || prev == null) 1 else 0)
                if (reading["status"] == "Full") put("fullAt", time)
            })
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        forceGap = false
        return completedReport
    }

    fun list(since: Long?, until: Long?, before: Long?): Map<String, Any?> {
        val rows = mutableListOf<Map<String, Any?>>()
        readableDatabase.rawQuery("SELECT * FROM recordings WHERE endTime>=? AND startTime<? AND id<? ORDER BY id DESC LIMIT 51", arrayOf((since ?: 0).toString(), (until ?: Long.MAX_VALUE).toString(), (before ?: Long.MAX_VALUE).toString())).use { c ->
            while (c.moveToNext()) rows.add(c.row())
        }
        return mapOf("recordings" to rows.take(50), "hasMore" to (rows.size > 50))
    }


    fun detail(id: Long, since: Long? = null, until: Long? = null): Map<String, Any?> {
        val db = readableDatabase
        val record = db.rawQuery("SELECT * FROM recordings WHERE id=?", arrayOf(id.toString())).use { if (it.moveToFirst()) it.row() else error("Recording has expired or was deleted.") }
        val segments = mutableListOf<Map<String, Any?>>()
        db.rawQuery("SELECT * FROM charging WHERE recordingId=? ORDER BY id", arrayOf(id.toString())).use { c ->
            while (c.moveToNext()) {
                val row = c.row()
                val gain = row.n("endLevel")?.let { end -> row.n("startLevel")?.let { end - it } }
                // Filter only incidental summaries, never delete their raw samples.
                if (row.n("ended") == 0.0 || row.n("endTime")!! - row.n("startTime")!! >= MIN_CHARGE_MS || gain != null && gain >= MIN_CHARGE_GAIN) segments.add(row)
            }
        }
        val first = maxOf(record.n("startTime")!!.toLong(), since ?: Long.MIN_VALUE)
        val last = minOf(record.n("endTime")!!.toLong(), until ?: Long.MAX_VALUE)
        // Preserve first/last and extrema of each metric in a time bucket.
        // Only the response is reduced; every original sample remains in SQLite.
        val bucketMs = maxOf(3000L, (last - first) / 240)
        val points = mutableListOf<Map<String, Any?>>()
        var bucketFirst: MutableMap<String, Any?>? = null
        var bucketLast: MutableMap<String, Any?>? = null
        val minima = mutableMapOf<String, MutableMap<String, Any?>>()
        val maxima = mutableMapOf<String, MutableMap<String, Any?>>()
        var bucketId: Long? = null
        var continuity = 0L
        var responseCount = 0L
        var nullSignature: List<Boolean>? = null
        fun flush() {
            if (bucketFirst == null) return
            val keep = mutableSetOf(bucketFirst!!, bucketLast!!)
            keep.addAll(minima.values); keep.addAll(maxima.values)
            points.addAll(keep.sortedBy { (it["id"] as Number).toLong() })
            bucketFirst = null; bucketLast = null; minima.clear(); maxima.clear()
        }
        db.rawQuery("SELECT * FROM samples WHERE recordingId=? AND time>=? AND time<=? ORDER BY id", arrayOf(id.toString(), first.toString(), last.toString())).use { c ->
            while (c.moveToNext()) {
                val point = c.row()
                val index = (point.n("time")!!.toLong() - first) / bucketMs
                val signature = metrics.map { point[it] == null }
                if (point.n("gapBefore") == 1.0 || nullSignature != null && signature != nullSignature) continuity++
                if (bucketId != index) { flush(); bucketId = index }
                point["sessionId"] = continuity
                // Monotonic continuity groups already account for actual gaps;
                // a sparsely drawn long-range graph must not invent new gaps.
                point["monitorPoint"] = true
                if (bucketFirst == null) bucketFirst = point
                bucketLast = point
                for (key in metrics) point.n(key)?.let { value ->
                    if (value < (minima[key]?.n(key) ?: Double.POSITIVE_INFINITY)) minima[key] = point
                    if (value > (maxima[key]?.n(key) ?: Double.NEGATIVE_INFINITY)) maxima[key] = point
                }
                responseCount++; nullSignature = signature
            }
        }
        flush()
        return mapOf("recording" to record, "points" to points, "charging" to segments, "rangeSampleCount" to responseCount)
    }

    fun rename(id: Long, name: String) {
        val checked = name.trim().also { require(it.length in 1..80) { "Use a name of 1–80 characters." } }
        require(writableDatabase.update("recordings", ContentValues().apply { put("name", checked) }, "id=?", arrayOf(id.toString())) > 0) { "Recording no longer exists." }
    }
    fun delete(id: Long) {
        require(writableDatabase.delete("recordings", "id=? AND active=0", arrayOf(id.toString())) > 0) { "Stop monitoring before deleting this recording." }
    }
    fun clear() { writableDatabase.delete("recordings", null, null); forceGap = false }
}
