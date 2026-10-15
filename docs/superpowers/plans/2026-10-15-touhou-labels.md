# Lightweight Touhou Labels Implementation Plan

> 历史实施记录：用户随后要求固定保留东方主题，以下装饰开关设计已由 `2026-10-15-fixed-touhou-labels.md` 替代。当前行为与验收见 `docs/touhou-labels.md`。

> **For agentic workers:** 使用 superpowers:executing-plans 在当前会话顺序执行。用户已认可预览，预算约束优先，不派发代理、不重复确认。

**Goal:** 将获认可的东方轻量题签加入现有页面，提供可持久关闭的开关，交付可覆盖安装的 APK。

**Architecture:** 一个 ConsumerWidget 统一题签、装饰设置和可见性；PageFrame 增加通用 header 插槽，特殊页面在正文顶部接入。独立设置开关处理异步写入与错误；全部沿用现有 SQLite 设置表。

**Tech Stack:** Flutter、Riverpod、Drift／SQLite；无新依赖、schema 或资源文件。

## Task 1：必要交互检查与复用组件

- [x] 新增 `test/features/settings/touhou_decorations_test.dart`：使用实际 AppDatabase 与 Cuso4App，检查默认题签映射；关闭后重建 ProviderContainer 验证持久化，重新开启后生效；SQL 触发器模拟写入失败，原值和页面功能保持。先运行观察功能缺失。
- [x] `lib/app/theme/app_colors.dart` 集中新增明暗题签前景／背景。新建 `lib/core/widgets/touhou_tag.dart`，枚举定义题签文案与图标，观察 settingsProvider：`settings != null && settings['touhouDecorations'] != 'false'` 才显示。无设置行默认开启；包裹 ExcludeSemantics，容许大字体换行；隐藏时返回 SizedBox.shrink，内含边距同时消失。
- [x] `lib/core/widgets/page_frame.dart` 新增 `Widget? header` 并在正文 subtitle 前渲染。`lib/features/settings/presentation/touhou_decoration_switch.dart` 写入 `saveSetting(ref, 'touhouDecorations', '$enabled')`，使用 saving 状态禁止重复操作，catch 后调用 showActionError，finally 恢复开关。

## Task 2：页面接入

- [x] 在 home／decks（列表及详情）／records／settings／favorites／practice 的 PageFrame.header 接入题签。收藏练习选择收藏题签。设置页在外观之后插入新开关。
- [x] study／backup 的自定义正文顶部插入题签，沿用正文滚动、深色与现有布局；不改变卡面、评分或确认弹窗。
- [x] 运行新交互检查和受影响页面回归，保持语义导航、原按钮文案、开关失败提示及现有学习行为。

## Task 3：验证与交付

- [x] 集中运行新测试及 app／home／practice／favorites／records／study／backup 界面回归，`flutter analyze --no-pub`。使用现有布局测试检查手机、深色和大字体；不运行无关导入解析全套。
- [x] 一次 `./tool/build_android_local.ps1 -BuildMode Release -TargetPlatform android-arm64 -Offline`；冻结 `build/releases/lunar-memory-touhou-labels-arm64.apk`，不覆盖旧包。
- [x] aapt2／apksigner 核对名称、Android 8+、ABI、原证书、包内 libapp.so 与本轮构建一致；核对上一版 APK 哈希不变。更新开发进度和手动验收说明，本地提交并保留分支。

验证记录：新交互检查 2 项通过；受影响页面 31 项通过；学习页在补齐卸载 widget 后等待订阅清理的测试代码后 3 项通过，共 36 项。静态分析无问题，离线构建成功。APK 为 22,561,086 字节，SHA256 `9BDF3B0859B3418EE06C1E5DDD90288E6E949503D8AD782635069FABDB7CFDD8`。真机视觉与安装仍待用户验收。
