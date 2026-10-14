# CuSO₄闪卡 Import and Study Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Import supported Anki .apkg decks transactionally and provide a complete, local, tested FSRS review session.

**Architecture:** Import is a staged pipeline: inspect archive, open Anki SQLite read-only, convert supported notes, stage media, then commit through repositories. The study engine wraps the FSRS library behind a local interface and writes card state plus review logs atomically.

**Tech Stack:** Dart archive and SQLite libraries, Drift, fsrs 2.0.1, file_picker, path_provider, audioplayers, Flutter isolates.

---

## File Structure

    lib/features/import/domain/import_report.dart
    lib/features/import/domain/import_error.dart
    lib/features/import/data/apkg_archive_reader.dart
    lib/features/import/data/anki_collection_reader.dart
    lib/features/import/data/anki_note_converter.dart
    lib/features/import/data/media_importer.dart
    lib/features/import/data/apkg_import_service.dart
    lib/features/import/presentation/import_page.dart
    lib/features/study/domain/scheduler.dart
    lib/features/study/data/fsrs_scheduler.dart
    lib/features/study/data/study_repository.dart
    lib/features/study/application/study_session_controller.dart
    lib/features/study/presentation/study_page.dart
    lib/features/study/presentation/review_rating_bar.dart
    test/fixtures/apkg/basic.apkg
    test/fixtures/apkg/cloze-media.apkg
    test/fixtures/apkg/damaged.apkg
    test/features/import/*
    test/features/study/*

### Task 1: Create deterministic .apkg fixtures

**Files:**
- Create: tool/build_apkg_fixtures.dart
- Create: test/fixtures/apkg/basic.apkg
- Create: test/fixtures/apkg/cloze-media.apkg
- Create: test/fixtures/apkg/damaged.apkg
- Test: test/fixtures/apkg_fixture_test.dart

- [ ] **Step 1: Write a failing fixture inventory test**

Assert basic.apkg contains a collection database and media manifest, cloze-media.apkg contains a standard Cloze note plus one image and one audio reference, and damaged.apkg fails ZIP integrity inspection.

- [ ] **Step 2: Verify RED**

Run:

    flutter test test/fixtures/apkg_fixture_test.dart

Expected: FAIL because fixture files do not exist.

- [ ] **Step 3: Implement the fixture builder**

The tool creates minimal Anki 2.1-compatible SQLite data and ZIP archives using fixed IDs and timestamps. Do not depend on a locally installed Anki application. Include nested deck name Languages::Japanese, tags, a basic note, a standard Cloze note, a tiny PNG, and a short local audio sample with permissive test licensing.

- [ ] **Step 4: Generate and verify fixtures**

Run:

    dart run tool/build_apkg_fixtures.dart
    flutter test test/fixtures/apkg_fixture_test.dart

Expected: PASS and fixtures are deterministic between runs.

- [ ] **Step 5: Commit**

    git add tool test/fixtures
    git commit -m "test: add deterministic apkg fixtures"

### Task 2: Inspect and validate .apkg archives

**Files:**
- Create: lib/features/import/domain/import_report.dart
- Create: lib/features/import/domain/import_error.dart
- Create: lib/features/import/data/apkg_archive_reader.dart
- Test: test/features/import/data/apkg_archive_reader_test.dart

- [ ] **Step 1: Write failing archive tests**

Test selecting the supported collection database entry, parsing the media JSON map, rejecting path traversal entries, rejecting a non-ZIP file, and returning a specific damagedArchive error for damaged.apkg.

- [ ] **Step 2: Verify RED**

Run:

    flutter test test/features/import/data/apkg_archive_reader_test.dart

Expected: FAIL because ApkgArchiveReader does not exist.

- [ ] **Step 3: Add packages and implement reader**

Run:

    flutter pub add archive file_picker crypto

The reader copies the selected URI to an app cache file, streams ZIP extraction to a unique temporary directory, rejects absolute paths and parent traversal, enforces configurable extracted-size and entry-count limits, and returns typed paths to the collection and media manifest.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/import/data/apkg_archive_reader_test.dart
    git add pubspec.yaml pubspec.lock lib/features/import test/features/import
    git commit -m "feat: validate apkg archives safely"

### Task 3: Read supported Anki collection data

**Files:**
- Create: lib/features/import/data/anki_collection_reader.dart
- Create: lib/features/import/data/anki_models.dart
- Test: test/features/import/data/anki_collection_reader_test.dart

- [ ] **Step 1: Write failing reader tests**

Test reading nested deck names, note fields separated by the Anki unit separator, tags, model type, card ordinals, and media references from both fixtures. Add a test that an unsupported schema version produces unsupportedCollectionVersion.

- [ ] **Step 2: Verify RED**

Run:

    flutter test test/features/import/data/anki_collection_reader_test.dart

Expected: FAIL because collection reader types do not exist.

- [ ] **Step 3: Implement read-only access**

Open the extracted Anki database read-only with sqlite3. Decode decks and models JSON, stream notes and cards in batches, and expose neutral AnkiDeck, AnkiModel, AnkiNote, and AnkiCard records. Never write to the source database.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/import/data/anki_collection_reader_test.dart
    git add lib/features/import/data test/features/import/data
    git commit -m "feat: read supported Anki collections"

### Task 4: Convert notes and sanitize local card content

**Files:**
- Create: lib/features/import/data/anki_note_converter.dart
- Create: lib/core/content/html_sanitizer.dart
- Test: test/features/import/data/anki_note_converter_test.dart
- Test: test/core/content/html_sanitizer_test.dart

- [ ] **Step 1: Write failing conversion tests**

Test basic front and back mapping, Cloze source mapping, tag preservation, br and formatting preservation, script and remote image removal, sound marker extraction, local image rewriting, and a typed skippedCustomTemplate result when field mapping is ambiguous.

- [ ] **Step 2: Verify RED**

Run:

    flutter test test/features/import/data/anki_note_converter_test.dart test/core/content/html_sanitizer_test.dart

Expected: FAIL because converter and sanitizer are absent.

- [ ] **Step 3: Implement sanitizer and converter**

Allow safe text formatting tags and safe inline styles only. Remove script, iframe, event handlers, remote URLs, data URLs beyond a small configured limit, and dangerous protocols. Convert Anki sound markers into explicit media tokens. Produce CreateBasicNoteCommand or CreateClozeNoteCommand plus media references.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/import/data/anki_note_converter_test.dart test/core/content/html_sanitizer_test.dart
    git add lib/core/content lib/features/import/data test
    git commit -m "feat: convert safe Anki card content"

### Task 5: Import media with hashing and reference counts

**Files:**
- Create: lib/features/import/data/media_importer.dart
- Create: lib/core/media/media_repository.dart
- Test: test/features/import/data/media_importer_test.dart

- [ ] **Step 1: Write failing media tests**

Test SHA-256 deduplication, two filenames referencing one content hash, missing media reporting, copy cancellation cleanup, and reference increment only after database commit.

- [ ] **Step 2: Verify RED**

Run:

    flutter test test/features/import/data/media_importer_test.dart

Expected: FAIL because MediaImporter does not exist.

- [ ] **Step 3: Implement staged media import**

Copy media to an import staging directory, calculate SHA-256 while streaming, validate known image and audio signatures, and prepare database rows. Move staged files into the content-addressed media directory only within the import commit boundary; on failure remove staging files.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/import/data/media_importer_test.dart
    git add lib/core/media lib/features/import/data test/features/import/data
    git commit -m "feat: import local card media safely"

### Task 6: Orchestrate a transactional .apkg import

**Files:**
- Create: lib/features/import/data/apkg_import_service.dart
- Create: lib/features/import/application/import_controller.dart
- Test: test/features/import/data/apkg_import_service_test.dart

- [ ] **Step 1: Write failing service tests**

Test successful import counts, all imported cards start as new, nested deck creation, same-name create-copy behavior, same-name merge behavior without overwriting existing notes, rollback after a forced media failure, cancellation rollback, and a report containing skipped reason counts.

- [ ] **Step 2: Verify RED**

Run:

    flutter test test/features/import/data/apkg_import_service_test.dart

Expected: FAIL because ApkgImportService is absent.

- [ ] **Step 3: Implement staged orchestration**

Run archive inspection and collection reading in an isolate. Persist ImportJob status. Convert notes in bounded batches. Begin one Drift transaction for decks, notes, cards, tags, media rows, and report rows. Initialize every card with new state and no imported Anki schedule fields. Roll back database and staged media on cancellation or error.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/import/data/apkg_import_service_test.dart
    git add lib/features/import test/features/import
    git commit -m "feat: import apkg decks transactionally"

### Task 7: Wrap FSRS behind a stable scheduler interface

**Files:**
- Create: lib/features/study/domain/scheduler.dart
- Create: lib/features/study/data/fsrs_scheduler.dart
- Test: test/features/study/data/fsrs_scheduler_test.dart

- [x] **Step 1: Add FSRS and write failing contract tests**

Run:

    flutter pub add fsrs:2.0.1

Write tests against the local Scheduler interface, not package classes. Test default desired retention 0.90, Again less than Hard less than Good less than Easy intervals, UTC due dates, deterministic output for a fixed clock, and serialization round-trip of scheduler state.

- [x] **Step 2: Verify RED**

Run:

    flutter test test/features/study/data/fsrs_scheduler_test.dart

Expected: FAIL because Scheduler is not implemented.

- [x] **Step 3: Implement FsrsScheduler adapter**

Map local ReviewRating to the package Rating and local card state to the package card type. Keep package-specific types inside fsrs_scheduler.dart. Validate retention input between supported bounds and expose previewIntervals plus applyReview.

- [x] **Step 4: Verify GREEN and commit**

    flutter test test/features/study/data/fsrs_scheduler_test.dart
    git add pubspec.yaml pubspec.lock lib/features/study test/features/study
    git commit -m "feat: add local FSRS scheduler"

### Task 8: Implement atomic study sessions and undo

**Files:**
- Create: lib/features/study/data/study_repository.dart
- Create: lib/features/study/application/study_session_controller.dart
- Test: test/features/study/application/study_session_controller_test.dart

- [x] **Step 1: Write failing session tests**

Test queue order due review, learning, new; per-deck daily new limit; rating atomically updates card and inserts ReviewLog; undo restores the exact previous snapshot and removes the log; favorites do not change due dates; and midnight or timezone change does not duplicate the daily new-card count.

- [x] **Step 2: Verify RED**

Run:

    flutter test test/features/study/application/study_session_controller_test.dart

Expected: FAIL because study session classes do not exist.

- [x] **Step 3: Implement repository and controller**

StudyRepository queries a bounded queue using indexed due fields. A rating transaction stores before and after scheduler snapshots in ReviewLog. StudySessionController owns current card, answer visibility, interval previews, elapsed response time, rating lock, undo availability, and session completion.

- [x] **Step 4: Verify GREEN and commit**

    flutter test test/features/study
    git add lib/features/study test/features/study
    git commit -m "feat: add atomic FSRS study sessions"

### Task 9: Build import and immersive study interfaces

2026-10-15 执行检查点：导入/学习页面、媒体只读解析和本地音频控制源码已接入；完整 103 项测试通过，静态分析无问题。根据预算与工程内修改约束，音频改用 Android MediaPlayer/MethodChannel，不新增 audioplayers 依赖。APK 构建、原生 Kotlin 编译和真实设备验证待补，不能将本任务的构建/实机检查标记完成。详见 docs/development-progress.md。

**Files:**
- Create: lib/features/import/presentation/import_page.dart
- Create: lib/features/import/presentation/import_result_page.dart
- Create: lib/features/study/presentation/study_page.dart
- Create: lib/features/study/presentation/review_rating_bar.dart
- Create: lib/core/media/local_audio_controller.dart
- Test: test/features/import/presentation/import_page_test.dart
- Test: test/features/study/presentation/study_page_test.dart

- [ ] **Step 1: Write failing import UI tests**

Test file selection, progress phases, cancellation, same-name choice dialog, success counts, and readable error actions.

- [ ] **Step 2: Write failing study UI tests**

Test ratings hidden before answer, four ratings and interval previews after answer, a second rating tap blocked, medium tactile confirmation requested, undo action, favorite action, missing media placeholder, and local audio playback control.

- [ ] **Step 3: Verify RED**

Run:

    flutter test test/features/import/presentation test/features/study/presentation

Expected: FAIL because pages do not exist.

- [ ] **Step 4: Add audio dependency and implement pages**

Run:

    flutter pub add audioplayers

Use the approved focused dark-green review surface, cyan accents, SafeArea, 48dp targets, PressableAction, and no remote WebView content. Render sanitized rich text and local media only.

- [ ] **Step 5: Run the phase checkpoint**

    flutter test
    flutter analyze
    flutter build apk --debug

Expected: all tests pass and a fixture deck can be imported and reviewed on an emulator without network access.

- [ ] **Step 6: Commit**

    git add lib test pubspec.yaml pubspec.lock
    git commit -m "feat: deliver apkg import and FSRS study flow"
