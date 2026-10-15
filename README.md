# Lunar Memory

本地使用的 Android 闪卡应用，支持 Android 8.0 及以上，无需服务器或账户。

支持基础卡、填空卡、文字与图片 `.apkg` 导入、FSRS 学习、随机练习、收藏、学习日历、跨牌组搜索、批量管理、本地提醒、存储管理及备份恢复。导入异常中断后，下次启动会安全清理暂存并提示重新选择牌组包。

使用 Flutter、Drift／SQLite。内部应用标识和备份格式保留，以支持覆盖升级和旧数据。

- 开发状态与验证记录：`docs/development-progress.md`
- 朋友上手指南：`docs/user-guide.md`
- 首页 logo、新图标与安装验收：`docs/home-logo.md`
- 导入恢复、图标与本轮手机验收：`docs/import-recovery.md`
- 本地工具说明：`docs/local-tools.md`
- 重建桌面图标：`python tool/generate_launcher_icons.py`（需要 Pillow）
- 离线 ARM64 构建：`./tool/build_android_local.ps1 -BuildMode Release -TargetPlatform android-arm64 -Offline`

当前安装包仍使用开发测试签名；正式公开发布签名和多机型兼容验收待完成。
