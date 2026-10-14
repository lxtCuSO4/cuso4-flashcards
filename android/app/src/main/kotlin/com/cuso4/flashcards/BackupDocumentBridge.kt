package com.cuso4.flashcards

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.StatFs
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files

/** SAF export streams a checked private archive, without broad storage permission. */
class BackupDocumentBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.cuso4.flashcards/backup")
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "availableBytes" -> {
                    try { result.success(StatFs(activity.filesDir.absolutePath).availableBytes) }
                    catch (_: Exception) { result.error("STORAGE_ERROR", "Cannot check free storage", null) }
                }
                "saveBackup" -> {
                    if (pending != null) {
                        result.error("BUSY", "A backup export is already active", null)
                    } else {
                        try {
                            val file = File(call.argument<String>("path") ?: error("Missing source"))
                            val root = File(activity.filesDir, "backup-work").canonicalFile
                            require(file.canonicalPath.startsWith(root.path + File.separator) &&
                                !Files.isSymbolicLink(file.toPath()) && file.isFile &&
                                file.name.endsWith(".cuso4backup"))
                            val name = call.argument<String>("name") ?: file.name
                            require(name.matches(Regex("CuSO4-[0-9]+\\.cuso4backup")))
                            source = file
                            pending = result
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/octet-stream"
                                putExtra(Intent.EXTRA_TITLE, name)
                            }
                            @Suppress("DEPRECATION")
                            activity.startActivityForResult(intent, REQUEST_EXPORT)
                        } catch (_: Exception) {
                            pending = null
                            source = null
                            result.error("EXPORT_ERROR", "Cannot open backup destination", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_EXPORT) return false
        val reply = pending ?: return true
        val file = source
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) {
            pending = null
            source = null
            reply.success(false)
            return true
        }
        Thread({
            try {
                activity.contentResolver.openOutputStream(uri, "wt").use { output ->
                    requireNotNull(output)
                    file.inputStream().use { input ->
                        val buffer = ByteArray(128 * 1024)
                        while (true) {
                            check(!disposed)
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                    }
                    output.flush()
                }
                activity.runOnUiThread {
                    if (pending === reply && !disposed) {
                        pending = null; source = null; reply.success(true)
                    }
                }
            } catch (_: Exception) {
                deletePartial(uri)
                activity.runOnUiThread {
                    if (pending === reply && !disposed) {
                        pending = null; source = null
                        reply.error("EXPORT_ERROR", "Backup destination could not be written", null)
                    }
                }
            }
        }, "cuso4-backup-export").start()
        return true
    }

    private fun deletePartial(uri: Uri) {
        try { DocumentsContract.deleteDocument(activity.contentResolver, uri) }
        catch (_: Exception) { /* Some document providers do not support deletion. */ }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.error("CLOSED", "Backup export interrupted", null)
        pending = null
        source = null
    }

    companion object { const val REQUEST_EXPORT = 46324 }
}
