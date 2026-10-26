package com.fittery.tid52

import android.app.Application
import android.os.Looper
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 34], manifest = Config.NONE, application = Application::class)
class NetworkMonitorTest {
    @Test fun oneSecondTicksStopWhenHiddenAndRepeatedListenDoesNotDuplicateTheTimer() {
        val monitor = NetworkMonitor(RuntimeEnvironment.getApplication())
        val readings = mutableListOf<Map<String, Any?>>()
        monitor.setForeground(true)
        monitor.listen { readings.add(it) }
        val looper = shadowOf(Looper.getMainLooper())
        looper.idle()
        val initial = readings.size
        looper.idleFor(999, TimeUnit.MILLISECONDS)
        assertEquals(initial, readings.size)
        looper.idleFor(1, TimeUnit.MILLISECONDS)
        assertEquals(initial + 1, readings.size)
        monitor.listen { readings.add(it) }
        monitor.setForeground(true)
        looper.idleFor(2, TimeUnit.SECONDS)
        assertEquals(initial + 3, readings.size)
        monitor.setForeground(false)
        looper.idleFor(5, TimeUnit.SECONDS)
        assertEquals(initial + 3, readings.size)
        monitor.setForeground(true)
        assertNull(readings.last()["downloadBytesPerSecond"])
        monitor.listen(null)
        val stopped = readings.size
        looper.idleFor(5, TimeUnit.SECONDS)
        assertEquals(stopped, readings.size)
    }
    @Test fun onlyAnActiveForegroundSubscriberCanSampleAndResumeStartsWithoutStaleRates() {
        val monitor = NetworkMonitor(RuntimeEnvironment.getApplication())
        val readings = mutableListOf<Map<String, Any?>>()
        monitor.listen { readings.add(it) }
        monitor.sample()
        assertTrue(readings.isEmpty())

        monitor.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(readings.isNotEmpty())
        val activeCount = readings.size
        monitor.sample()
        assertEquals(activeCount + 1, readings.size)

        monitor.setForeground(false)
        val stoppedCount = readings.size
        monitor.sample()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(stoppedCount, readings.size)

        monitor.setForeground(true)
        assertNull(readings.last()["downloadBytesPerSecond"])
        monitor.listen(null)
        val cancelledCount = readings.size
        monitor.sample()
        monitor.setForeground(false)
        monitor.setForeground(true)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(cancelledCount, readings.size)
    }
}
