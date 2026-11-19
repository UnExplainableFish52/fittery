package com.fittery.tid52

object NotificationElements {
    val metrics = listOf("Current", "Power", "Temperature", "Time remaining")
    fun valid(value: Any?): Boolean = value is List<*> &&
        (value == listOf("All metrics") || value.size in 1..3 && value.distinct().size == value.size && value.all { it in metrics })

    fun selected(settings: Map<*, *>): List<String> {
        val saved = settings["notificationElements"]
        val selection = if (valid(saved)) (saved as List<*>).map { it as String }
            else listOf(settings["notificationFormat"] as? String ?: "All metrics")
        return if (selection == listOf("All metrics")) metrics else metrics.filter { it in selection }.ifEmpty { metrics }
    }
}
