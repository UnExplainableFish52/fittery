package com.fittery.tid52

import android.content.Context
import android.net.Uri

/** One choice per alert. Missing choices use the corresponding bundled voice. */
enum class AlertTone(val key: String, val bit: Int, val resource: Int, val title: String) {
    CHARGE("charge", 1, R.raw.charging_limit_reached, "Charging limit voice"),
    HEAT("heat", 4, R.raw.battery_temperature_limit, "Battery temperature voice"),
    LOW("low", 2, R.raw.low_battery_warning, "Low battery voice");

    fun defaultUri(context: Context): Uri = Uri.parse("android.resource://${context.packageName}/$resource")
    fun source(settings: Map<String, Any?>): String = settings["${key}ToneSource"] as? String
        ?: if (settings.containsKey("toneUri")) {
            if (settings["toneUri"] == null) "silent" else settings["toneSource"] as? String ?: "system"
        } else "bundled"

    fun selectedUri(settings: Map<String, Any?>): String? =
        if (settings.containsKey("${key}ToneSource")) settings["${key}ToneUri"] as? String
        else settings["toneUri"] as? String

    companion object {
        fun from(value: String?): AlertTone = entries.firstOrNull { it.key == (value ?: "charge") }
            ?: throw IllegalArgumentException("Unknown battery alert")

        fun migrate(settings: Map<String, Any?>): Map<String, Any?> = settings.toMutableMap().apply {
            for (tone in AlertTone.entries) {
                val source = tone.source(settings)
                putIfAbsent("${tone.key}ToneSource", source)
                if (source == "bundled") putIfAbsent("${tone.key}ToneName", tone.title)
                else if (!settings.containsKey("${tone.key}ToneSource")) {
                    put("${tone.key}ToneUri", settings["toneUri"])
                    put("${tone.key}ToneName", settings["toneName"] ?: if (source == "silent") "Silent" else "System alarm")
                }
            }
            remove("toneUri"); remove("toneName"); remove("toneSource")
        }

        fun fileUris(settings: Map<String, Any?>): Set<Uri> = entries.mapNotNull { tone ->
            tone.selectedUri(settings)?.takeIf { tone.source(settings) == "file" }?.let(Uri::parse)
        }.toSet()

        // Only one audible alarm at a time. Safety warnings take precedence.
        fun active(mask: Int, settings: Map<String, Any?>): AlertTone? =
            listOf(HEAT, LOW, CHARGE).firstOrNull { mask and it.bit != 0 && it.source(settings) != "silent" }
    }
}
