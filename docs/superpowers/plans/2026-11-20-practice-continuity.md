# Lunar Memory 练习连续性实施计划

> **For agentic workers:** 使用 executing-plans 在当前 worktree 顺序实施。按用户预算要求不启用子代理。

**Goal:** 第一批交付：练习自动续练、移除练习数量限制、编辑返回保留有效作答状态、评分栏对比修复。

**Architecture:** 复用 SQLite 的 AppSettings，按牌组、章节范围、类型、收藏／错题及顺序分别保存队列与小型进度记录。题序只在新一轮写入，答题状态在操作发生时保存；判分与进度在同一事务完成。沿用数据库版本及备份格式。

**Tech Stack:** Flutter、Riverpod、Drift、SQLite；不增加依赖。

## 边界

- 工作目录：D:/LunarMemory/.worktrees/cuso4-app，分支 codex/foundation
- 保留已有的两份未跟踪文档
- 第一批不接入外观预览，不实现第二批统计、答题卡及后续草稿／回收站
- 正式记忆排程、错题答对自动移出和收藏语义保持

## 顺序

- [x] 先添加并执行 test/features/practice/practice_resume_test.dart，确认数量配置回归用例失败
- [x] 增加 lib/features/practice/domain/practice_session.dart 与 data/practice_session_repository.dart：会话范围键、队列／游标持久化、重复提交保护、内容变更失效与固定随机队列
- [x] 修改 practice_repository.dart：默认全范围取题，移除 500 上限；保留范围、收藏和错题筛选
- [x] 修改 choice_card_face.dart、practice_card_face.dart、choice_practice_scaffold.dart：恢复选项排列与作答草稿，保存成功后再继续提交／查看解析
- [x] 修改 practice_page.dart：去数量、读取继续入口、持久化下一题和解析状态、完成后显式新一轮、删除题目自动跳过、编辑后核对题目版本
- [x] 修改 review_rating_bar.dart：按实际按钮底色分别配置前景，保持四档平级
- [x] 更新现有测试中被移除的数量配置与“任何设置均不可写入”的旧预期，保留正式学习数据不变的检查
- [x] 相关 87 项回归及静态分析通过；离线构建 ARM64 APK 并校验包名、版本与原签名，见 docs/releases/2026-11-20-practice-continuity.md

## 验收命令

使用 D:/dev/flutter/bin/flutter.bat，PUB_CACHE 指向工程 build/pub-cache。

```powershell
flutter test --no-pub test/features/practice test/features/favorites test/features/settings/font_settings_page_test.dart test/features/backup
flutter analyze --no-pub
```

必要验收：退出或重新打开数据库后恢复；顺序与随机、牌组与收藏错题各自独立；选项顺序不漂移；已提交题不重复写错题；超过 500 张不截断；仅改标签不丢作答；改题干后重置当前题；旧备份与新进度备份可恢复。
