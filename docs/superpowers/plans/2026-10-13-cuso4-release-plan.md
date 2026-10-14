# CuSO₄闪卡 Backup and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add reliable local backup and recovery, harden failure paths and database upgrades, and produce signed public APK variants for Android 8 and later.

**Architecture:** Backup and restore use versioned manifests, database snapshots, staged media, hashes, and atomic replacement. Release automation keeps signing secrets outside source control and produces reproducible ABI-specific and universal artifacts.

**Tech Stack:** Flutter integration_test, Drift migrations, archive, crypto, Android Gradle signing, adb, GitHub release notes or equivalent static distribution.

2026-10-15 执行状态：Task 1–4 和恢复中断的启动保护已实施并产出测试 APK，具体实现调整／验证证据见 `2026-10-15-local-backup-execution.md` 与 `docs/development-progress.md`。正式签名、其余迁移／恢复覆盖和公开发布仍未完成；按用户预算约束采用集中关键验证，不沿用逐任务双重代理审查。

---

### Task 1: Define the versioned backup format

**Files:**
- Create: lib/features/backup/domain/backup_manifest.dart
- Create: lib/features/backup/domain/backup_error.dart
- Test: test/features/backup/domain/backup_manifest_test.dart

- [ ] **Step 1: Write failing manifest tests**

Test formatVersion, appVersion, createdAtUtc, database hash, media hash map, settings inclusion, JSON round-trip, unknown required field rejection, and newer unsupported format rejection.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/backup/domain

Expected: FAIL because backup domain types do not exist.

- [ ] **Step 3: Implement version 1 manifest**

Use a strict decoder that ignores unknown optional fields but rejects missing required fields. Store no card content directly in the manifest. Define typed errors for unsupportedVersion, checksumMismatch, insufficientSpace, canceled, and invalidArchive.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/backup/domain
    git add lib/features/backup/domain test/features/backup/domain
    git commit -m "feat: define versioned local backup format"

### Task 2: Create consistent backups

**Files:**
- Create: lib/features/backup/data/backup_service.dart
- Create: lib/features/backup/data/database_snapshot_service.dart
- Test: test/features/backup/data/backup_service_test.dart

- [ ] **Step 1: Write failing backup tests**

Test a consistent SQLite snapshot while writes are paused briefly, only referenced media included, settings included, SHA-256 hashes correct, cancellation removes the temporary archive, and destination failure leaves no partial official backup.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/backup/data/backup_service_test.dart

Expected: FAIL because BackupService does not exist.

- [ ] **Step 3: Implement backup staging**

Checkpoint WAL, create a SQLite-safe snapshot, stream database and media into a temporary archive, write manifest last, verify the created archive, then hand the file to the system create-document flow. Use an ISO-like timestamp in the suggested filename.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/backup/data/backup_service_test.dart
    git add lib/features/backup/data test/features/backup/data
    git commit -m "feat: create complete offline backups"

### Task 3: Restore atomically with automatic pre-restore snapshot

**Files:**
- Create: lib/features/backup/data/restore_service.dart
- Test: test/features/backup/data/restore_service_test.dart

- [ ] **Step 1: Write failing restore tests**

Test checksum validation before replacement, insufficient-space refusal, automatic snapshot of current data, successful restoration of cards, media, settings, and FSRS state, corrupted-media rollback, and unsupported-version refusal.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/backup/data/restore_service_test.dart

Expected: FAIL because RestoreService does not exist.

- [ ] **Step 3: Implement staged restore**

Extract to a unique staging directory with traversal protection. Verify hashes and open the staged database with integrity_check. Close the live database, rename current data to a recovery snapshot, atomically move staged data into place, reopen, and delete the old snapshot only after health checks pass.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/backup/data/restore_service_test.dart
    git add lib/features/backup/data test/features/backup/data
    git commit -m "feat: restore local data atomically"

### Task 4: Build backup and restore interfaces

