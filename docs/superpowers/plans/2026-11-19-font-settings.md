# 应用内字号调节实施计划

用户接受上一轮提出的「我的 → 字体大小」、实时预览、本地保存、界面和卡片阅读分别设置方案。

**Goal:** 在本应用内分别调节界面字号与卡片阅读字号，保持默认系统字号行为。

**Architecture:** FontSettings 以单条 JSON 设置原子保存至既有 app_settings；应用 builder 调整界面 TextScaler，CardContent 以原始系统 TextScaler 独立应用阅读倍率。保留系统非线性缩放，避免两类倍率叠加。设置页草稿实时预览，保存后全局生效，无数据库迁移或新依赖。

**Tech Stack:** Flutter、Riverpod、Drift；现有工作树直接实施，不使用代理。

- [x] 添加回归：入口、独立预览、保存／重进、系统缩放、解析页、恢复默认与大字号布局；先验证新入口缺失。
- [x] 新增 FontSettings、FontSettingsRepository，统一解析并验证范围；缺失／异常设置回退 100%。界面 80–150%，阅读 80–200%，步长 5%。单行 JSON 原子保存，随完整备份恢复。
- [x] 新增 FontScaleScope，保留系统 TextScaler，再分别生成界面与阅读倍率；接入 Cuso4App 和 CardContent，覆盖学习、选项、解析、背卡和预览里的正文。
- [x] 新增 FontSettingsPage 和路由，提供两个滑块、实时预览、保存及恢复默认草稿；保存失败保留草稿可重试。沿用东方题签、主题及反馈。
- [x] 运行相关交互／数据回归与静态检查，更新指南，版本递增至 1.1.3+6，离线构建 ARM64 APK 并校验版本、签名和新功能编译结果。本轮本地交付。
