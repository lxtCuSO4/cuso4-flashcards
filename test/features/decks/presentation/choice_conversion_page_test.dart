import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/decks/presentation/choice_conversion_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'scan and cancel never write; explicit confirmation converts once',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deck = await DeckRepository(db).createDeck('题目');
      final notes = NoteRepository(db);
      final note = await notes.createBasicNote(
        deckId: deck,
        front: '问题<br>A. 甲<br>B. 乙',
        back: '答案：A',
      );
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(home: ChoiceConversionPage(deckId: deck)),
        ),
      );
      Future<void> tap(String label, {bool settle = true}) async {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        if (settle) {
          await tester.pumpAndSettle();
        } else {
          // The pressed action stays busy while its confirmation dialog is open.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      await tap('扫描基础卡');
      expect(find.text('可转为单选题：1 条'), findsOneWidget);
      expect((await notes.getNote(note)).type, NoteType.basic);
      await tap('转换为选择题', settle: false);
      expect(find.text('确认转换选择题？'), findsOneWidget);
      await tap('取消');
      expect((await notes.getNote(note)).type, NoteType.basic);
      await tap('转换为选择题', settle: false);
      await tap('确认转换');
      expect((await notes.getNote(note)).type, NoteType.singleChoice);
      expect(find.text('已转换 1 条选择题，学习进度已保留。'), findsOneWidget);
      await tap('扫描基础卡');
      expect(find.text('可转为单选题：0 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
