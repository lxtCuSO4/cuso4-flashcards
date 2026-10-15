# Import Recovery and Launcher Icon Implementation Plan

> **For agentic workers:** 使用 superpowers:executing-plans 在当前会话顺序实施；用户预算约束优先，不派发代理，不重复设计审批。

**Goal:** 导入异常终止后安全收尾并提示重试，使用用户原图更新 Android 图标，并按补充要求改名 Lunar Memory，交付可覆盖安装的 APK。

**Architecture:** 后台 SQLite setup 中执行启动专用恢复，媒体提交前写持久日志，实际引用和已提交记录共同保护媒体，通用设置表存提示。首页与导入页复用提示组件；Pillow 生成原生启动图标，保留旧 APK。

**Tech Stack:** Flutter／Riverpod、Drift／sqlite3、dart:io／html、已有 Python／Pillow、Android 原生图标资源。

## Task 1：恢复与持久提示

- [x] `test/core/recovery/import_recovery_test.dart` 构造真实 schema 1 数据库、未完成任务和暂存文件。覆盖事务中断回滚、已提交数据／共享图片保护、无日志旧暂存、异常日志／未知文件保护、重复启动与确认后隐藏。
- [x] 提取 `lib/core/media/media_references.dart` 供既有 MediaRepository 和恢复共用，保留解析语义。
- [x] 新建 `lib/core/recovery/import_recovery.dart`：`ImportRecovery(Directory root).run(Database database)`。`BEGIN IMMEDIATE` 内收尾；仅固定 media/.imports 子目录及已知前缀；媒体日志 version 1／newFiles 哈希列表，删除前复查 media 表与笔记引用，失败保留并记录提示。
- [x] `lib/features/import/data/media_importer.dart` 在任何移动前以 journal.next → journal.json 写入候选哈希日志。`lib/core/database/database_connection.dart` 先恢复备份，再在后台连接 setup 运行导入恢复；允许传入 root 以验证实际连接入口。
- [x] 新建 `lib/features/import/domain/import_recovery_notice.dart`、`data/import_recovery_repository.dart`；观察 importRecoveryNotice 设置值，确认时匹配原始 value_json 后删除，防止旧提示确认覆盖新提示。

核心验证：`flutter test test/core/recovery/import_recovery_test.dart --no-pub`；真实磁盘重开后原牌组／卡片／排程保持，未提交内容消失，已提交媒体保留，提示可持久确认。

## Task 2：用户提示

- [x] 新建 `lib/features/import/presentation/import_recovery_notice.dart`，首页和导入页复用，显示中断数量／清理失败说明，提供前往导入或选择文件、知道了；失败保留提示并显示错误。
- [x] 修改 `lib/features/home/presentation/home_page.dart`、`import_page.dart` 接入组件；不自动打开选择器或启动新任务。
- [x] `test/features/import/presentation/import_recovery_notice_test.dart` 验证手机尺寸／深色大字体、进入导入与确认持久化、旧提示不能清除新提示；既有 import_page_test 使用空恢复状态隔离文件系统。

## Task 3：图标与交付

- [x] 将用户 JPG 复制到 `assets/branding/launcher-source.jpg`，新增 `tool/generate_launcher_icons.py`，写出 mdpi～xxxhdpi、adaptive foreground／background 和本地预览。保留白底与像素边缘，在安全区域放完整可见图像。
- [x] 接入 `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` 及 roundIcon，视觉检查圆形／圆角预览，不新增无意义样式测试。
- [x] 集中运行受影响恢复／导入／共享媒体／备份测试、静态分析；离线构建 ARM64 release，核对新图标资源、签名／版本／代码哈希和旧包不变，更新进度和说明。
- [x] 本地提交并检查工作树；保留当前分支，不上传 GitHub。

构建：`./tool/build_android_local.ps1 -BuildMode Release -TargetPlatform android-arm64 -Offline`。按新增名称要求，产物命名为 `build/releases/lunar-memory-arm64.apk`，不覆盖之前冻结 APK。

验证：集中 91 项测试通过（含用户 OS 牌组 520 笔记／670 新卡），静态分析无问题，离线 release 构建及 lint 通过。新 APK 22,560,462 字节，SHA256 `B477A2F6818EA5B261B1C3965F13902D45E63F46B95A214A7D458DB598189D73`；沿用原测试签名。真机强停恢复与桌面图标刷新仍待用户验收。
