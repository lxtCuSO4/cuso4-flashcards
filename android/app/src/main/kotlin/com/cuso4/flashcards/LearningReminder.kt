package com.cuso4.flashcards

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar
import io.flutter.plugin.common.MethodChannel

object LearningReminder {
    const val ACTION = "com.cuso4.flashcards.LEARNING_REMINDER"
    private const val CHANNEL = "daily_learning"
    private const val ID = 4102
    private fun prefs(context: Context) = context.getSharedPreferences("learning_reminder", Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    fun allowed(context: Context): Boolean {
        val service = manager(context)
        service.createNotificationChannel(NotificationChannel(CHANNEL, "每日学习提醒", NotificationManager.IMPORTANCE_DEFAULT))
        return (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            service.areNotificationsEnabled() && (service.getNotificationChannel(CHANNEL)?.importance ?: NotificationManager.IMPORTANCE_NONE) != NotificationManager.IMPORTANCE_NONE
    }
    fun state(context: Context): Map<String, Any> {
        val settings = prefs(context)
        return mapOf("enabled" to settings.getBoolean("enabled", false), "hour" to settings.getInt("hour", 20),
            "minute" to settings.getInt("minute", 0), "allowed" to allowed(context))
    }
    private fun pending(context: Context) = PendingIntent.getBroadcast(context, ID,
        Intent(context, LearningReminderReceiver::class.java).setAction(ACTION), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val settings = prefs(context)
        val intent = pending(context)
        alarms.cancel(intent)
        if (!settings.getBoolean("enabled", false)) { manager(context).cancel(ID); return }
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, settings.getInt("hour", 20)); set(Calendar.MINUTE, settings.getInt("minute", 0))
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        // Daily learning is tolerant of system batching; no exact-alarm permission.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, intent)
    }
    fun configure(context: Context, enabled: Boolean, hour: Int, minute: Int) {
        require(hour in 0..23 && minute in 0..59)
        require(!enabled || allowed(context)) { "请先允许应用发送通知" }
        val settings = prefs(context)
        val before = state(context)
        try {
            check(settings.edit().putBoolean("enabled", enabled).putInt("hour", hour).putInt("minute", minute).commit())
            schedule(context)
        } catch (error: Exception) {
            settings.edit().putBoolean("enabled", before["enabled"] as Boolean).putInt("hour", before["hour"] as Int)
                .putInt("minute", before["minute"] as Int).commit()
            try { schedule(context) } catch (_: Exception) { }
            throw error
        }
    }
    fun show(context: Context, test: Boolean = false) {
        check(allowed(context)) { "通知权限未开启" }
        val open = PendingIntent.getActivity(context, ID, Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager(context).notify(ID, Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_stat_cards)
            .setContentTitle(if (test) "学习提醒测试" else "该复习一下了")
            .setContentText("打开 CuSO₄闪卡，花一点时间巩固今天的知识。")
            .setContentIntent(open).setAutoCancel(true).build())
    }
}

class LearningReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action == LearningReminder.ACTION && LearningReminder.state(context)["enabled"] == true && LearningReminder.allowed(context)) {
                LearningReminder.show(context)
            }
        } catch (_: Exception) {
            // Permission/channel may change between checking and posting.
        } finally { try { LearningReminder.schedule(context) } catch (_: Exception) { } }
    }
}

class LearningReminderBridge(private val activity: MainActivity, messenger: io.flutter.plugin.common.BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.cuso4.flashcards/reminders")
    private var permissionResult: MethodChannel.Result? = null
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "state" -> result.success(LearningReminder.state(activity))
                    "save" -> { LearningReminder.configure(activity, call.argument<Boolean>("enabled") ?: false,
                        call.argument<Int>("hour") ?: 20, call.argument<Int>("minute") ?: 0); result.success(LearningReminder.state(activity)) }
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            check(permissionResult == null) { "正在申请通知权限" }
                            permissionResult = result
                            try {
                                activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4103)
                            } catch (error: Exception) {
                                permissionResult = null
                                throw error
                            }
                        } else result.success(LearningReminder.allowed(activity))
                    }
                    "settings" -> { activity.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, activity.packageName)); result.success(null) }
                    "test" -> { LearningReminder.show(activity, true); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("REMINDER_ERROR", error.message ?: "提醒设置失败", null) }
        }
        try { LearningReminder.schedule(activity) } catch (_: Exception) { }
    }
    fun permissionResponse(requestCode: Int): Boolean {
        if (requestCode != 4103) return false
        permissionResult?.success(LearningReminder.allowed(activity)); permissionResult = null
        return true
    }
    fun dispose() {
        permissionResult?.error("CLOSED", "页面已关闭，请重试", null); permissionResult = null
        channel.setMethodCallHandler(null)
    }
}
