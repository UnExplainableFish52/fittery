package com.fittery.tid52

import android.app.Application
import android.content.Context
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.SQLiteMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE, application = Application::class)
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class MonitorStoreTest {
    private lateinit var context: Context
    private lateinit var store: MonitorStore
    private val base = 1792977300000L
    private var now = base
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("monitor.db")
        store = MonitorStore(context) { now }
    }
    @After fun cleanup() { store.close() }
    private fun sample(offset: Long, plugged: Int = 0, level: Int = 50, power: Double? = -4.0, current: Double? = -1000.0, temp: Double? = 30.0, elapsed: Long = offset) {
        store.record(mapOf("time" to base + offset, "elapsed" to elapsed, "plugged" to plugged,
            "level" to level, "status" to if (plugged > 0) "Charging" else "Discharging",
            "powerW" to power, "currentMa" to current, "temperatureC" to temp,
            "voltageMv" to 4000, "chargeCounterMah" to 2500, "convention" to "1000/false/1"))
    }
    @Suppress("UNCHECKED_CAST") private fun rows(data: Map<String, Any?>, key: String) = data[key] as List<Map<String, Any?>>
    @Suppress("UNCHECKED_CAST") private fun summary(id: Long) = store.detail(id)["recording"] as Map<String, Any?>

    @Test fun onlyAnUnplugSampleThatClosesARealSegmentReturnsAReport() {
        val id = store.begin()
        fun reading(offset: Long, plugged: Int) = mapOf<String, Any?>(
            "time" to base + offset, "elapsed" to offset, "plugged" to plugged,
            "level" to 50, "status" to if (plugged > 0) "Charging" else "Discharging", "convention" to "test"
        )
        assertNull(store.record(reading(0, 0)))
        assertNull(store.record(reading(3000, 1)))
        val report = store.record(reading(6000, 0))!!
        assertEquals(id, report["recordingId"])
        assertEquals(base + 3000, report["startTime"])
        assertEquals(base + 6000, report["endTime"])
        assertEquals(1L, summary(id)["active"])
        assertEquals(2L, store.detail(id, base + 3000, base + 6000)["rangeSampleCount"])
        assertNull(store.record(reading(9000, 0)))
        store.finish()
        store.begin(base + 12000)
        assertNull(store.record(reading(12000, 0)))
    }

    @Test fun chargingAndDischargingRemainInsideOneIntentionalRecording() {
        val id = store.begin()
        sample(0)
        sample(3000, 1, 51, 4.0, 1000.0, 40.0)
        sample(6000, 0, 51)
        store.finish(base + 6000)
        assertEquals(1, rows(store.list(null, null, null), "recordings").size)
        val report = summary(id)
        assertEquals(3L, report["sampleCount"])
        assertEquals(6000L, report["observedMs"])
        assertEquals(40.0, report["maxTemperatureC"])
        assertEquals(3000.0, (report["above35Ms"] as Number).toDouble(), .001)
        // Opposite current directions must not become all-positive charge.
        assertEquals(.416666, (report["chargeMah"] as Number).toDouble(), .00001)
        assertEquals(.416666, (report["dischargeMah"] as Number).toDouble(), .00001)
        assertEquals(0.0, (report["powerWms"] as Number).toDouble(), .001)
        assertTrue(rows(store.detail(id), "charging").isEmpty())
        assertEquals(3, rows(store.detail(id), "points").size)
    }
    @Test fun fiveMinuteOrFivePointSegmentsAreKeptButShortTinyOnesAreOnlyHidden() {
        val id = store.begin()
        sample(0, 1, 50)
        for (i in 1..100) sample(i * 3000L, if (i == 100) 0 else 1, 51)
        sample(303000, 1, 51)
        sample(306000, 0, 56)
        sample(309000, 1, 56)
        sample(312000, 0, 57)
        store.finish(base + 312000)
        val detail = store.detail(id)
        assertEquals(2, rows(detail, "charging").size)
        assertEquals(105L, summary(id)["sampleCount"])
        assertEquals(105L, detail["rangeSampleCount"])
    }
    @Test fun retentionIsPerCreationNotCalendarMonthAndHasNoTenRecordingCap() {
        val ids = (0..12).map { i -> store.begin(base + i * 1000L).also { store.finish(base + i * 1000L + 1) } }
        now = base + MonitorStore.RETENTION_MS - 1
        store.cleanup(false, true)
        assertEquals(13, rows(store.list(null, null, null), "recordings").size)
        now++
        store.cleanup(false, true)
        assertEquals(12, rows(store.list(null, null, null), "recordings").size)
        assertFalse(rows(store.list(null, null, null), "recordings").any { it["id"] == ids.first() })
        now += MonitorStore.RETENTION_MS
        store.cleanup(true, true)
        assertEquals(12, rows(store.list(null, null, null), "recordings").size)
        store.begin(now - MonitorStore.RETENTION_MS * 2)
        store.cleanup(false, true)
        assertEquals(1, rows(store.list(null, null, null), "recordings").size)
    }
    @Test fun restartKeepsIdentityAndMarksGapsWithoutInventingTotals() {
        val id = store.begin()
        sample(0); sample(3000)
        store.close()
        store = MonitorStore(context) { now }
        assertEquals(id, store.begin(base + 4000))
        sample(6000)
        sample(36000)
        sample(39000, power = null, current = null, temp = null)
        val report = summary(id)
        assertEquals(2L, report["gapCount"])
        assertEquals(6000L, report["observedMs"])
        assertEquals(3000L, report["powerMs"])
        assertEquals(3000L, report["currentMs"])
        val points = rows(store.detail(id), "points")
        assertEquals(4, points.map { it["sessionId"] }.distinct().size)
    }
    @Test fun dateFilteringNamesAndDeletionOperateOnWholeRecordings() {
        val id = store.begin()
        sample(0); sample(3000)
        store.finish(base + 4000)
        assertEquals(1, rows(store.list(base + 2000, base + 5000, null), "recordings").size)
        assertTrue(rows(store.list(base + 5000, null, null), "recordings").isEmpty())
        store.rename(id, " Overnight test ")
        assertEquals("Overnight test", summary(id)["name"])
        store.delete(id)
        store.readableDatabase.rawQuery("SELECT COUNT(*) FROM samples", null).use { it.moveToFirst(); assertEquals(0, it.getInt(0)) }
    }
    @Test fun graphReductionPreservesExtremaAndZoomLoadsOriginalSamples() {
        val id = store.begin()
        for (i in 0..3000) sample(i * 3000L, temp = if (i == 1501) 49.9 else 30.0, power = if (i == 1502) 25.0 else -4.0)
        val detail = store.detail(id)
        val points = rows(detail, "points")
        assertTrue(points.size < 3001)
        assertTrue(points.any { it["temperatureC"] == 49.9 })
        assertTrue(points.any { it["powerW"] == 25.0 })
        val zoom = store.detail(id, base + 1500 * 3000L, base + 1503 * 3000L)
        assertEquals(4, rows(zoom, "points").size)
        store.readableDatabase.rawQuery("SELECT COUNT(*) FROM samples", null).use { it.moveToFirst(); assertEquals(3001, it.getInt(0)) }
    }
    @Test fun clockCorrectionsAndRebootsAreGaps() {
        val id = store.begin()
        sample(0, elapsed = 100000)
        sample(3000, elapsed = 103000)
        sample(900000, elapsed = 106000)
        sample(903000, elapsed = 3000)
        assertEquals(2L, summary(id)["gapCount"])
        assertEquals(3000L, summary(id)["observedMs"])
    }
}
