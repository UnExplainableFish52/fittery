package com.fittery.tid52

import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns

/** Uses a durable, read-only document grant; the app never scans the music library. */
class AlarmAudioFile(private val context: Context) {
    companion object {
        fun pickerIntent() = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
    }

    data class Selection(val uri: Uri, val name: String)

    /** Run on a worker. Reject an unreadable/unsupported file before replacing a saved tone. */
    fun select(uri: Uri): Selection {
        require(uri.scheme == "content") { "Choose an audio file using the file picker." }
        requireReadable(uri)
        val player = MediaPlayer()
        try {
            player.setDataSource(context, uri)
            player.prepare()
            require(player.duration > 0) { "This audio file has no playable sound." }
        } catch (e: Exception) {
            throw IllegalArgumentException("This audio file cannot be played. Choose another audio file.", e)
        } finally { player.release() }
        try {
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            throw IllegalArgumentException("Access to this file could not be saved. Choose it from your phone's local storage.", e)
        }
        val name = try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (cursor.moveToFirst() && column >= 0) cursor.getString(column)?.takeIf { it.isNotBlank() } else null
            }
        } catch (_: Exception) { null }
        return Selection(uri, name ?: "Selected audio file")
    }

    fun requireReadable(uri: Uri) {
        try {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { return }
        } catch (e: Exception) {
            throw IllegalArgumentException("Your selected audio file is unavailable. Choose it again or select another tone.", e)
        }
        error("Your selected audio file is unavailable. Choose it again or select another tone.")
    }

    fun releaseUnused(previous: Map<String, Any?>, next: Map<String, Any?>) {
        for (uri in AlertTone.fileUris(previous) - AlertTone.fileUris(next)) releaseIfUnused(uri, next)
    }

    fun releaseIfUnused(uri: Uri, settings: Map<String, Any?>) {
        if (uri in AlertTone.fileUris(settings)) return
        try { context.contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        catch (_: SecurityException) { /* The provider may already have revoked access. */ }
    }
}
