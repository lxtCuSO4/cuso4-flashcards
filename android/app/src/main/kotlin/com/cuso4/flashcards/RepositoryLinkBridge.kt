package com.cuso4.flashcards

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Opens only the project's fixed repository; no app networking is needed. */
class RepositoryLinkBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.cuso4.flashcards/repository_link")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "openRepository") {
                result.notImplemented()
            } else {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://github.com/lxtCuSO4/cuso4-flashcards")).apply {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                }
                try {
                    activity.startActivity(intent)
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                } catch (_: SecurityException) {
                    result.success(false)
                }
            }
        }
    }

    fun dispose() { channel.setMethodCallHandler(null) }
}
