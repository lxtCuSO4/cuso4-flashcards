# Lunar Memory 1.1.4 紧凑选择题试用版

选择题改为一屏优先自适应布局，顶栏集中元信息，选项更紧凑，底部操作固定。适用于常规、错题、收藏专项练习，也适用于直接打开收藏和错题列表的选择题预览。

正文可临时缩小至可读下限，不修改已保存字号。超长内容允许滚动并完整保留；图片支持点击放大。判分、错题和收藏语义保持，预览不写入错题或学习记录。

版本 `1.1.4+7`，沿用原包名、签名和 Android 8.0 以上 ARM64 范围；数据库不升级，无需重新导入牌组。本轮本地交付，实际手机显示与覆盖安装待验收。

## 验证与产物

- 相关回归分批通过：常规四选项无需滚动、真实布局缩字、超长内容完整滚动、触摸高度、旋转、图片放大／返回、收藏和错题直接预览、原判分和解析回调、字号、备份、背卡及编辑。
- 主回归其余 68 项通过；字号用例等待临时保存提示消失后，最终自适应／字号 8 项通过；宿主真实字体布局 6 项及最终预览捕获 1 项通过（批次有重复覆盖）。
- 最终 Dart analyze：No issues found；Git diff --check 通过。
- 单次离线 ARM64 Release 构建成功，用时 2 分 27 秒，无新依赖。
- APK：`build/releases/lunar-memory-1.1.4-arm64.apk`，23,178,865 字节，约 23.2 MB。
- APK SHA256：`D0B10F3D0015EC8F57D2A9ADC32D0935B50B764930FE3D411AFF9A183C726B38`。
- 包名 `com.cuso4.flashcards`，versionName `1.1.4`，versionCode `7`，minSdk 26，targetSdk 36，仅 `arm64-v8a`。
- 签名验证通过，与旧版证书 SHA256 `7729944fb7a11b56489b12f9d8b7ba71e9fe53ef873200445a92892b01a4ea2a` 一致；已核对 APK 内编译了 AdaptiveChoiceViewport 与 ChoicePracticeScaffold。
- 指南：`build/releases/Lunar-Memory-1.1.4-User-Guide.md`，18,921 字节；SHA256 `9720B7BFC84A4E635F8C736D95A8D683EFF9FFFAA5180E1A66E691F54D16C625`。
- 布局预览：`build/previews/adaptive-choice-phone.png`，1220×2712，使用宿主字体辅助查看，未向 APK 添加字体资源。
- 活跃配置、工具脚本和代码中未发现旧工程绝对路径，实际读写和构建均在 `D:/LunarMemory/.worktrees/cuso4-app`；旧版 1.1.3 APK 哈希保持不变。
