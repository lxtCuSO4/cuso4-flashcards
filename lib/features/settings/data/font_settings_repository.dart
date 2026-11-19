import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../domain/font_settings.dart';

class FontSettingsRepository {
  FontSettingsRepository(this.db);
  final AppDatabase db;

  Future<void> save(FontSettings settings) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: FontSettings.settingKey,
            valueJson: jsonEncode(settings.toJson()),
          ),
        );
  }
}
