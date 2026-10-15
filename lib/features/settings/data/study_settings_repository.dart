import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../domain/study_settings.dart';

class StudySettingsRepository {
  StudySettingsRepository(this.db);
  final AppDatabase db;
  static const settingKey = 'studySettings';

  Future<StudySettings> load() async {
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(settingKey))).getSingleOrNull();
    if (row == null) return StudySettings();
    try {
      final json = jsonDecode(row.valueJson);
      if (json is! Map<String, dynamic>) throw const FormatException();
      return StudySettings.fromJson(json);
    } on FormatException {
      throw StateError('学习设置损坏，请保留数据并恢复有效备份。');
    } on ArgumentError {
      throw StateError('学习设置损坏，请保留数据并恢复有效备份。');
    }
  }

  /// One row replaces all three settings atomically. Existing card schedules
  /// and review history are intentionally untouched.
  Future<void> save(StudySettings settings) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: settingKey,
            valueJson: jsonEncode(settings.toJson()),
          ),
        );
  }
}
