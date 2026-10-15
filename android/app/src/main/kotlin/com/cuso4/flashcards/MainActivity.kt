package com.cuso4.flashcards

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import java.io.File
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private var audioChannel: MethodChannel? = null
    private var focus: AudioFocusRequest? = null
    private var playbackId: Int? = null
    private var backupBridge: BackupDocumentBridge? = null
    private var reminderBridge: LearningReminderBridge? = null
    private var feedbackBridge: ProblemFeedbackBridge? = null
    private val audioManager by lazy { getSystemService(AUDIO_SERVICE) as AudioManager }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupBridge = BackupDocumentBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        reminderBridge = LearningReminderBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        feedbackBridge = ProblemFeedbackBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.cuso4.flashcards/audio").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "stop" -> { stopAudio(); result.success(null) }
                    "play" -> {
                        try {
                            val path = call.argument<String>("path") ?: error("Missing file")
                            val id = call.argument<Int>("id") ?: error("Missing id")
                            val file = File(path)
                            val root = File(filesDir, "media").canonicalFile
                            require(file.canonicalFile.parentFile == root &&
                                file.name.matches(Regex("[a-f0-9]{64}")) && file.isFile)
                            stopAudio()
                            val attributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
                            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                                .setAudioAttributes(attributes)
                                .setOnAudioFocusChangeListener { change ->
                                    if (change < 0) finishAudio("completed")
                                }.build()
                            focus = request
                            require(audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
                            playbackId = id
                            val next = MediaPlayer()
                            player = next
                            next.setAudioAttributes(attributes)
                            next.setDataSource(file.canonicalPath)
                            next.setOnPreparedListener { if (player === it) it.start() }
                            next.setOnCompletionListener { if (player === it) finishAudio("completed") }
                            next.setOnErrorListener { failed, _, _ ->
                                if (player === failed) finishAudio("error")
                                true
                            }
                            next.prepareAsync()
                            result.success(null)
                        } catch (e: Exception) {
                            stopAudio()
                            result.error("AUDIO_ERROR", "Local audio could not be played", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun finishAudio(event: String) {
        val id = playbackId
        stopAudio()
        if (id != null) audioChannel?.invokeMethod(event, mapOf("id" to id))
    }

    private fun stopAudio() {
        val old = player
        player = null
        playbackId = null
        old?.release()
        focus?.let { audioManager.abandonAudioFocusRequest(it) }
        focus = null
    }

    override fun onStop() {
        finishAudio("completed")
        super.onStop()
    }

    override fun onDestroy() {
        feedbackBridge?.dispose()
        feedbackBridge = null
        reminderBridge?.dispose()
        reminderBridge = null
        backupBridge?.dispose()
        backupBridge = null
        stopAudio()
        audioChannel?.setMethodCallHandler(null)
        audioChannel = null
        super.onDestroy()
    }

    @Deprecated("Activity result bridge for the system document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        reminderBridge?.permissionResponse(requestCode)
    }
}
