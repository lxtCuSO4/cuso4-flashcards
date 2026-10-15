# Fixed Touhou Labels Implementation Plan

> 在当前会话使用 executing-plans 顺序执行，不派发代理。用户明确要求东方主题始终保留，此修订取代上一版的装饰开关设计，无需再次选择方案。

**Goal:** 东方题签为固定视觉元素，用户无法在应用内关闭或修改；升级及恢复旧设置也不能隐藏题签。

**Architecture:** `TouhouTag` 改为普通 StatelessWidget，直接渲染，不依赖设置流。移除装饰开关组件及设置入口。遗留 `touhouDecorations` 行可以保留在数据库／备份中，但新代码完全忽略它，避免无必要的数据迁移。外观明暗和触觉设置继续提供。

**Tech Stack:** 现有 Flutter 页面及 SQLite，无新依赖或 schema 变化。

- [x] 更新 `test/features/settings/touhou_decorations_test.dart`，用真实数据库预置旧版 `touhouDecorations=false`，检查各页题签、重启、大字体深色和设置中无开关；运行确认旧实现失败。
- [x] 修改 `lib/core/widgets/touhou_tag.dart`，移除 Riverpod／settingsProvider 和隐藏分支，改为 `Widget build(BuildContext context)`；删除 `lib/features/settings/presentation/touhou_decoration_switch.dart`，移除 `settings_page.dart` 中相应 import 和实例。
- [x] 运行该回归和受影响 app／home／study／backup 页面测试、静态分析；不重复无关导入与数据层测试。
- [x] 一次 ARM64 离线构建，保留旧包，冻结 `build/releases/lunar-memory-fixed-touhou-arm64.apk`；核对原签名、包名、架构及 libapp.so 哈希。
- [x] 更新当前验收说明／开发进度，标注旧开关方案已被替代；本地提交并保留分支，不上传 GitHub。

验证结果：16 项通过，静态分析无问题，离线构建成功。原 Android Debug 证书未变；新包 22,561,086 字节，SHA256 `73EBEC3DBB0FB0212AC4779962E5E3E491CECE1A9D0CD3665985A905537F44EB`。真实手机观感与覆盖安装仍待验收。
