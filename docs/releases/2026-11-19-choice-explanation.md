# Lunar Memory 1.1.2 解析页试用版

选择题提交后自动打开独立解析页，底部固定「返回题目」和「下一题」，长解析不再阻挡切题。题目页保留原下一张按钮，并提供查看解析入口。

返回题目保留已选选项、选项字母顺序和判分，重复查看不会重新记录错题。提前查看解析按未作答处理；单选／多选判分、错题答对自动移出和收藏规则不变。

版本 `1.1.2+5`；沿用包名、签名和 Android 8.0 以上 ARM64 范围。数据库维持版本 2，可覆盖现有版本，无需重新导入牌组。

本轮仅本地交付，未自动上传 GitHub。实际手机显示和覆盖安装待验收。

## 验证和产物

- 主回归 45 项通过：自由练习、错题和收藏、选择题组件、背卡和学习编辑；底部返回按钮及版本相关检查 19 项通过；慢速保存修复后的最终解析流程／组件 8 项通过（各批次有重复覆盖）。
- 最终 Dart analyze：No issues found；Git diff --check 通过。
- 单次离线 ARM64 Release 构建成功，用时 2 分 18 秒，无新依赖。
- APK：`build/releases/lunar-memory-1.1.2-arm64.apk`，22,982,197 字节，约 23.0 MB。
- APK SHA256：`CD64F9E031506CC96708FCE656162345BEC7235DAB13A99CBCD19BA0C3D1BFCC`。
- 包名 `com.cuso4.flashcards`，versionName `1.1.2`，versionCode `5`，minSdk 26，targetSdk 36，仅 `arm64-v8a`。
- 签名验证通过，证书 SHA256 `7729944fb7a11b56489b12f9d8b7ba71e9fe53ef873200445a92892b01a4ea2a`，与旧版一致。
- APK 内已核对包含新增 ChoiceExplanationPage 和解析页路由标记，排除复用旧编译产物；旧 1.1.1 APK 哈希保持不变。
- 指南：`build/releases/Lunar-Memory-1.1.2-User-Guide.md`，17,126 字节；SHA256 `2144E8DAA291F16861F92A5E6D70544214EFB48A263D754E15F1A45E733DBF2D`。
- 按 1220×2712、375dp 小屏、1.8 倍文字、深色和横屏检查固定操作区；返回题目、系统返回、重复查看、最后一题及连续调用下一题均有交互回归。
