import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/settings/data/study_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/study_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late StudySettingsRepository repository;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = StudySettingsRepository(db);
  });
  tearDown(() => db.close());

  test('defaults and saved values survive a new repository', () async {
    final defaults = await repository.load();
    expect(defaults.dailyNewLimit, 20);
    expect(defaults.dailyReviewLimit, 200);
    expect(defaults.desiredRetention, .9);
    final settings = StudySettings(
      dailyNewLimit: 0,
      dailyReviewLimit: 99999,
      desiredRetentionPercent: 99,
    );
    await repository.save(settings);
    expect(
      (await StudySettingsRepository(db).load()).toJson(),
      settings.toJson(),
    );
  });

  test('boundaries reject invalid settings before persistence', () async {
    for (final values in [
      {'dailyNewLimit': -1},
      {'dailyNewLimit': 10000},
      {'dailyReviewLimit': -1},
      {'dailyReviewLimit': 100000},
      {'desiredRetentionPercent': 69},
      {'desiredRetentionPercent': 100},
      {'dailyNewLimit': 1.5},
      {'desiredRetentionPercent': '90'},
    ]) {
      expect(
        () => StudySettings.fromJson({...StudySettings().toJson(), ...values}),
        throwsArgumentError,
      );
    }
    final minimum = StudySettings(
      dailyNewLimit: 9999,
      dailyReviewLimit: 0,
      desiredRetentionPercent: 70,
    );
    await repository.save(minimum);
    expect((await repository.load()).desiredRetention, .7);
  });

  test('failed replacement preserves the complete previous settings', () async {
    final previous = StudySettings(dailyNewLimit: 12);
    await repository.save(previous);
    await db.customStatement(
      "CREATE TRIGGER fail_settings BEFORE UPDATE ON app_settings BEGIN SELECT RAISE(FAIL, 'failure'); END",
    );
    await expectLater(
      repository.save(
        StudySettings(dailyNewLimit: 1, desiredRetentionPercent: 95),
      ),
      throwsA(anything),
    );
    expect((await repository.load()).toJson(), previous.toJson());
    expect((await db.select(db.appSettings).get()).length, 1);
  });

  test(
    'corrupt stored settings fail explicitly rather than silently reset',
    () async {
      for (final value in ['{', '[]', '{"dailyNewLimit":-1}', 'null']) {
        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: StudySettingsRepository.settingKey,
                valueJson: value,
              ),
            );
        await expectLater(repository.load(), throwsStateError);
      }
    },
  );
}
