# 章节折叠与基础收藏列表实施计划

> 执行方式：本会话内使用 executing-plans；按用户预算要求不启用代理或重复审查。

**Goal:** 默认折叠并记住多级章节，提供不改变学习排程的基础收藏列表。

**Architecture:** 牌组页以 app_settings 的每牌组独立键保存展开状态，既有数据流驱动显示。收藏查询使用 Drift 关联及有界分页；预览复用 CardContent 和只读 getStudyCard。

**Tech Stack:** 既有 Flutter、Riverpod、Drift、go_router，无新依赖或 schema 迁移。

## Task 1：章节折叠

- [ ] 新增 test/features/decks/presentation/deck_list_page_test.dart：默认收起、三级展开、父级收起再打开、组件重建后恢复、独立键、防重复点击、点击名称仍跳转、目标手机大字和横屏。
- [ ] 运行测试复现当前无折叠按钮/默认显示子级。
- [ ] 修改 lib/features/decks/presentation/deck_list_page.dart：每牌组键 deckExpanded.<id>，默认 false；仅展示已展开祖先的后代；写入中锁定对应按钮并显示错误；箭头使用原生 IconButton、48dp 和 expanded 语义。
- [ ] 运行 `flutter test --no-pub test/features/decks/presentation/deck_list_page_test.dart test/app/cuso4_app_test.dart`。

## Task 2：基础收藏列表

- [ ] 新增收藏查询回归：稳定分页、Basic/Cloze、移除不改 FSRS、删除级联。
- [ ] 新增 lib/features/favorites/data/favorite_repository.dart：JOIN favorites/cards/notes/decks，ORDER BY created_at_utc DESC/card_id DESC，LIMIT limit+1/OFFSET；最多 30 条展示，额外一条判断下一页。
- [ ] 新增 lib/features/favorites/presentation/favorites_page.dart、favorite_preview_page.dart：列表、分页、取消/撤销、带答案门控的安全预览；直接调用既有 setFavorite 和 getStudyCard，不调用 loadQueue/rateCard。
- [ ] 修改 lib/app/router/app_router.dart 和 lib/features/records/presentation/records_page.dart，新增 /favorites 及 /favorites/:cardId，记录页提供收藏入口。
- [ ] 新增 UI 回归验证入口、答案门控、取消/撤销、无日志/排程改动与小屏大字。

## Task 3：集中验证与交付

- [ ] 相关范围：`flutter test --no-pub test/features/decks test/features/favorites test/features/study test/app test/core/content`，不重复全套音频或导入验收。
- [ ] `flutter analyze --no-pub` 和 `git diff --check`，直接检查本轮差异。
- [ ] `tool/build_android_local.ps1 -BuildMode Release -TargetPlatform android-arm64 -Offline`；检查 aapt2、apksigner、SHA-256 和 APK 内新应用库。
- [ ] 更新 docs/development-progress.md，记录用户已确认导入/来源/显示答案/四项评分/撤销真机通过；本轮新增功能仍标注待手机验收。仅提交本轮工程文件，保留工作树。
