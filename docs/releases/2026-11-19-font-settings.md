# Lunar Memory 1.1.3 字号设置试用版

「我的 → 字体大小」新增界面文字和卡片阅读字号，支持实时预览、保存、恢复默认。两项倍率独立，默认仍跟随手机系统字号；保存后覆盖题干、选项、答案和解析正文。

设置保存在本机，并随本地完整备份保存、恢复。保留 1.1.2 的独立解析页和底部返回／下一题，以及现有错题、收藏和记忆学习行为。

版本 `1.1.3+6`，数据库仍为版本 2；本轮为本地交付，实际手机覆盖安装与字号观感待验收。

## 验证与产物

- 45 项相关检查通过，覆盖字号设置、系统非线性缩放、保存重进、正文渲染、选择题解析、背卡、学习编辑和备份恢复；补查 1 项最大字号下的固定返回／完成按钮通过。
- 最终 Dart analyze：No issues found，Git diff --check 通过。没有新增字体资源、网络依赖或数据库迁移。
- 单次 ARM64 Release 离线构建成功，用时 1 分 23 秒。
- APK：`build/releases/lunar-memory-1.1.3-arm64.apk`，23,113,329 字节，约 23.1 MB。
- APK SHA256：`7ED1FD89A2078A8C2EBBADA5B162E8F646205EDC4841777674AAAB46CA3E6E9E`。
- 包名 `com.cuso4.flashcards`，versionName `1.1.3`，versionCode `6`，minSdk 26，targetSdk 36，仅 `arm64-v8a`。
- 签名验证通过，与原包一致，证书 SHA256 `7729944fb7a11b56489b12f9d8b7ba71e9fe53ef873200445a92892b01a4ea2a`。已核对编译包包含 FontSettingsPage 和 ChoiceExplanationPage。
- 指南：`build/releases/Lunar-Memory-1.1.3-User-Guide.md`，18,045 字节；SHA256 `FB16834489651583D9B49758DEFC43804B74F27E85CF45AEB2F35E7DB44B2708`。
- 旧版 1.1.2 APK 保持原哈希不变。