**Files:**
- Create: lib/features/backup/presentation/backup_page.dart
- Modify: lib/features/settings/presentation/settings_page.dart
- Test: test/features/backup/presentation/backup_page_test.dart

- [ ] **Step 1: Write failing UI tests**

Test backup progress and cancellation, restore risk confirmation, automatic snapshot explanation, success restart prompt, checksum failure message, and PressableAction tactile feedback for confirmations.

- [ ] **Step 2: Verify RED**

Run: flutter test test/features/backup/presentation

Expected: FAIL because BackupPage does not exist.

- [ ] **Step 3: Implement UI**

Show last backup time, approximate size, export, restore, and recovery snapshot status. Never silently overwrite live data. On restore success, rebuild providers and return to a stable root route.

- [ ] **Step 4: Verify GREEN and commit**

    flutter test test/features/backup
    git add lib/features/backup lib/features/settings test/features/backup
    git commit -m "feat: add local backup and recovery UI"

### Task 5: Harden database migration and interrupted jobs

**Files:**
- Modify: lib/core/database/app_database.dart
- Create: lib/core/recovery/startup_recovery_service.dart
- Test: test/core/recovery/startup_recovery_service_test.dart
- Test: test/core/database/migration_test.dart

- [ ] **Step 1: Write failing recovery tests**

Test cleanup of abandoned import staging directories, completion or rollback of media trash operations, detection of an interrupted restore snapshot, and preserving a valid current database when recovery artifacts are corrupt.

- [ ] **Step 2: Write failing migration tests**

Open version 1 and version 2 schema fixtures using current code, migrate to the latest version, and assert card state, tags, FTS content, review logs, and settings are unchanged.

- [ ] **Step 3: Verify RED**

Run:

    flutter test test/core/recovery test/core/database/migration_test.dart

Expected: recovery behavior or migration coverage fails before implementation.

- [ ] **Step 4: Implement startup recovery and migration snapshots**

Run recovery before repository providers are exposed. Every schema change must have a Drift migration test and a schema dump committed under drift_schemas.

- [ ] **Step 5: Verify GREEN and commit**

    flutter test test/core
    git add lib/core test/core drift_schemas
    git commit -m "feat: harden startup recovery and migrations"

### Task 6: Audit Android permissions and offline behavior

**Files:**
- Modify: android/app/src/main/AndroidManifest.xml
- Create: test/security/android_manifest_test.dart
- Create: integration_test/offline_app_test.dart

- [ ] **Step 1: Write failing manifest test**

Parse the merged or source manifest and assert INTERNET, broad external storage, contacts, location, microphone, and advertising permissions are absent. Allow only notification and plugin-required reboot scheduling permissions documented in the test.

- [ ] **Step 2: Verify RED if unwanted permissions exist**

Run: flutter test test/security/android_manifest_test.dart

- [ ] **Step 3: Add offline integration coverage**

Launch with network disabled, import fixture .apkg, create a card, complete reviews, view records, export a backup, and confirm no feature waits for network.

- [ ] **Step 4: Run tests and commit**

    flutter test test/security
    flutter test integration_test/offline_app_test.dart
    git add android test/security integration_test
    git commit -m "test: enforce private offline Android behavior"

### Task 7: Configure production signing without committing secrets

**Files:**
- Modify: android/app/build.gradle.kts
- Modify: .gitignore
- Create: android/key.properties.example
- Create: docs/release/signing.md
- Test: tool/verify_release_config.dart

- [ ] **Step 1: Write a failing release-config verifier**

The verifier checks applicationId, minSdk 26, versionName, versionCode, release signing config presence, forbidden tracked keystore files, and absence of plaintext passwords in tracked project files.

- [ ] **Step 2: Verify RED**

Run: dart run tool/verify_release_config.dart

Expected: FAIL because release signing is not configured.

- [ ] **Step 3: Generate the private signing key outside source control**

Use keytool to create a long-lived release keystore in a user-controlled secure directory. Store its passwords in local key.properties or environment variables. Back up the keystore separately. Never include key material in chat output, tests, or Git.

