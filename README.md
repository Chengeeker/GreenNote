# GreenNote

GreenNote 是一个基于 Kotlin 和 Jetpack Compose 的第三方酷安 Android 客户端。它支持浏览动态、文章、数码话题和二手商品，也提供应用管理、应用内下载和 WebDAV 备份。

当前版本为 2.0.0，支持 Android 7.0 及以上，发行包使用 ARM64 架构。

## 构建

使用 JDK 21 和 Android SDK 36。在仓库根目录运行以下命令。

```powershell
.\gradlew.bat :app:testDebugUnitTest :app:assembleRelease
```

其他系统可使用 `./gradlew`。APK 位于 `app/build/outputs/apk/release/`。本地网络验证、原签名和备份兼容说明见 [开发说明](DEVELOPMENT.md)。
