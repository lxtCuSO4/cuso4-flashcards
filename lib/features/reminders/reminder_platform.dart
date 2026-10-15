import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reminderPlatformProvider = Provider((ref) => ReminderPlatform());

class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.allowed,
  });
  final bool enabled, allowed;
  final int hour, minute;
  factory ReminderSettings.fromMap(Map<dynamic, dynamic> value) =>
      ReminderSettings(
        enabled: value['enabled'] == true,
        hour: (value['hour'] as int?) ?? 20,
        minute: (value['minute'] as int?) ?? 0,
        allowed: value['allowed'] == true,
      );
}

class ReminderPlatform {
  ReminderPlatform({MethodChannel? channel})
    : channel =
          channel ?? const MethodChannel('com.cuso4.flashcards/reminders');
  final MethodChannel channel;
  Future<T?> _call<T>(String method, [Map<String, Object>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      throw StateError(error.message ?? '提醒设置失败，请重试。');
    }
  }

  Future<ReminderSettings> read() async =>
      ReminderSettings.fromMap(await _call<Map>('state') ?? {});
  Future<ReminderSettings> save({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('提醒时间不正确。');
    }
    return ReminderSettings.fromMap(
      await _call<Map>('save', {
            'enabled': enabled,
            'hour': hour,
            'minute': minute,
          }) ??
          {},
    );
  }

  Future<bool> requestPermission() async =>
      await _call<bool>('requestPermission') ?? false;
  Future<void> openSettings() async {
    await _call<void>('settings');
  }

  Future<void> test() async {
    await _call<void>('test');
  }
}
