package com.fittery.tid52

import android.app.Application
import android.content.Context
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.SQLiteMode
import java.util.Calendar
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE, application = Application::class)
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class BatteryStoreTest {
    private lateinit var context: Context
    private lateinit var store: BatteryStore
    private var now = 1792977300000L
    private lateinit var originalZone: TimeZone

    @Before fun setup() {
        originalZone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("battery.db")
        store = BatteryStore(context) { now }
    }
    @After fun cleanup() { store.close(); TimeZone.setDefault(originalZone) }

    private fun record(time: Long, level: Int, plugged: Int, power: Double = 4.0) {
        now = time
        store.record(mapOf(
            "time" to time, "level" to level, "plugged" to plugged,
            "status" to if (plugged > 0) "Charging" else "Discharging",
            "powerW" to power, "temperatureC" to 31.2,
            "voltageMv" to 4100, "currentMa" to power * 1000000 / 4100,
            "chargeCounterMah" to level * 50.0
        ))
    }
    @Suppress("UNCHECKED_CAST")
    private fun rows(history: Map<String, Any?>, key: String) = history[key] as List<Map<String, Any?>>

    private fun legacyPoints(db: android.database.sqlite.SQLiteDatabase) {
        db.execSQL("ALTER TABLE points RENAME TO upgraded_points")
        db.execSQL("CREATE TABLE points (time INTEGER PRIMARY KEY, sessionId INTEGER, level INTEGER, temperatureC REAL, powerW REAL, plugged INTEGER, status TEXT, voltageMv REAL, currentMa REAL, chargeCounterMah REAL)")
        db.execSQL("INSERT INTO points SELECT time,sessionId,level,temperatureC,powerW,plugged,status,voltageMv,currentMa,chargeCounterMah FROM upgraded_points")
        db.execSQL("DROP TABLE upgraded_points")
        db.execSQL("CREATE INDEX point_session ON points(sessionId)")
    }

    @Test fun freshDatabaseContainsNoSeededHistory() {
        val history = store.history(true)
        for (key in listOf("points", "sessions", "daily")) assertTrue(rows(history, key).isEmpty())
    }

    @Test fun actualSamplesDriveSessionsTotalsAndTimeWeightedPower() {
        val start = now
        record(start, 59, 1, 10.0)
        record(start + 30000, 60, 1, 8.0)
        record(start + 60000, 61, 0, -2.0)
        val history = store.history(true)
        val sessions = rows(history, "sessions")
        assertEquals(2, sessions.size)
        assertEquals("Discharging", sessions[0]["kind"])
        assertEquals(true, sessions[0]["active"])
        assertEquals(61.0, sessions[1]["endLevel"])
        assertEquals((start + 60000).toDouble(), sessions[1]["endTime"])
        assertEquals(8.5, (sessions[1]["averagePowerW"] as Number).toDouble(), .0001)
        val day = rows(history, "daily").single()
        assertEquals(2.0, (day["charged"] as Number).toDouble(), .0001)
        assertEquals(60000, (day["pluggedMs"] as Number).toInt())
        val points = rows(history, "points")
        assertEquals(3, points.size)
        assertEquals(4100.0, points.first()["voltageMv"])
        assertEquals(31.2, points.first()["temperatureC"])
    }

    @Test fun historySurvivesReopeningAndContinuesTheActiveSession() {
        val start = now
        record(start, 80, 0, -2.0)
        record(start + 30000, 79, 0, -2.0)
        store.close()
        store = BatteryStore(context) { now }
        assertEquals(2, rows(store.history(true), "points").size)
        record(start + 60000, 79, 0, -2.0)
        assertEquals(1, rows(store.history(true), "sessions").size)
        assertEquals(3, rows(store.history(true), "points").size)
    }

    @Test fun gapsAndRepeatedSamplesDoNotManufactureTotals() {
        val start = now
        record(start, 50, 1)
        record(start, 50, 1)
        assertEquals(1, rows(store.history(true), "points").size)
        record(start + 180000, 90, 1)
        val history = store.history(true)
        assertEquals(2, rows(history, "sessions").size)
        assertEquals(true, rows(history, "sessions")[1]["gap"])
        assertTrue(rows(history, "daily").isEmpty())
    }

    @Test fun midnightSplitsObservedPluggedTimeAcrossTheCorrectDays() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Kathmandu"))
        val start = Calendar.getInstance().apply {
            set(2026, Calendar.OCTOBER, 25, 23, 59, 50); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        record(start, 50, 1)
        record(start + 20000, 51, 1)
        val daily = rows(store.history(true), "daily").associateBy { it["day"] }
        assertEquals(10000L, daily["2026-10-25"]!!["pluggedMs"])
        assertEquals(10000L, daily["2026-10-26"]!!["pluggedMs"])
        assertEquals(1.0, daily["2026-10-26"]!!["charged"])
    }

    @Test fun clearDeletesRecordedDataAndTheNextSampleStartsFresh() {
        val start = now
        record(start, 50, 1)
        record(start + 30000, 51, 1)
        store.clear()
        for (key in listOf("points", "sessions", "daily")) assertTrue(rows(store.history(true), key).isEmpty())
        record(start + 60000, 52, 1)
        val history = store.history(true)
        assertEquals(1, rows(history, "points").size)
        assertEquals(1, rows(history, "sessions").size)
        assertTrue(rows(history, "daily").isEmpty())
    }

    @Test fun latestTenSessionsKeepOnlyTheirOwnPointsAndDailyContributions() {
        val start = now
        repeat(12) { index ->
            record(start + index * 60000L, 50, 1)
            record(start + index * 60000L + 30000, 51, 1)
            store.endSession()
        }
        val history = store.history(false)
        val sessions = rows(history, "sessions")
        assertEquals(10, sessions.size)
        assertEquals(20, rows(history, "points").size)
        assertEquals(10.0, (rows(history, "daily").single()["charged"] as Number).toDouble(), .0001)
        val retainedIds = sessions.map { (it["id"] as Number).toLong() }.toSet()
        assertTrue(rows(history, "points").all { (it["sessionId"] as Number).toLong() in retainedIds })
        for (table in listOf("points", "daily")) {
            store.readableDatabase.rawQuery("SELECT COUNT(*) FROM $table WHERE sessionId NOT IN (SELECT id FROM sessions)", null).use { c ->
                c.moveToFirst(); assertEquals(0, c.getInt(0))
            }
        }
    }

    @Test fun readingHistoryAfterThreeDaysPhysicallyDeletesExpiredDataAndResetsTheActiveSession() {
        val start = now
        record(start, 50, 1)
        record(start + 30000, 51, 1)
        now = start + BatteryStore.RETENTION_MS + 1
        val expired = store.history(false)
        for (table in listOf("points", "sessions", "daily")) {
            assertTrue(rows(expired, table).isEmpty())
            store.readableDatabase.rawQuery("SELECT COUNT(*) FROM $table", null).use { c ->
                c.moveToFirst(); assertEquals(0, c.getInt(0))
            }
        }
        record(now, 80, 1)
        val fresh = store.history(true)
        assertEquals(1, rows(fresh, "sessions").size)
        assertEquals(1, rows(fresh, "points").size)
        assertTrue(rows(fresh, "daily").isEmpty())
    }

    @Test fun recordingAlsoExpiresOldSessionsWithoutOpeningHistory() {
        val start = now
        record(start, 50, 1)
        record(start + 30000, 51, 1)
        record(start + BatteryStore.RETENTION_MS + 1, 80, 1)
        store.readableDatabase.rawQuery("SELECT COUNT(*) FROM sessions", null).use { c ->
            c.moveToFirst(); assertEquals(1, c.getInt(0))
        }
        store.readableDatabase.rawQuery("SELECT COUNT(*) FROM daily", null).use { c ->
            c.moveToFirst(); assertEquals(0, c.getInt(0))
        }
    }

    @Test fun versionTwoMigrationRebuildsTotalsFromRetainedIntervalsIncludingTheUnplugEvent() {
        val start = now
        record(start, 50, 1)
        record(start + 30000, 51, 1)
        record(start + 60000, 52, 0)
        val db = store.writableDatabase
        db.execSQL("DROP TABLE daily")
        db.execSQL("CREATE TABLE daily (day TEXT PRIMARY KEY, charged REAL DEFAULT 0, pluggedMs INTEGER DEFAULT 0)")
        db.execSQL("INSERT INTO daily VALUES('2026-10-26',999,999999)")
        val old = now - 4L * 86400000
        db.execSQL("INSERT INTO sessions(id,kind,source,startTime,endTime,startLevel,endLevel) VALUES(999,'Charging',1,?,?,10,11)", arrayOf(old,old + 30000))
        db.execSQL("INSERT INTO points(time,sessionId,level,plugged,status) VALUES(?,999,11,1,'Charging')", arrayOf(old + 30000))
        legacyPoints(db)
        db.version = 2
        store.close()
        store = BatteryStore(context) { now }
        val history = store.history(false)
        assertEquals(2, rows(history, "sessions").size)
        assertEquals(3, rows(history, "points").size)
        assertEquals(2.0, (rows(history, "daily").single()["charged"] as Number).toDouble(), .0001)
        assertEquals(60000L, rows(history, "daily").single()["pluggedMs"])
    }

    @Test fun migratingDailyTotalsNeverBridgesAShortRecordingPause() {
        val start = now
        record(start, 50, 1)
        record(start + 30000, 51, 1)
        store.endSession()
        record(start + 60000, 80, 1)
        record(start + 90000, 81, 1)
        val db = store.writableDatabase
        db.execSQL("DROP TABLE daily")
        db.execSQL("CREATE TABLE daily (day TEXT PRIMARY KEY, charged REAL DEFAULT 0, pluggedMs INTEGER DEFAULT 0)")
        legacyPoints(db)
        db.version = 2
        store.close()
        store = BatteryStore(context) { now }
        val history = store.history(false)
        assertEquals(2, rows(history, "sessions").size)
        assertEquals(2.0, (rows(history, "daily").single()["charged"] as Number).toDouble(), .0001)
        assertEquals(60000L, rows(history, "daily").single()["pluggedMs"])
    }

    @Test fun schemaUpgradePreservesOldReadingsWithoutInventingVoltageData() {
        store.close()
        val db = context.openOrCreateDatabase("battery.db", Context.MODE_PRIVATE, null)
        db.execSQL("CREATE TABLE sessions (id INTEGER PRIMARY KEY, kind TEXT, source INTEGER, startTime INTEGER, endTime INTEGER, startLevel INTEGER, endLevel INTEGER, powerSum REAL DEFAULT 0, powerCount INTEGER DEFAULT 0, gap INTEGER DEFAULT 0, ended INTEGER DEFAULT 0)")
        db.execSQL("CREATE TABLE points (time INTEGER PRIMARY KEY, sessionId INTEGER, level INTEGER, temperatureC REAL, powerW REAL, plugged INTEGER, status TEXT)")
        db.execSQL("CREATE TABLE daily (day TEXT PRIMARY KEY, charged REAL DEFAULT 0, pluggedMs INTEGER DEFAULT 0)")
        db.execSQL("INSERT INTO sessions(id,kind,source,startTime,endTime,startLevel,endLevel,powerSum,powerCount) VALUES(1,'Charging',1,?,?,70,71,18,2)", arrayOf(now - 30000, now))
        db.execSQL("INSERT INTO points(time,sessionId,level,temperatureC,powerW,plugged,status) VALUES(?,1,71,31,9,1,'Charging')", arrayOf(now))
        db.version = 1
        db.close()
        store = BatteryStore(context) { now }
        val history = store.history(true)
        assertEquals(71.0, rows(history, "sessions").single()["endLevel"])
        assertEquals(9.0, rows(history, "sessions").single()["averagePowerW"])
        assertNull(rows(history, "points").single()["voltageMv"])
        assertNull(rows(history, "points").single()["currentMa"])
        record(now + 30000, 72, 1)
        assertEquals(4100.0, rows(store.history(true), "points").last()["voltageMv"])
    }

    @Test fun sixHourCurrentQueryPreservesSignedAndMissingSamplesAndSurvivesReopening() {
        val end = now
        record(end - 7L * 3600000, 50, 1)
        record(end - 5L * 3600000, 51, 1)
        record(end, 52, 0, -2.0)
        now += 1000
        store.record(mapOf("time" to now,"level" to 52,"plugged" to 0,"status" to "Discharging",
            "currentMa" to null,"voltageMv" to 4000,"sampleIntervalMs" to 1000L,"currentConvention" to "1000.0/false"))
        store.close(); store = BatteryStore(context) { now }
        val samples = store.currentHistory()
        assertEquals(3,samples.size)
        assertTrue((samples[1]["currentMa"] as Number).toDouble() < 0)
        assertNull(samples.last()["currentMa"])
        assertEquals(1000L,samples.last()["sampleIntervalMs"])
        assertEquals("1000.0/false",samples.last()["currentConvention"])
        assertEquals(1,store.currentHistory(now).size)
    }

    @Test fun versionThreeUpgradeRetainsRealValuesAndDoesNotInventOldSamplingCadence() {
        record(now, 80, 0, -2.0)
        val db = store.writableDatabase
        legacyPoints(db); db.version = 3
        store.close(); store = BatteryStore(context) { now }
        val sample = store.currentHistory().single()
        assertTrue((sample["currentMa"] as Number).toDouble() < 0)
        assertEquals(30000L,sample["sampleIntervalMs"])
        assertNull(sample["currentConvention"])
    }
}
