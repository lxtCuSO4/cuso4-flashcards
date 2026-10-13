# CuSO₄闪卡 Product Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Complete the approved 专注融合 product experience with local authoring, search, favorites, statistics, calendar, themes, reminders, and storage controls.

**Architecture:** Each user-facing feature owns its query service, Riverpod controller, and presentation widgets. Aggregations run from local indexed review logs. Settings are persisted in SQLite and mirrored to platform services through small interfaces.

**Tech Stack:** Flutter, Riverpod, Drift FTS5, flutter_local_notifications, timezone, fl_chart or CustomPainter, integration_test.

---

### Task 1: Build the 今日 dashboard from real study data

**Files:**
- Create: lib/features/home/application/home_summary_service.dart
- Modify: lib/features/home/presentation/home_page.dart
- Test: test/features/home/application/home_summary_service_test.dart
- Test: test/features/home/presentation/home_page_test.dart

- [ ] **Step 1: Write failing summary tests**

Test due count, learning count, new count after daily limits, estimated minutes based on recent response times, and streak calculation across local calendar dates.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/home

Expected: FAIL because HomeSummaryService does not exist.

- [ ] **Step 3: Implement queries and dashboard**

Show the circular daily progress, due number, streak, primary 进入专注学习 action, and a concise deck list. Every action uses PressableAction. Empty data offers import and create-card paths.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/home
    git add lib/features/home test/features/home
    git commit -m "feat: add live daily study dashboard"

### Task 2: Build card and deck authoring interfaces

**Files:**
- Create: lib/features/decks/presentation/deck_editor_page.dart
- Create: lib/features/decks/presentation/card_browser_page.dart
- Create: lib/features/decks/presentation/note_editor_page.dart
- Create: lib/features/decks/application/note_editor_controller.dart
- Test: test/features/decks/presentation/note_editor_page_test.dart

- [ ] **Step 1: Write failing editor tests**

Test creating basic cards, creating multi-index Cloze cards, validation for blank front or no Cloze marker, editing without resetting schedule, confirmed removal of existing Cloze cards, deleting a note, renaming a deck, and moving a deck without cycles.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/decks/presentation

Expected: FAIL because authoring pages do not exist.

- [ ] **Step 3: Implement accessible editors**

Use native text fields, explicit labels, inline validation, a simple local rich-text toolbar for supported formatting, local image and audio attachment through the system picker, and a preview tab that uses the same card renderer as study mode.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/decks/presentation
    git add lib/features/decks test/features/decks
    git commit -m "feat: add deck and card authoring"

### Task 3: Add indexed search, tags, and batch actions

**Files:**
- Modify: lib/core/database/app_database.dart
- Create: lib/features/search/data/search_repository.dart
- Create: lib/features/search/presentation/search_page.dart
- Test: test/features/search/data/search_repository_test.dart
- Test: test/features/search/presentation/search_page_test.dart

- [ ] **Step 1: Write failing search tests**

Test Chinese and Latin text search, tag intersection, deck filter, note-type filter, favorite filter, stable ordering, and batch add-tag, move-deck, and delete operations.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/search

Expected: FAIL because search schema and repository do not exist.

- [ ] **Step 3: Add database migration version 2**

Create an FTS5 table or equivalent indexed normalized search table populated from note fields. Add triggers or repository updates to keep it synchronized. Write a migration test from schema version 1 to 2 before implementing the migration.

- [ ] **Step 4: Implement search page**

Debounce text input locally, expose filter chips with accessible labels, paginate results, and provide selection mode for batch actions. Never load every card into memory.

- [ ] **Step 5: Verify GREEN and commit**

    dart run build_runner build --delete-conflicting-outputs
    flutter test test/features/search test/core/database
    git add lib test drift_schemas
    git commit -m "feat: add offline card search and tags"

### Task 4: Complete favorites and dedicated mistake practice

**Files:**
- Create: lib/features/favorites/data/favorite_repository.dart
- Create: lib/features/favorites/presentation/favorites_page.dart
- Test: test/features/favorites/favorite_repository_test.dart
- Test: test/features/favorites/favorites_page_test.dart

- [ ] **Step 1: Write failing favorite tests**

Test filtering by deck, tag, lapse count, and last failure date. Test preview-only practice leaves FSRS unchanged, while normal-rating practice writes a standard review log.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/favorites

Expected: FAIL because favorite repository and page do not exist.

- [ ] **Step 3: Implement repository and UI**

Add a 收藏入口 to 记录 and study overflow actions. Clearly label preview-only versus normal-rating modes before a session begins.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/favorites
    git add lib/features/favorites test/features/favorites
    git commit -m "feat: add favorite mistake practice"

### Task 5: Implement learning calendar and statistics

**Files:**
- Create: lib/features/records/data/statistics_repository.dart
- Create: lib/features/records/domain/daily_statistics.dart
- Modify: lib/features/records/presentation/records_page.dart
- Create: lib/features/records/presentation/learning_calendar.dart
- Create: lib/features/records/presentation/statistics_charts.dart
- Test: test/features/records/data/statistics_repository_test.dart
- Test: test/features/records/presentation/records_page_test.dart

