# GreenNote

GreenNote 是面向 Android 的独立酷安客户端，使用 Flutter，应用包名为 `com.green.note`。当前版本为 **2.0.0**。

## 功能

- 首页频道、话题分类、搜索、动态详情、评论和图库。
- 用户主页、二维码名片、关注的话题、常去和浏览历史。
- 动态、图文、酷图、二手、清单、天梯榜与投票编辑界面。
- 应用内商店、本机应用管理、更新检查、下载管理和安装包管理。
- 酷品与好物榜、商品购买链接、私信通知、本地账户与 WebDAV 备份。

发布、关注等云端写操作需要有效的酷安登录状态；匿名账户的收藏和关注按本地规则保存。

## 构建 ARM64 APK

安装与 `pubspec.yaml` SDK 约束兼容的 Flutter，然后执行：

```sh
flutter pub get
flutter build apk --release --no-pub --target-platform android-arm64
```

输出位于 `build/app/outputs/flutter-apk/app-release.apk`，仅包含 `arm64-v8a`。本地签名和接口素材要求见 [构建说明](DEVELOPMENT.md)。

## 已知边界

酷安接口并非稳定的公开开发者 API，服务端可能限流、要求验证码或调整字段。应用管理读取本机安装信息以展示列表和检查更新；登录凭据使用 Android 安全存储。购物链接会优先尝试对应购物 App，无法唤起时回退网页，实际行为取决于平台链接与已安装客户端。

首页减速阶段的偶发顿挫仍未完成真机验收。静态检查、自动化测试与 APK 构建通过不代表所有设备、账号和购物链接均已验证。

GreenNote 是独立第三方客户端，与酷安无隶属关系。
