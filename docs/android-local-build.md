# Windows 本地 Android 构建

在活跃工程 D:\anki\.worktrees\cuso4-app 内执行：

    powershell -ExecutionPolicy Bypass -File .\tool\build_android_local.ps1

首次构建需联网补齐 Gradle 插件及 Android/Flutter 构建依赖。依赖齐全后可使用：

    powershell -ExecutionPolicy Bypass -File .\tool\build_android_local.ps1 -Offline

## 工程内隔离

- 直接运行已经安装的 Gradle 9.3.1，不调用可能自行下载分发的包装器。
- 新 Gradle 缓存位于 build\gradle-home；Flutter 构建插件副本位于 build\flutter-gradle-plugin。
- Android SDK/JDK/Flutter SDK 仍从现有 D 盘安装读取。禁用 Android SDK 自动下载；若缺少平台/工具版本，构建应报错，不自动修改 SDK。
- JAVA_HOME、GRADLE_USER_HOME 仅在脚本运行的进程内设置，结束后恢复。不修改全局镜像、PATH、Git 配置或系统环境。
- 保留 build 与 android\.gradle，不执行 flutter clean。不需要重新安装 Flutter 或 Android Studio。
- 默认依赖仓库使用工程已有的官方仓库，不关闭 TLS 验证。
- 构建命令关闭 Kotlin 增量编译并在 Gradle 进程内编译，绕过 C 盘 pub 源码与 D 盘工程之间的增量缓存相对路径错误；不迁移或清理全局 pub 缓存。

脚本参数 FlutterRoot、JavaRoot、GradleExecutable 可替换安装位置。默认 GradleExecutable 是当前已验证存在的分发路径；若路径改变，先确认文件存在再传入参数。

## 安装包与范围

输出目录为 build\app\outputs\flutter-apk；输出是调试签名 APK，不是正式公开发布包。正式发布签名、版本/机型兼容测试与备份恢复仍需后续完成。

构建成功仅说明 Dart/Kotlin 和打包流程通过，不等于真机验证。当前优先验收文字、图片、基础卡/填空卡、FSRS 评分和误触保护；现有音频代码保留，但不追加音频专项验收。

2026-10-15：在线构建和离线重建均通过，APK 为 178456534 字节，minSdk 26，三架构调试版。包名/签名校验通过，打包的 Dart kernel 与本次编译输出一致。详细核验记录见 development-progress.md。

停止构建后保留缓存，再运行相同命令可复用已完整下载的依赖。未下载完的单个依赖可能重新下载，不能保证每个文件都支持字节级断点续传。
