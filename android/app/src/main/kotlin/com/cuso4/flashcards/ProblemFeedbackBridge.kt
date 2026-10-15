package com.cuso4.flashcards

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Hands a user-written draft to a mail app; it never sends mail itself. */
class ProblemFeedbackBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.cuso4.flashcards/problem_feedback")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "openEmail") {
                result.notImplemented()
            } else {
                val subject = call.argument<String>("subject")
                val body = call.argument<String>("body")
                if (subject == null || body == null || subject.length > 300 || body.length > 15000) {
                    result.error("INVALID_DRAFT", "Invalid email draft", null)
                } else {
                    val recipient = "2791398676@qq.com"
                    val uri = Uri.parse("mailto:$recipient?subject=${Uri.encode(subject)}&body=${Uri.encode(body)}")
                    val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                        putExtra(Intent.EXTRA_EMAIL, arrayOf(recipient))
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                        putExtra(Intent.EXTRA_TEXT, body)
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
    }

    fun dispose() { channel.setMethodCallHandler(null) }
}
