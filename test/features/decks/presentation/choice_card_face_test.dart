import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/local_audio_controller.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/decks/presentation/choice_card_face.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late MediaRepository media;
  late LocalAudioController audio;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('choice_ui_');
    media = MediaRepository(db, directory: root);
    audio = LocalAudioController(media);
  });
  tearDown(() async {
    audio.dispose();
    await db.close();
    await root.delete(recursive: true);
  });
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final type in [NoteType.singleChoice, NoteType.multipleChoice]) {
    testWidgets(
      '${type.name}: exact grading, locking and reset at large text',
      (tester) async {
        tester.view.physicalSize = const Size(1220, 2712);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var revealed = false;
        late StateSetter update;
        final question = ChoiceQuestion(
          type: type,
          prompt: '选出正确项',
          options: ['铜', '硫', '铁'],
          correctIndexes: type == NoteType.singleChoice ? [1] : [0, 1],
          explanation: '解析内容',
          shuffle: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.8)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: ChoiceCardFace(
                        question: question,
                        media: media,
                        audio: audio,
                        answerVisible: revealed,
                        onReveal: () => update(() => revealed = true),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        expect(find.text('解析内容'), findsNothing);
        await tap(tester, find.byKey(const ValueKey('choice-option-0')));
        if (type == NoteType.singleChoice) {
          await tap(tester, find.byKey(const ValueKey('choice-option-1')));
        }
        final order = tester
            .widgetList<InkWell>(find.byType(InkWell))
            .where((w) => w.key.toString().contains('choice-option'))
            .map((w) => w.key)
            .toList();
        update(() {});
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<InkWell>(find.byType(InkWell))
              .where((w) => w.key.toString().contains('choice-option'))
              .map((w) => w.key)
              .toList(),
          order,
        );
        await tap(tester, find.text('提交答案'));
        expect(
          find.text(type == NoteType.singleChoice ? '回答正确' : '回答错误'),
          findsOneWidget,
        );
        expect(find.text('解析内容'), findsOneWidget);
        expect(
          tester
              .widget<InkWell>(find.byKey(const ValueKey('choice-option-2')))
              .onTap,
          isNull,
        );
        expect(await db.select(db.reviewLogs).get(), isEmpty);
        update(() => revealed = false);
        await tester.pumpAndSettle();
        await tap(tester, find.text('直接看答案'));
        expect(find.text('未作答'), findsOneWidget);
        tester.view.physicalSize = const Size(2712, 1220);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