- [ ] **Step 4: Configure Gradle**

Load key.properties only when present. Release builds must fail clearly if signing values are missing. Add *.jks, *.keystore, key.properties, build/, backups, and APK artifacts to .gitignore. Commit only key.properties.example with placeholder field names.

- [ ] **Step 5: Verify GREEN and commit**

    dart run tool/verify_release_config.dart
    git add android .gitignore docs/release tool/verify_release_config.dart
    git commit -m "chore: configure secure Android release signing"

### Task 8: Build and install ABI-specific release APKs

**Files:**
- Create: tool/build_release.ps1
- Create: docs/release/build-and-install.md

- [ ] **Step 1: Implement the build script**

The script runs pub get, generated-code build, tests, analyzer, release-config verification, then:

    flutter build apk --release --split-per-abi
    flutter build apk --release

Copy outputs into a local untracked release directory with names CuSO4-Flashcards-arm64.apk, CuSO4-Flashcards-armv7.apk, and CuSO4-Flashcards-universal.apk. Also record SHA-256 hashes and byte sizes.

- [ ] **Step 2: Run the complete release build**

Run:

    powershell -ExecutionPolicy Bypass -File tool/build_release.ps1

Expected: tests and analyzer pass; signed split and universal APKs are produced.

- [ ] **Step 3: Verify signatures and SDK metadata**

Use apksigner verify --verbose and aapt dump badging. Confirm package com.cuso4.flashcards, minSdkVersion 26, expected version, and valid signing certificate.

- [ ] **Step 4: Install on devices**

Use adb install for a fresh install and adb install -r for an upgrade from the prior signed build. Test at least one ARM64 physical device, the 1220×2712 target device, and an Android 8 emulator. Install ARMv7 on a compatible emulator if no physical device exists.

- [ ] **Step 5: Commit scripts and documentation**

    git add tool/build_release.ps1 docs/release
    git commit -m "build: add reproducible APK release pipeline"

### Task 9: Execute final acceptance and public release checklist

**Files:**
- Create: docs/release/acceptance-checklist.md
- Create: docs/release/privacy.md
- Create: docs/release/release-notes-template.md

- [ ] **Step 1: Run automated verification**

    flutter test
    flutter analyze
    flutter test integration_test
    dart run tool/verify_release_config.dart
    powershell -ExecutionPolicy Bypass -File tool/build_release.ps1

Expected: every command passes with clean output.

- [ ] **Step 2: Run manual acceptance on the target phone**

Verify installation, first launch offline, .apkg import with image and audio, basic and Cloze authoring, all four review buttons and strong feedback, undo, favorites, search, calendar, statistics, theme switching, reminder permission, backup, restore, app restart, and upgrade installation.

- [ ] **Step 3: Validate failure paths**

Try damaged .apkg, missing media, import cancellation, low storage simulation, notification denial, corrupted backup, interrupted restore recovery, large text, reduced animation, feedback off, and system dark mode.

- [ ] **Step 4: Prepare public distribution metadata**

Privacy documentation states no network, account, ads, or analytics. Release notes state Android 8 minimum, architecture selection guidance, backup recommendation, current .apkg compatibility, known custom-template limits, APK SHA-256 hashes, and upgrade signature requirements.

- [ ] **Step 5: Commit the release documentation**

    git add docs/release
    git commit -m "docs: add CuSO4 public release checklist"

### Task 10: Final verification before completion claim

**Files:**
- Verify only; modify failures at their owning task files.

- [ ] **Step 1: Use verification-before-completion skill**

Load superpowers:verification-before-completion and follow its evidence requirements.

- [ ] **Step 2: Record evidence**

Record exact test totals, analyzer result, APK filenames, sizes, hashes, apksigner output summary, device models and Android versions, fresh-install result, upgrade result, and backup/restore result.

- [ ] **Step 3: Confirm no required work remains**

Do not call the app complete if any acceptance item is skipped, any permission is unexplained, any artifact is unsigned, or the target 1220×2712 device has not been checked.
