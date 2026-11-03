package com.fittery.tid52

import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ProviderInfo
import android.content.res.AssetFileDescriptor
import android.database.MatrixCursor
import android.media.MediaPlayer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowContentResolver
import java.io.File
import java.io.FileNotFoundException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE, application = Application::class, shadows = [FileAudioPlayerShadow::class])
class AlarmAudioFileTest {
    private lateinit var context: Context
    private lateinit var files: AlarmAudioFile
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        files = AlarmAudioFile(context)
        FileAudioPlayerShadow.released = 0
        ShadowContentResolver.registerProviderInternal("audio.test", Robolectric.buildContentProvider(LocalAudioProvider::class.java).create(ProviderInfo().apply { authority = "audio.test" }).get())
    }

    @Test fun pickerRequestsLocalAudioAndOnlyReadAccess() {
        val pick = AlarmAudioFile.pickerIntent()
        assertEquals(Intent.ACTION_OPEN_DOCUMENT, pick.action)
        assertEquals("audio/*", pick.type)
        assertTrue(pick.hasCategory(Intent.CATEGORY_OPENABLE))
        assertTrue(pick.getBooleanExtra(Intent.EXTRA_LOCAL_ONLY, false))
        assertTrue(pick.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0)
        assertEquals(0, pick.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
    }

    @Test fun selectingAudioKeepsTheFileNameAndPersistentReadGrantAndReleasesTheDecoder() {
        val uri = Uri.parse("content://audio.test/song")
        val selection = files.select(uri)
        assertEquals(uri, selection.uri)
        assertEquals("My favorite song.mp3", selection.name)
        assertTrue(context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission })
        assertEquals(1, FileAudioPlayerShadow.released)
        // Selection does not depend on an in-memory player after the picker closes.
        AlarmAudioFile(context).requireReadable(uri)
        files.releaseIfUnused(uri, emptyMap())
        assertFalse(context.contentResolver.persistedUriPermissions.any { it.uri == uri })
    }

    @Test fun unsupportedAudioDoesNotKeepAFileGrantAndTheDecoderIsReleased() {
        val uri = Uri.parse("content://audio.test/unsupported")
        try { files.select(uri); fail("Unsupported audio should be rejected") }
        catch (e: IllegalArgumentException) { assertTrue(e.message!!.contains("cannot be played")) }
        assertFalse(context.contentResolver.persistedUriPermissions.any { it.uri == uri })
        assertEquals(1, FileAudioPlayerShadow.released)
    }

    @Test fun aSharedFileGrantIsKeptUntilTheLastAlertStopsUsingIt() {
        val uri = Uri.parse("content://audio.test/song")
        files.select(uri)
        val shared = mapOf("chargeToneUri" to uri.toString(), "chargeToneSource" to "file",
            "heatToneUri" to uri.toString(), "heatToneSource" to "file")
        val heatOnly = shared + ("chargeToneSource" to "bundled")
        files.releaseUnused(shared, heatOnly)
        assertTrue(context.contentResolver.persistedUriPermissions.any { it.uri == uri })
        files.releaseUnused(heatOnly, heatOnly + ("heatToneSource" to "bundled"))
        assertFalse(context.contentResolver.persistedUriPermissions.any { it.uri == uri })
    }

    @Test fun missingAudioHasAnActionableError() {
        try { files.select(Uri.parse("content://audio.test/missing")); fail("Missing audio should be rejected") }
        catch (e: IllegalArgumentException) { assertTrue(e.message!!.contains("Choose it again")) }
    }
}

class LocalAudioProvider : ContentProvider() {
    override fun onCreate() = true
    override fun getType(uri: Uri) = "audio/mpeg"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?) =
        MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)).apply { addRow(arrayOf("My favorite song.mp3")) }
    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor {
        if (uri.lastPathSegment == "missing") throw FileNotFoundException("Removed audio")
        val file = File(requireNotNull(context).cacheDir, "test-audio").apply { writeText("Simulated audio data") }
        return AssetFileDescriptor(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY), 0, file.length())
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = 0
}

@Implements(MediaPlayer::class)
class FileAudioPlayerShadow {
    companion object { var released = 0 }
    private var source: Uri? = null
    @Implementation fun setDataSource(context: Context, uri: Uri) { source = uri }
    @Implementation fun prepare() { if (source?.lastPathSegment == "unsupported") throw IllegalArgumentException("Unsupported codec") }
    @Implementation fun getDuration() = 180000
    @Implementation fun release() { released++ }
}
