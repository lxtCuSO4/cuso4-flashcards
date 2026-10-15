# Choice Cards Implementation Plan

> 在当前会话顺序实施；依用户预算约束，不派发代理、不扩大静态测试。用户已选择单选与多选同时实现，PDF 计划暂停。

**Goal:** 可新建、编辑、学习和随机练习离线单选／多选题，沿用 FSRS 与既有管理能力。

**Architecture:** NoteType 追加值；ChoiceQuestion 负责扁平字段、验证和按稳定编号判分；ChoiceCardFace 共用作答界面，各页面控制答案显示和生命周期。沿用现有笔记、图片及学习事务。备份格式 2 阻止旧版误读，新版兼容格式 1。

**Tech Stack:** 现有 Flutter、Riverpod、SQLite／Drift，无新依赖。

- [x] 先写关键领域／仓储检查，确认缺失功能导致失败；增加 choice_question.dart、扩展 note.dart 和 note_repository.dart，保留卡片 ID、排程、媒体与旧类型。
- [x] 增加共用 choice_card_face.dart、choice_editor_fields.dart；接入 note_editor_page.dart、note_preview_page.dart，选项可增删、选正确答案、可选乱序、图片和解析。
- [x] 在 study_page.dart 和 practice_card_face.dart／practice_page.dart 接入；StudySessionController 提供展示代次，避免同 ID 撤销／重载保留答案。接入收藏预览、列表类型与搜索筛选。
- [x] 备份 manifest 读 1／2、写 2，校验选择题字段；做选择题／媒体／排程备份恢复及旧格式兼容检查。
- [x] 集中运行受影响领域、仓储、学习、练习、收藏、编辑、搜索、备份与布局检查，静态分析，一次离线 ARM64 构建，核对包及原签名。
- [x] 更新功能说明、朋友指南和开发进度，保留分支／旧包；不在本轮实现 PDF。实施检查点在本地 Git 保存，不自动推送新增功能。
