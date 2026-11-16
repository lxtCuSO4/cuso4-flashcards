# Choice Practice Implementation Plan

**Goal:** 选择题独立刷题，错题答对自动移出，保留文字记忆排程。

**Architecture:** 扩展 PracticeRepository 和 PracticePage；以独立 WrongQuestions 表维护当前错题，事务判分。共享列表查询显示错题和收藏，保留旧入口。

**Tech Stack:** Flutter, Riverpod, Drift, SQLite。直接在现有功能工作树执行，不使用子代理。

## Tasks

- [x] 在 `test/features/practice/choice_practice_test.dart` 添加实际数据库测试：错题增删、收藏不变、顺序/随机范围、选择题排程拒绝、旧库迁移。运行并确认缺失行为。
- [x] 新建 `lib/core/database/tables/wrong_questions.dart`，主键 cardId，级联删除，wrongCount、lastWrongAtUtc；AppDatabase schema 2，从 1 创建该表；运行 build_runner 生成 Drift 代码。
- [x] 扩展 `lib/features/practice/data/practice_repository.dart`：PracticeOrder，choicesOnly/wrongOnly 筛选，事务 submitChoice 校验并保存错题，不更新调度或 review_logs。
- [x] 在 `lib/features/study/data/study_repository.dart` 的候选和当日额度查询排除 note_type 2、3；rateCard 防御拒绝选择题。
- [x] 更新 `lib/features/backup/domain/backup_manifest.dart` 和 `data/backup_archive.dart`，显式标记 schema 2，校验支持 schema 1/2 并核对 manifest 和数据库；添加迁移和备份回归测试。ImportRecovery 同步支持 schema 2。
- [x] 在 `ChoiceCardFace` 增加异步提交回调，禁用重复提交，失败保留选择可重试；`PracticeCardFace` 转发结果，`PracticePage` 增加顺序、选择题筛选、收藏、跳过、判分计数和保存提示。
- [x] `FavoriteRepository.watchPage` 支持 wrongOnly 并读取错题次数；`FavoritesPage` 复用为错题列表，收藏增加选择题专项入口；router、牌组及我的页增加入口。
- [x] 运行针对性 repository/widget/backup 测试与 analyze；更新指南及版本为 1.2.0+3；构建 ARM64 APK 并检查签名。保持 PDF 文档未跟踪，不推送 GitHub。
