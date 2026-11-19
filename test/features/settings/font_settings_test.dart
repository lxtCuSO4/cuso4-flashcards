import 'dart:convert';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/typography/font_scale_scope.dart';
import 'package:cuso4_flashcards/features/settings/data/font_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/font_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class NonlinearTestScaler extends TextScaler {
  const NonlinearTestScaler();
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.8 : fontSize * 1.3;
  @override
  double get textScaleFactor => 1.8;
}

void main() {
  test(
    'missing or invalid settings fall back without blocking card access',
    () {
      for (final raw in <String?>[
        null,
        'not-json',
        '[]',
        '{}',
        '{"uiPercent":151,"cardPercent":100}',
        '{"uiPercent":100,"cardPercent":201}',
        '{"uiPercent":100,"cardPercent":"NaN"}',
      ]) {
        expect(FontSettings.decode(raw).toJson(), {
          'uiPercent': 100,
          'cardPercent': 100,
        });
      }
      final value = FontSettings(uiPercent: 80, cardPercent: 200);
      expect(
        FontSettings.decode(jsonEncode(value.toJson())).toJson(),
        value.toJson(),
      );
      expect(() => FontSettings(uiPercent: 79), throwsArgumentError);
      expect(() => FontSettings(cardPercent: 201), throwsArgumentError);
    },
  );

  test(
    'multipliers preserve nonlinear platform scaling at different font sizes',
    () {
      const system = NonlinearTestScaler();
      expect(identical(applyFontPercent(system, 100), system), true);
      final scaled = applyFontPercent(system, 150);
      expect(scaled.scale(10), closeTo(27, .0001));
      expect(scaled.scale(30), closeTo(58.5, .0001));
      expect(applyFontPercent(system, 150), scaled);
    },
  );

  test('saving replaces both scales atomically and leaves unrelated settings untouched', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'theme', valueJson: 'dark'));
      final repository = FontSettingsRepository(db);
      await repository.save(FontSettings(uiPercent: 125, cardPercent: 175));
      await repository.save(FontSettings(uiPercent: 90, cardPercent: 150));
      final rows = await db.select(db.appSettings).get();
      expect(rows, hasLength(2));
      expect(rows.singleWhere((r) => r.key == 'theme').valueJson, 'dark');
      expect(
        FontSettings.decode(
          rows.singleWhere((r) => r.key == FontSettings.settingKey).valueJson,
        ).toJson(),
        {'uiPercent': 90, 'cardPercent': 150},
      );
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    } finally {
      await db.close();
    }
  });
}
