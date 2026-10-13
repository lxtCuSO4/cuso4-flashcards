# CuSO₄闪卡开发进度

更新日期：2026-10-14（Asia/Shanghai）。

## 工作位置

- 活跃工作区：`D:\anki\.worktrees\cuso4-app`
- 开发分支：`codex/foundation`
- 原始工作区：`D:\anki`；其中已有的 `tool/` 脚本需保留。
- GitHub 上传暂缓，先完成应用。

## 当前阶段

- [x] Flutter Android 项目、依赖和离线构建缓存；已提交 `bf6cb74`。
- [x] 明暗主题：`500e2f8`；明暗前景和错误色、对比度。
- [x] 按键反馈：`9c4406a`；明显、轻柔、关闭，按压态、异步锁、减少动画。
- [x] 牌组、笔记、卡片模型与 Cloze 解析；`6699892`。
- [x] Drift 数据库版本 1、外键、索引与迁移快照；`6699892`。
- [x] 牌组和笔记事务仓储，编辑保留排程，移除 Cloze 编号需确认。
- [x] 响应式四页导航、牌组管理、卡片编辑器、主题和触觉强度设置。
- [ ] `.apkg` 卡片与媒体导入、FSRS 学习。
- [ ] 编辑器、统计日历、收藏、设置和本地通知。
- [ ] 备份恢复、设备兼容验证和正式签名 APK。

## 环境

- Flutter：`D:\dev\flutter`
- Android SDK：`D:\Android\Sdk`
- Android Studio / JDK：`D:\Android\Android Studio\jbr`
- Gradle 缓存：`D:\gradle-cache`
- Gradle 本地仓库镜像配置：`D:\gradle-cache\init.d\cuso4-mirrors.gradle`

不要执行 `flutter clean`；保留已验证的 Gradle 和 sqlite3 原生资产缓存。

## 验证记录

- 2026-10-13：基础项目测试、静态分析和 debug APK 构建通过；离线重建通过。
- 2026-10-14：`flutter test test/app test/widget_test.dart --no-pub`，2 项通过。
- 2026-10-14：完整 29 项测试通过，`flutter analyze --no-pub` 无问题。
- 2026-10-14：`gradlew --offline app:assembleDebug --no-daemon` 成功；APK 包含主题代码，主界面仍是品牌启动壳，并非完整应用。
- 2026-10-14：卡片模型和数据库关键测试 8 项通过；仓储关键测试 4 项通过。
- 2026-10-14：主界面接入后完整测试 41 项通过，静态分析无问题；导航测试覆盖 1220×2712 / DPR 3、1.8 倍字体和宽屏 NavigationRail。
- 最新界面包含今日、牌组、记录、我的。记录是明确的待接入页面，`.apkg` 入口显示开发阶段提示；FSRS、媒体导入和增强功能尚未完成。
- 2026-10-14：主界面离线 debug 构建成功；`build/app/outputs/flutter-apk/app-debug.apk` 已更新，188466739 字节。调试构建包含多架构及调试资源，不能用于估算正式发布体积。
- 数据管理和主界面已提交 `ad06aee`；下一阶段执行导入与 FSRS 计划。

## 预算控制（用户最新要求）

- 不再逐项实施双重代理审查，以直接实施和集中检查为主。
- 低风险样式、文案、静态布局不新增单元测试。
- 保留数据库事务、导入解析、FSRS、备份恢复和明显的交互风险测试。
- 没有新改动或新问题时不重复检查；阶段结束一次整体验证和构建。
- 此要求优先于原计划中的逐项 TDD 和审查流程。
- 最新范围约束：只修改 `D:\anki` 内工程相关文件；不修改系统设置、SDK、全局 Git 配置或其他工程。

## 继续方式

按 `docs/superpowers/plans/2026-10-13-cuso4-flashcards-plan-index.md` 的阶段顺序继续。
完成每项后记录真实测试结果、审查结果和提交；未完成的功能不要标记为可用。
