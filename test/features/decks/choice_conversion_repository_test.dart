import 'dart:convert';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/choice_conversion_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late ChoiceConversionRepository conversion;
  late int deck, child;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    notes = NoteRepository(db);
    conversion = ChoiceConversionRepository(db);
    deck = await DeckRepository(db).createDeck('主牌组');
    child = await DeckRepository(db).createDeck('子章节', parentId: deck);
  });
  tearDown(() => db.close());
  Future<int> add(int target, {String answer = 'A', String media = ''}) =>
      notes.createBasicNote(
        deckId: target,
        front: '题干<br>A. 甲$media<br>B. 乙',
        back: '答案：$answer<br>解析：原解析',
        tags: ['保留标签'],
      );

  test('preview is read-only; apply preserves every card, log, favorite, tag and media row', () async {
    final hash = List.filled(64, 'a').join();
    await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            contentHash: hash,
            originalName: 'a.png',
            relativePath: hash,
            mimeType: 'image/png',
            byteLength: 10,
            createdAtUtc: 1,
          ),
        );
    final single = await add(deck, media: '<img src="media:$hash">');
    await add(child, answer: 'AB');
    await notes.createBasicNote(deckId: child, front: '普通卡', back: '回答');
    await notes.createClozeNote(deckId: deck, text: '{{c1::填空}}');
    final outside = await DeckRepository(db).createDeck('其他牌组');
    await add(outside);
    final study = StudyRepository(db);
    final card = (await study.loadQueue()).firstWhere(
      (c) => c.noteId == single,
    );
    await study.rateCard(card, ReviewRating.good);
    await study.setFavorite(card.id, true);
    final cardsBefore = await db.select(db.cards).get();
    final logsBefore = await db.select(db.reviewLogs).get();
    final favoritesBefore = await db.select(db.favorites).get();
    final tagsBefore = await db.select(db.noteTags).get();
    final mediaBefore = await db.select(db.media).get();
    final notesBefore = await db.select(db.notes).get();
    final preview = await conversion.scan(deck);
    expect(
      (preview.singleChoice, preview.multipleChoice, preview.retainedBasic),
      (1, 1, 1),
    );
    expect(await db.select(db.notes).get(), notesBefore);
    expect(await conversion.apply(preview), 2);
    expect((await notes.getNote(single)).type, NoteType.singleChoice);
    expect(await db.select(db.cards).get(), cardsBefore);
    expect(await db.select(db.reviewLogs).get(), logsBefore);
    expect(await db.select(db.favorites).get(), favoritesBefore);
    expect(await db.select(db.noteTags).get(), tagsBefore);
    expect(await db.select(db.media).get(), mediaBefore);
    expect((await conversion.scan(deck)).total, 0);
    await expectLater(conversion.apply(preview), throwsStateError);
  });

  test('stale preview rolls back entire batch after a note changes or leaves the subtree', () async {
    final first = await add(deck);
    final second = await add(child);
    final preview = await conversion.scan(deck);
    await (db.update(db.notes)..where((n) => n.id.equals(second))).write(
      NotesCompanion(
        fieldsJson: Value(jsonEncode({'front': '已编辑', 'back': '新答案'})),
      ),
    );
    await expectLater(conversion.apply(preview), throwsStateError);
    expect((await notes.getNote(first)).type, NoteType.basic);
    final next = await conversion.scan(deck);
    final elsewhere = await DeckRepository(db).createDeck('其他');
    await (db.update(db.notes)..where((n) => n.id.equals(first))).write(
      NotesCompanion(deckId: Value(elsewhere)),
    );
    await expectLater(conversion.apply(next), throwsStateError);
    expect((await notes.getNote(first)).type, NoteType.basic);
  });

  test('nonstandard card structures are retained and new reviews after preview survive conversion', () async {
    final first = await add(deck);
    final second = await add(deck);
    await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            noteId: second,
            clozeIndex: const Value(1),
            dueAtUtc: 1,
          ),
        );
    final preview = await conversion.scan(deck);
    expect((preview.total, preview.retainedBasic), (1, 1));
    final study = StudyRepository(db);
    await study.rateCard(
      (await study.loadQueue()).firstWhere((c) => c.noteId == first),
      ReviewRating.good,
    );
    final current = await db.select(db.cards).get();
    await conversion.apply(preview);
    expect(await db.select(db.cards).get(), current);
    expect((await notes.getNote(second)).type, NoteType.basic);
  });
}