- [ ] **Step 1: Write failing aggregation tests**

Test day boundaries in Asia/Shanghai and another timezone, review count, study duration, Again/Hard/Good/Easy distribution, success rate definition, streak, and 7/30/90/all range queries.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/records

Expected: FAIL because statistics classes do not exist.

- [ ] **Step 3: Implement local aggregations**

Aggregate from ReviewLog with indexed UTC ranges converted from requested local dates. Document success rate as non-Again answers divided by rated answers. Cache only derived display results, never duplicate source logs.

- [ ] **Step 4: Implement calendar and charts**

Calendar uses intensity cells and opens a day detail sheet. Charts provide visible labels and text summaries so color is not the only signal. Keep rendering responsive at 320 logical pixels.

- [ ] **Step 5: Verify GREEN and commit**

    flutter test test/features/records
    git add lib/features/records test/features/records
    git commit -m "feat: add learning calendar and statistics"

### Task 6: Persist theme and feedback preferences

**Files:**
- Create: lib/features/settings/data/settings_repository.dart
- Create: lib/features/settings/application/settings_controller.dart
- Modify: lib/features/settings/presentation/settings_page.dart
- Modify: lib/app/cuso4_app.dart
- Test: test/features/settings/settings_controller_test.dart

- [ ] **Step 1: Write failing settings tests**

Test system/light/dark persistence, strong/gentle/off feedback persistence, default desired retention 0.90, valid daily limits, and restoration after app restart.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/settings

Expected: FAIL because SettingsRepository does not exist.

- [ ] **Step 3: Implement settings flow**

Store typed settings in app_settings. Cuso4App watches theme mode. FeedbackController watches strength. Validate FSRS retention before saving and display advanced settings behind a disclosure section.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/settings
    git add lib/features/settings lib/app test/features/settings
    git commit -m "feat: add persistent theme and study settings"

### Task 7: Add local daily reminders

**Files:**
- Create: lib/core/notifications/reminder_service.dart
- Create: lib/core/notifications/flutter_reminder_service.dart
- Modify: lib/features/settings/presentation/settings_page.dart
- Modify: android/app/src/main/AndroidManifest.xml
- Test: test/core/notifications/reminder_service_test.dart

- [ ] **Step 1: Add packages and write failing tests**

Run:

    flutter pub add flutter_local_notifications timezone flutter_timezone

Test scheduling at local wall-clock time, rescheduling after timezone change, canceling, no permission request before the user enables reminders, and message text containing due count but no card body.

- [ ] **Step 2: Verify RED**

Run: flutter test test/core/notifications

Expected: FAIL because ReminderService does not exist.

- [ ] **Step 3: Implement platform adapter**

Use zonedSchedule. Add Android 13 notification permission only. Configure reboot rescheduling if required by the plugin, with explicit manifest entries documented and tested on Android 8 and 13+.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/core/notifications test/features/settings
    git add lib android pubspec.yaml pubspec.lock test
    git commit -m "feat: add private local study reminders"

### Task 8: Add storage usage and safe cleanup

**Files:**
- Create: lib/features/settings/data/storage_service.dart
- Create: lib/features/settings/presentation/storage_page.dart
- Test: test/features/settings/storage_service_test.dart

- [ ] **Step 1: Write failing storage tests**

Test database, referenced media, cache, and backup byte totals; clearing import cache; identifying zero-reference media; and retaining zero-reference files during the recovery grace period.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/settings/storage_service_test.dart

Expected: FAIL because StorageService does not exist.

- [ ] **Step 3: Implement storage page**

Display categories and human-readable sizes. Cache cleanup is immediate after confirmation. Orphan media cleanup moves files to a recoverable trash folder before permanent deletion on a later maintenance pass.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/settings
    git add lib/features/settings test/features/settings
    git commit -m "feat: add local storage management"

### Task 9: Validate target-device responsiveness and accessibility

**Files:**
- Create: integration_test/target_device_layout_test.dart
- Create: test/goldens/target_device/*
- Modify: affected presentation widgets

- [ ] **Step 1: Write failing layout tests**

Use tester.view.physicalSize 1220×2712 with a representative devicePixelRatio, plus 720×1280, 1080×1920, 1600×2560, and a tablet width. Test textScaleFactor 1.0, 1.3, and 2.0. Assert no overflow exceptions, four rating buttons remain reachable, and bottom navigation avoids system insets.

- [ ] **Step 2: Verify RED where layouts overflow**

Run:

    flutter test integration_test/target_device_layout_test.dart

Expected: any current overflow is reproduced before layout fixes.

- [ ] **Step 3: Fix responsive layouts and capture goldens**

Use LayoutBuilder and explicit breakpoints, not physical-inch assumptions. Ensure at least 48dp touch targets, semantics labels, high-contrast selected states, reduced-motion behavior, and no required hover interactions.

- [ ] **Step 4: Run the product checkpoint**

    flutter test
    flutter analyze
    flutter test integration_test
    flutter build apk --debug

Expected: all tests pass and the approved product experience is usable on the target profile.

- [ ] **Step 5: Commit**

    git add lib test integration_test
    git commit -m "feat: complete responsive CuSO4 product experience"
