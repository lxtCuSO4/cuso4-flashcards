# Lunar Memory 1.2.0 开发预览版

选择题独立练习；错题答对自动移出。

## 功能

- 单选、多选不再进入 FSRS／自定义自然日学习队列，既有历史记录保留。
- 牌组选择题、错题、收藏选择题分别支持顺序和随机练习。
- 提交错误答案自动记错，答对自动清除；预览、跳过和直接看答案不改变错题。
- 练习中可收藏和编辑；错题记录纳入本地完整备份，旧库及旧备份可升级。

## 验收

- 主回归：75 项通过，覆盖练习、选择题提交、收藏、备份、排程和数据库；兼容检查：23 项通过（含重复的备份检查），覆盖旧备份、导入中断恢复、学习编辑和背卡。
- Dart analyze：No issues found。Git diff --check：通过。
- 离线 ARM64 Release 构建成功，用时 1 分 35 秒；未新增或下载依赖。
- `build/releases/lunar-memory-1.2.0-arm64.apk`：22,982,201 字节，约 23.0 MB。
- APK SHA256：`C8915B707577B788A23AEEC4D7660A2B7316F775B311139935066F3B57D27E89`。
- 包名 `com.cuso4.flashcards`，versionName `1.2.0`，versionCode `3`，minSdk 26，targetSdk 36；仅 `arm64-v8a`。
- APK 签名校验通过，证书 SHA256 `7729944fb7a11b56489b12f9d8b7ba71e9fe53ef873200445a92892b01a4ea2a`，与原安装包一致。
- 指南副本 `build/releases/Lunar-Memory-1.2.0-User-Guide.md`：16,302 字节；SHA256 `834F2F9B9C89EC857ACCD5C5660293C3EF3BBAC8FF4E8C23713EA9AF585B0FF5`。
- 旧版 1.1.0 APK 保持原哈希 `1A04E4ADE52CEFD82EFE6CB8EAD5BC0310A0F6F282F900E0964EC6DE7BB0DF20`。
- 本轮未推送 GitHub，PDF 制卡未实施，两个原有未跟踪计划文档保持不动。

实际手机覆盖安装、触觉强度及显示观感仍需设备验收。
