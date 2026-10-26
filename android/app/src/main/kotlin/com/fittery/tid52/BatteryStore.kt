package com.fittery.tid52

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs

/** Accessed only on BatteryEngine's single worker. No database work on the UI thread. */
class BatteryStore(context: Context, private val clock: () -> Long = System::currentTimeMillis) : SQLiteOpenHelper(context, "battery.db", null, 3) {
    companion object {
        const val RETENTION_MS = 3L * 86400000
        const val SESSION_LIMIT = 10
    }
    private var last: Map<String, Any?>? = null
    private var activeId: Long? = null
    private var lastPrune = 0L

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE sessions (id INTEGER PRIMARY KEY, kind TEXT, source INTEGER, startTime INTEGER, endTime INTEGER, startLevel INTEGER, endLevel INTEGER, powerSum REAL DEFAULT 0, powerCount INTEGER DEFAULT 0, gap INTEGER DEFAULT 0, ended INTEGER DEFAULT 0, powerWms REAL DEFAULT 0, powerMs INTEGER DEFAULT 0)")
        db.execSQL("CREATE TABLE points (time INTEGER PRIMARY KEY, sessionId INTEGER, level INTEGER, temperatureC REAL, powerW REAL, plugged INTEGER, status TEXT, voltageMv REAL, currentMa REAL, chargeCounterMah REAL)")
        db.execSQL("CREATE INDEX point_session ON points(sessionId)")
        createDaily(db)
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE sessions ADD COLUMN powerWms REAL DEFAULT 0")
            db.execSQL("ALTER TABLE sessions ADD COLUMN powerMs INTEGER DEFAULT 0")
            for (column in listOf("voltageMv", "currentMa", "chargeCounterMah")) {
                db.execSQL("ALTER TABLE points ADD COLUMN $column REAL")
            }
        }
        if (oldVersion < 3) {
            // Old global totals cannot be attributed to sessions. Rebuild from
            // retained observations once, without inventing missing intervals.
            db.execSQL("DROP TABLE daily")
            createDaily(db)
            deleteExpired(db, clock())
            db.execSQL("DELETE FROM points WHERE sessionId NOT IN (SELECT id FROM sessions)")
            rebuildDaily(db)
        }
    }

    private fun createDaily(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE daily (sessionId INTEGER NOT NULL, day TEXT NOT NULL, charged REAL DEFAULT 0, pluggedMs INTEGER DEFAULT 0, PRIMARY KEY(sessionId,day))")
    }

    /** Whole sessions expire 72 hours after their start, or when outside the latest ten. */
    private fun deleteExpired(db: SQLiteDatabase, now: Long): Set<Long> {
        val ids = mutableSetOf<Long>()
        db.rawQuery("SELECT id FROM sessions WHERE startTime < ? OR id NOT IN (SELECT id FROM sessions ORDER BY id DESC LIMIT $SESSION_LIMIT)", arrayOf((now - RETENTION_MS).toString())).use { c ->
            while (c.moveToNext()) ids.add(c.getLong(0))
        }
        for (batch in ids.toList().chunked(500)) {
            val placeholders = batch.joinToString(",") { "?" }
            val args = batch.map(Long::toString).toTypedArray()
            db.delete("points", "sessionId IN ($placeholders)", args)
            db.delete("daily", "sessionId IN ($placeholders)", args)
            db.delete("sessions", "id IN ($placeholders)", args)
        }
        return ids
    }

    private fun prune(db: SQLiteDatabase, now: Long, force: Boolean = false) {
        if (!force && now - lastPrune in 0 until 60000L) return
        val removed: Set<Long>
        db.beginTransaction()
        try {
            removed = deleteExpired(db, now)
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        lastPrune = now
        if (activeId in removed) { activeId = null; last = null }
    }

    fun record(reading: Map<String, Any?>) {
        val db = writableDatabase
        val time = (reading["time"] as Number).toLong()
        prune(db, time)
        val level = (reading["level"] as Number?)?.toInt()
        val plugged = (reading["plugged"] as Number).toInt()
        val kind = if (plugged > 0) "Charging" else "Discharging"
        val power = (reading["powerW"] as Number?)?.toDouble()?.takeIf { it.isFinite() }
        var previous = last
        if (previous == null) {
            db.rawQuery("SELECT * FROM sessions ORDER BY id DESC LIMIT 1", null).use { c ->
                if (c.moveToFirst() && c.getInt(c.getColumnIndexOrThrow("ended")) == 0) {
                    activeId = c.getLong(c.getColumnIndexOrThrow("id"))
                    previous = mapOf(
                        "time" to c.getLong(c.getColumnIndexOrThrow("endTime")),
                        "level" to if (c.isNull(c.getColumnIndexOrThrow("endLevel"))) null else c.getInt(c.getColumnIndexOrThrow("endLevel")),
                        "plugged" to c.getInt(c.getColumnIndexOrThrow("source")),
                        "powerW" to db.rawQuery("SELECT powerW FROM points WHERE sessionId=? ORDER BY time DESC LIMIT 1", arrayOf(activeId.toString())).use { point ->
                            if (point.moveToFirst() && !point.isNull(0)) point.getDouble(0) else null
                        }
                    )
                }
            }
        }
        val previousSource = (previous?.get("plugged") as Number?)?.toInt()
        val interval = HistoryInterval.between(
            (previous?.get("time") as Number?)?.toLong(), previousSource,
            (previous?.get("level") as Number?)?.toInt(), time, plugged, level
        )
        val gap = interval.gap
        val previousId = activeId
        val previousPrune = lastPrune
        if (previous != null && interval.elapsed == 0L && !interval.sourceChanged) return
        db.beginTransaction()
        try {
            val previousPower = (previous?.get("powerW") as? Number)?.toDouble()?.takeIf { it.isFinite() }
            if (!gap && interval.elapsed > 0 && previousId != null && previousPower != null) {
                val average = if (!interval.sourceChanged && power != null) (abs(previousPower) + abs(power)) / 2 else abs(previousPower)
                db.execSQL("UPDATE sessions SET powerWms=powerWms+?, powerMs=powerMs+? WHERE id=?", arrayOf<Any>(average * interval.elapsed, interval.elapsed, previousId))
            }
            val startsSession = activeId == null || interval.sourceChanged || gap
            if (startsSession) {
                activeId?.let { oldId ->
                    val close = ContentValues().apply {
                        put("ended", 1)
                        if (gap) put("gap", 1) else {
                            put("endTime", time)
                            level?.let { put("endLevel", it) }
                        }
                    }
                    db.update("sessions", close, "id=?", arrayOf(oldId.toString()))
                }
                val values = ContentValues().apply {
                    put("kind", kind); put("source", plugged); put("startTime", time); put("endTime", time)
                    if (level == null) { putNull("startLevel"); putNull("endLevel") }
                    else { put("startLevel", level); put("endLevel", level) }
                }
                activeId = db.insertOrThrow("sessions", null, values)
            }
            val update = ContentValues().apply {
                put("endTime", time)
                if (level == null) putNull("endLevel") else put("endLevel", level)
            }
            db.update("sessions", update, "id=?", arrayOf(activeId.toString()))
            if (power != null) db.execSQL("UPDATE sessions SET powerSum=powerSum+?, powerCount=powerCount+1 WHERE id=?", arrayOf<Any?>(abs(power), activeId))
            val point = ContentValues().apply {
                put("time", time); put("sessionId", activeId); put("plugged", plugged); put("status", reading["status"] as String)
                if (level == null) putNull("level") else put("level", level)
                (reading["temperatureC"] as Number?)?.let { put("temperatureC", it.toDouble()) }
                power?.let { put("powerW", it) }
                for (key in listOf("voltageMv", "currentMa", "chargeCounterMah")) {
                    (reading[key] as? Number)?.toDouble()?.takeIf { it.isFinite() }?.let { put(key, it) }
                }
            }
            db.insertWithOnConflict("points", null, point, SQLiteDatabase.CONFLICT_REPLACE)
            if (!gap && interval.elapsed > 0 && previousId != null) {
                dailyParts(time, interval) { day, gain, duration -> addDaily(db, previousId, day, gain, duration) }
            }
            if (startsSession) {
                // Enforce the count cap immediately, inside the recording transaction.
                deleteExpired(db, time)
                lastPrune = time
            }
            db.setTransactionSuccessful()
        } catch (e: Exception) {
            activeId = previousId
            lastPrune = previousPrune
            throw e
        } finally { db.endTransaction() }
        last = reading
    }

    private fun addDaily(db: SQLiteDatabase, sessionId: Long, day: String, charged: Double, duration: Long) {
        db.execSQL("INSERT OR IGNORE INTO daily(sessionId,day) VALUES(?,?)", arrayOf<Any>(sessionId,day))
        db.execSQL("UPDATE daily SET charged=charged+?, pluggedMs=pluggedMs+? WHERE sessionId=? AND day=?", arrayOf<Any>(charged,duration,sessionId,day))
    }

    private fun dailyParts(time: Long, interval: HistoryInterval, consume: (String, Double, Long) -> Unit) {
        val start = time - interval.elapsed
        val midnight = java.util.Calendar.getInstance().apply {
            timeInMillis = time; set(java.util.Calendar.HOUR_OF_DAY,0); set(java.util.Calendar.MINUTE,0); set(java.util.Calendar.SECOND,0); set(java.util.Calendar.MILLISECOND,0)
        }.timeInMillis
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        consume(format.format(Date(time)), interval.chargedPercent.toDouble(), if (start < midnight) (time - midnight).coerceAtMost(interval.pluggedMs) else interval.pluggedMs)
        if (interval.pluggedMs > 0 && start < midnight) consume(format.format(Date(start)), 0.0, midnight - start)
    }

    private fun rebuildDaily(db: SQLiteDatabase) {
        val totals = mutableMapOf<Pair<Long, String>, Pair<Double, Long>>()
        var previousTime: Long? = null
        var previousSource: Int? = null
        var previousLevel: Int? = null
        var previousId: Long? = null
        var previousEnd: Long? = null
        var previousGap = false
        db.rawQuery("SELECT p.time,p.sessionId,p.level,p.plugged,s.endTime,s.gap FROM points p JOIN sessions s ON s.id=p.sessionId ORDER BY p.time", null).use { c ->
            while (c.moveToNext()) {
                val time = c.getLong(0)
                val id = c.getLong(1)
                val level = if (c.isNull(2)) null else c.getInt(2)
                val source = c.getInt(3)
                val interval = HistoryInterval.between(previousTime, previousSource, previousLevel, time, source, level)
                val owner = previousId
                val observedSwitch = interval.sourceChanged && !previousGap && previousEnd == time
                if (!interval.gap && interval.elapsed > 0 && owner != null && (owner == id || observedSwitch)) {
                    dailyParts(time, interval) { day, gain, duration ->
                        val key = owner to day
                        val total = totals[key] ?: (0.0 to 0L)
                        totals[key] = total.first + gain to total.second + duration
                    }
                }
                previousTime = time; previousId = id; previousLevel = level; previousSource = source
                previousEnd = c.getLong(4); previousGap = c.getInt(5) == 1
            }
        }
        for ((key, total) in totals) addDaily(db, key.first, key.second, total.first, total.second)
    }

    fun history(isRecording: Boolean): Map<String, Any?> {
        val db = writableDatabase
        val now = clock()
        prune(db, now, force = true)
        val points = mutableListOf<Map<String, Any?>>()
        db.rawQuery("SELECT * FROM points WHERE time>=? AND time<=? ORDER BY time", arrayOf((now - 3600000).toString(), now.toString())).use { c ->
            while (c.moveToNext()) points.add((0 until c.columnCount).associate { i ->
                c.getColumnName(i) to if (c.isNull(i)) null else if (c.getType(i) == android.database.Cursor.FIELD_TYPE_STRING) c.getString(i) else c.getDouble(i)
            })
        }
        val sessions = mutableListOf<Map<String, Any?>>()
        db.rawQuery("SELECT * FROM sessions ORDER BY id DESC LIMIT $SESSION_LIMIT", null).use { c ->
            while (c.moveToNext()) {
                val row = mutableMapOf<String, Any?>()
                for (i in 0 until c.columnCount) row[c.getColumnName(i)] = when {
                    c.isNull(i) -> null
                    c.getType(i) == android.database.Cursor.FIELD_TYPE_STRING -> c.getString(i)
                    else -> c.getDouble(i)
                }
                val id = (row["id"] as Number).toLong()
                val count = (row["powerCount"] as Number).toInt()
                val powerMs = (row["powerMs"] as Number).toLong()
                row["averagePowerW"] = if (powerMs > 0) (row["powerWms"] as Number).toDouble() / powerMs else if (count > 0) (row["powerSum"] as Number).toDouble() / count else null
                row["averagePowerKind"] = if (powerMs > 0) "time average" else if (count > 1) "sample average" else "single reading"
                row["active"] = id == activeId && isRecording && now - (row["endTime"] as Number).toLong() < 120000
                if (id == activeId) row["status"] = last?.get("status") as? String
                row["gap"] = (row["gap"] as Number).toInt() == 1
                sessions.add(row)
            }
        }
        val daily = mutableListOf<Map<String, Any?>>()
        db.rawQuery("SELECT day,SUM(charged),SUM(pluggedMs) FROM daily GROUP BY day ORDER BY day DESC", null).use { c ->
            while (c.moveToNext()) daily.add(mapOf("day" to c.getString(0), "charged" to c.getDouble(1), "pluggedMs" to c.getLong(2)))
        }
        return mapOf("points" to points, "sessions" to sessions, "daily" to daily)
    }

    fun recentChargingSamples(): List<ChargeTimeEstimator.Sample> {
        val samples = mutableListOf<ChargeTimeEstimator.Sample>()
        val now = clock()
        val db = writableDatabase
        prune(db, now, force = true)
        db.rawQuery("SELECT time,level,chargeCounterMah,plugged,status FROM points WHERE time>=? AND time<=? ORDER BY time", arrayOf((now - 600000).toString(), now.toString())).use { c ->
            while (c.moveToNext()) samples.add(ChargeTimeEstimator.Sample(
                c.getLong(0), if (c.isNull(1)) null else c.getInt(1), if (c.isNull(2)) null else c.getDouble(2), c.getInt(3), c.getString(4) == "Charging"
            ))
        }
        return samples
    }

    fun clear() {
        val db = writableDatabase
        db.beginTransaction()
        try { db.delete("points",null,null); db.delete("sessions",null,null); db.delete("daily",null,null); db.setTransactionSuccessful() }
        finally { db.endTransaction() }
        last = null; activeId = null; lastPrune = 0L
    }

    fun endSession() {
        activeId?.let { writableDatabase.execSQL("UPDATE sessions SET ended=1, gap=1 WHERE id=?", arrayOf(it)) }
        last = null; activeId = null
    }
}
