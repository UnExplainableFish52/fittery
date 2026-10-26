package com.fittery.tid52

import android.app.ActivityManager
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.StatFs
import android.view.Display

/** On-demand public SDK information, never polled with battery readings. */
internal object DeviceInfo {
    private fun reported(value: String): String? = value.takeIf { it.isNotBlank() && !it.equals(Build.UNKNOWN, true) }

    fun read(context: Context): Map<String, Any?> {
        val values = mutableMapOf<String, Any?>(
            "model" to reported(Build.MODEL),
            "manufacturer" to reported(Build.MANUFACTURER),
            "board" to reported(Build.BOARD),
            "androidVersion" to Build.VERSION.RELEASE,
            "apiLevel" to Build.VERSION.SDK_INT,
            "securityPatch" to reported(Build.VERSION.SECURITY_PATCH),
            "architectures" to Build.SUPPORTED_ABIS.joinToString(", "),
            "availableProcessors" to Runtime.getRuntime().availableProcessors(),
            "socModel" to if (Build.VERSION.SDK_INT >= 31) reported(Build.SOC_MODEL) else null,
            "socManufacturer" to if (Build.VERSION.SDK_INT >= 31) reported(Build.SOC_MANUFACTURER) else null
        )
        try {
            val memory = ActivityManager.MemoryInfo()
            (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
            values["totalRamBytes"] = memory.totalMem.takeIf { it > 0 }
            if (Build.VERSION.SDK_INT >= 34) values["advertisedRamBytes"] = memory.advertisedMem.takeIf { it > 0 }
        } catch (_: RuntimeException) { }
        try {
            val storage = StatFs(context.dataDir.absolutePath)
            values["dataTotalBytes"] = storage.totalBytes
            values["dataAvailableBytes"] = storage.availableBytes
        } catch (_: RuntimeException) { }
        try {
            val display = (context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager).getDisplay(Display.DEFAULT_DISPLAY)
            display?.mode?.let {
                values["displayWidth"] = it.physicalWidth
                values["displayHeight"] = it.physicalHeight
                values["displayRefreshRate"] = it.refreshRate.toDouble()
            }
        } catch (_: RuntimeException) { }
        return values
    }
}
