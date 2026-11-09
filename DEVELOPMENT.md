# 开发说明

- `app/src/main/java/com/green/note` 包含页面、网络、存储和 Android 服务。JVM 回归测试位于 `app/src/test`。
- 通过 `ANDROID_HOME` 或本地 `local.properties` 指向 Android SDK。测试在宿主 JVM 运行。
- 构建原签名 APK 需要已有的发行密钥。将 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword` 配置到本地 `key.properties`，相对密钥路径以仓库根目录为准。缺少此文件时，Gradle 生成未签名的发行包。
- 酷安实网请求依赖本地 `app/src/main/assets/coolapk_auth_blob.b64`。提交源码时排除该文件、密钥、账号数据及本地产物。
- Android 应用 ID 为 `com.green.note`。从旧版升级时，首次导入读取兼容的 Flutter 偏好和账号记录，原记录保留。切换同签名同版本的回退包时使用覆盖安装，以保留应用数据。
- 验证发行包时检查应用 ID、版本、原签名、ARM64 ABI 和 ZIP、ELF 的 16 KiB 对齐。设备上的启动、账号迁移和交互需要单独验收。
