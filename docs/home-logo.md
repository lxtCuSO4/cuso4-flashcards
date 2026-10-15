# 首页 logo 与紧凑桌面图标

2026-10-15：在首页顶栏 Lunar Memory 左侧增加 36dp logo。logo 为装饰，不增加点击行为，不重复读屏标题；小屏和大字体下标题可收缩，保留完整语义。

原始 artwork 保持不变。现有脚本将人物画幅从 72dp 可视区内的 46dp 放大到 64dp，约放大 39%，同步生成五种 Android 密度、圆形／圆角预览和小尺寸 Flutter logo。普通圆形／圆角预览已查看；各手机桌面的遮罩和动效仍需真机确认。

## 安装与验收

直接覆盖安装 build/releases/lunar-memory-logo-arm64.apk，约 22.7 MB（22,729,830 字节），不用卸载或重新导入。先导出应用外备份更稳妥。

1. 检查首页左上角 logo 在 Lunar Memory 左侧，桌面人物更大。
2. 检查原有牌组、图片、进度、收藏、评分和撤销，以及固定东方题签。
3. 在明暗外观、系统大字体和横屏下检查首页；标题空间不足时可能省略，logo 和刷新按钮应保持可见。
4. 如果桌面仍显示旧图标，可先正常重启手机，不清除应用数据。

## 验证记录

已有 app/home 主题与布局回归 10 项通过，静态分析无问题。一次 ARM64 release 离线构建成功，release lint 通过。最终包内首页资产与生成源相同，三种 xxxhdpi launcher 图标逐像素一致，libapp.so 与本轮构建相同；原始图片、上一固定题签 APK 均未变。

- 包名 com.cuso4.flashcards，名称 Lunar Memory，版本 1.0.0／code 1，minSdk 26，targetSdk 36，仅 arm64-v8a。
- APK SHA256：38A1D01145CD2F20313CBF63ACFF2CE7F6DCD5079D966E84BB38C2DEC8A501E4。
- libapp.so SHA256：7FD5FEF6A73D8197299059B53C7B172E8BDDF4509571043280F0F36CD11EFB3F。
- 原测试签名 SHA256：7729944fb7a11b56489b12f9d8b7ba71e9fe53ef873200445a92892b01a4ea2a。

当前仍为开发试用签名；正式公开发布签名、多机型兼容及本轮手机显示验收没有完成。安装包无 INTERNET 权限；系统自动备份尚未在工程内显式关闭，由手机设置控制，此项需另行落实。

朋友上手指南见 user-guide.md，同内容纯文本可随 APK 发送：build/releases/Lunar Memory 使用指南.txt。
