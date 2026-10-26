package com.fittery.tid52

import android.content.Context
import org.xmlpull.v1.XmlPullParser

object DevicePowerProfile {
    /** Read the manufacturer's overlaid framework profile without blocking startup. */
    fun batteryCapacity(context: Context): Double? {
        try {
            val resources = context.resources
            @Suppress("DiscouragedApi")
            val id = resources.getIdentifier("power_profile", "xml", "android")
            if (id != 0) {
                val parser = resources.getXml(id)
                try {
                    while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                        if (parser.eventType == XmlPullParser.START_TAG && parser.name == "item" &&
                            parser.getAttributeValue(null, "name") == "battery.capacity") {
                            BatteryHardwareValues.validCapacity(parser.nextText().trim().toDoubleOrNull())?.let { return it }
                        }
                        parser.next()
                    }
                } finally { parser.close() }
            }
        } catch (_: Exception) { /* Some OEMs do not expose the XML resource. */ }

        // Best-effort fallback. Restricted or unavailable platform APIs are
        // caught normally; no hidden-API exemptions or root access are used.
        return try {
            val type = Class.forName("com.android.internal.os.PowerProfile")
            val profile = type.getConstructor(Context::class.java).newInstance(context)
            val value = (type.getMethod("getBatteryCapacity").invoke(profile) as? Number)?.toDouble()
            BatteryHardwareValues.validCapacity(value)
        } catch (_: Exception) { null }
    }
}
