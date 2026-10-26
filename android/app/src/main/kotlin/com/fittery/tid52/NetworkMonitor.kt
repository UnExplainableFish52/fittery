package com.fittery.tid52

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** Rate math is independent of wall-clock changes, counter resets and UI gaps. */
internal class TrafficRateTracker {
    private var previous: LongArray? = null

    fun reset() { previous = null }

    fun sample(rx: Long, tx: Long, elapsedMs: Long): Pair<Double, Double>? {
        if (rx < 0 || tx < 0) { reset(); return null }
        val before = previous
        previous = longArrayOf(rx, tx, elapsedMs)
        if (before == null || elapsedMs <= before[2] || rx < before[0] || tx < before[1]) return null
        val seconds = (elapsedMs - before[2]) / 1000.0
        return (rx - before[0]) / seconds to (tx - before[1]) / seconds
    }
}

/** Activity-owned observer. A one-second tick exists only for a visible subscriber.
 * No service, scans, traffic history, Internet requests or wake locks.
 */
internal class NetworkMonitor(context: Context) {
    private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private val handler = Handler(Looper.getMainLooper())
    private val rates = TrafficRateTracker()
    private var foreground = false
    private var listener: ((Map<String, Any?>) -> Unit)? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var network: Network? = null
    private var details = emptyMap<String, Any?>()
    private var latestRates: Pair<Double, Double>? = null
    private var counterError: String? = null
    private val tick = object : Runnable {
        override fun run() {
            if (callback == null || !foreground || listener == null) return
            sample()
            if (callback != null && foreground && listener != null) handler.postDelayed(this, 1000)
        }
    }

    fun listen(value: ((Map<String, Any?>) -> Unit)?) {
        listener = value
        reconcile()
    }

    fun setForeground(value: Boolean) {
        foreground = value
        reconcile()
    }

    private fun reconcile() {
        if (foreground && listener != null) {
            if (callback == null) start()
        } else stop()
    }

    private fun start() {
        val observer = object : ConnectivityManager.NetworkCallback() {
            private fun dispatch(action: () -> Unit) {
                handler.post { if (callback === this) action() }
            }
            override fun onAvailable(value: Network) = dispatch {
                if (network != value) {
                    network = value
                    resetRates()
                    details = mapOf("connected" to true, "connectionType" to "Connecting")
                    publish()
                }
            }
            override fun onCapabilitiesChanged(value: Network, capabilities: NetworkCapabilities) = dispatch {
                if (network != value) resetRates()
                network = value
                details = connectionDetails(capabilities)
                publish()
            }
            override fun onLost(value: Network) = dispatch {
                if (network == value) {
                    network = null
                    details = connectionDetails(null)
                    resetRates()
                    publish()
                }
            }
        }
        callback = observer
        try {
            connectivity.registerDefaultNetworkCallback(observer)
            // One initial snapshot. Callback updates use their supplied capabilities.
            network = connectivity.activeNetwork
            details = connectionDetails(network?.let(connectivity::getNetworkCapabilities))
            resetRates()
            publish()
            if (callback === observer && foreground && listener != null) handler.postDelayed(tick, 1000)
        } catch (_: RuntimeException) {
            stop()
            listener?.invoke(mapOf("connectionType" to "Unavailable", "error" to "Network information is unavailable on this device."))
        }
    }

    private fun stop() {
        val previous = callback
        callback = null
        if (previous != null) {
            try { connectivity.unregisterNetworkCallback(previous) } catch (_: RuntimeException) { }
        }
        handler.removeCallbacksAndMessages(null)
        rates.reset()
        latestRates = null
        counterError = null
        network = null
        details = emptyMap()
    }

    private fun resetRates() {
        rates.reset()
        latestRates = null
        readCounters()
    }

    fun sample() {
        if (callback == null || !foreground || listener == null) return
        readCounters()
        publish()
    }

    private fun readCounters() {
        // A broken OEM counter must never interrupt battery sampling or alerts.
        try {
            val rx = TrafficStats.getTotalRxBytes()
            val tx = TrafficStats.getTotalTxBytes()
            counterError = if (rx < 0 || tx < 0) "Traffic counters are unavailable on this device." else null
            latestRates = rates.sample(rx, tx, SystemClock.elapsedRealtime())
        } catch (_: RuntimeException) {
            rates.reset()
            latestRates = null
            counterError = "Traffic counters are unavailable on this device."
        }
    }

    private fun publish() {
        listener?.invoke(details + mapOf(
            "downloadBytesPerSecond" to latestRates?.first,
            "uploadBytesPerSecond" to latestRates?.second,
            "combinedBytesPerSecond" to latestRates?.let { it.first + it.second },
            "error" to counterError
        ))
    }

    @Suppress("DEPRECATION")
    private fun connectionDetails(capabilities: NetworkCapabilities?): Map<String, Any?> {
        if (capabilities == null) return mapOf("connected" to false, "connectionType" to "Disconnected")
        val transports = listOf(
            NetworkCapabilities.TRANSPORT_VPN to "VPN",
            NetworkCapabilities.TRANSPORT_WIFI to "Wi-Fi",
            NetworkCapabilities.TRANSPORT_CELLULAR to "Cellular",
            NetworkCapabilities.TRANSPORT_ETHERNET to "Ethernet",
            NetworkCapabilities.TRANSPORT_BLUETOOTH to "Bluetooth"
        ).filter { capabilities.hasTransport(it.first) }.map { it.second }
        val info = if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
            try {
                if (Build.VERSION.SDK_INT >= 31) capabilities.transportInfo as? WifiInfo
                else wifi?.connectionInfo
            } catch (_: RuntimeException) { null }
        } else null
        val ssid = info?.ssid?.removeSurrounding("\"")?.takeIf {
            it.isNotBlank() && it != WifiManager.UNKNOWN_SSID && it != "0x"
        }
        val frequency = info?.frequency?.takeIf { it > 0 }
        val band = when (frequency) {
            in 2400..2500 -> "2.4 GHz"
            in 4900..5900 -> "5 GHz"
            in 5925..7125 -> "6 GHz"
            in 57000..71000 -> "60 GHz"
            else -> null
        }
        return mapOf(
            "connected" to true,
            "connectionType" to transports.joinToString(" · ").ifEmpty { "Other" },
            "wifi" to capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
            "cellular" to capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
            "vpn" to capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
            "internetValidated" to capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            "metered" to !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
            "accessPoint" to ssid,
            "frequencyMhz" to frequency,
            "wifiBand" to band,
            "linkSpeedMbps" to info?.linkSpeed?.takeIf { it > 0 }
        )
    }
}
