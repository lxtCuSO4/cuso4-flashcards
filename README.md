# Lunar Memory

本地使用的 Android 闪卡应用，原名 CuSO₄闪卡。支持 Android 8.0 及以上，无需服务器或账户。

支持基础卡、填空卡、单选题、多选题、文字与图片 `.apkg` 导入、FSRS 学习、随机练习、收藏、学习日历、跨牌组搜索、批量管理、本地提醒、存储管理及备份恢复。导入异常中断后，下次启动会安全清理暂存并提示重新选择牌组包。

选择题支持 2–8 个选项、图片、解析及可选乱序；多选按答案集合完全一致判定，正式学习仍由用户评分进入 FSRS。`.apkg` 中题干、连续 A–H 选项和明确答案齐全时自动识别单选／多选，无法确定时保留基础卡；不执行模板脚本。已有基础卡可在牌组内扫描并确认转换，保留原学习进度。新备份写格式 2，新版可恢复格式 1；旧版不能恢复格式 2。

「我的 → 问题反馈」可离线填写表单，再交给手机邮件应用向 lixingtong035@163.com 发送。用户需在邮件应用确认并联网投递；没有客户端可复制内容。应用自身不联网，不自动附加用户数据。

使用 Flutter、Drift／SQLite。内部应用标识和备份格式保留，以支持覆盖升级和旧数据。

- 开发状态与验证记录：`docs/development-progress.md`
- 朋友上手指南：`docs/user-guide.md`
- 选择题、问题反馈与本版安装验收：`docs/choice-feedback.md`
- 选择题导入、原地转换及仓库入口：`docs/choice-import.md`
- 首页 logo、新图标与安装验收：`docs/home-logo.md`
- 导入恢复、图标与本轮手机验收：`docs/import-recovery.md`
- 本地工具说明：`docs/local-tools.md`
- 重建桌面图标：`python tool/generate_launcher_icons.py`（需要 Pillow）
- 离线 ARM64 构建：`./tool/build_android_local.ps1 -BuildMode Release -TargetPlatform android-arm64 -Offline`

当前安装包仍使用开发测试签名；正式公开发布签名和多机型兼容验收待完成。
