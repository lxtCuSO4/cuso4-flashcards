# CuSO₄闪卡 Implementation Plan Set

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement these plans task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build and publicly distribute a fully offline Android flashcard app that imports standard Anki .apkg decks, supports local card authoring, and schedules reviews with FSRS.

**Architecture:** The implementation is split into four independently verifiable plans. Complete them in order because later plans depend on the database, domain interfaces, and UI primitives established earlier.

**Tech Stack:** Flutter, Dart, Riverpod, Drift and SQLite, FSRS, Android local notifications, local files, and split APK builds.

---

## Execution Order

1. Foundation, data model, and app shell: 2026-10-13-cuso4-foundation-plan.md
2. .apkg import and FSRS study engine: 2026-10-13-cuso4-import-study-plan.md
3. Product UI and enhanced offline features: 2026-10-13-cuso4-product-features-plan.md
4. Backup, hardening, signing, and public APK release: 2026-10-13-cuso4-release-plan.md

## Mandatory Checkpoints

- After Plan 1: app launches offline, theme and navigation work, CRUD persists in SQLite.
- After Plan 2: a fixture .apkg imports transactionally and cards complete a tested FSRS review cycle.
- After Plan 3: all approved user-facing features work on the 1220×2712 target screen.
- After Plan 4: signed ARM64, ARMv7, and universal APKs pass installation, upgrade, backup, and restore checks.

## Local Environment Note

At plan-writing time Java 22 is available, but Flutter is not on PATH and ANDROID_HOME or ANDROID_SDK_ROOT is not configured. Plan 1 installs a supported Flutter stable SDK and Android toolchain before production code is created.

## Global Engineering Rules

- Use strict red-green-refactor TDD for every behavior change.
- Keep domain and import code independent of Flutter widgets.
- Never add Internet permission or remote font and image dependencies.
- Store persisted timestamps in UTC and convert only at display boundaries.
- Run flutter test and flutter analyze before every checkpoint commit.
- Do not commit a signing keystore, passwords, generated APKs, imported decks, or user backups.
