# 纯粹直播（自定义版） Pure Live Custom

基于 [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live) 二次开发、按个人使用需求裁剪的第三方多平台直播聚合播放器，使用 Flutter 构建。

> 本版本使用独立包名 `com.superxyline.purelive`，可与原作者版本**共存安装**，互不影响。

## 当前版本

- 版本号：**0.1.2**（构建号 3）
- 应用名：纯粹直播（自定义版）
- 签名：独立新签名密钥（仅保存在本机构建机，不入仓库）
- 支持平台：Android（含 Android TV）、Windows、macOS

## 支持平台

- B站（Bilibili）
- 斗鱼（Douyu）
- 虎牙（Huya）
- 抖音（Douyin）

## 功能列表

### 保留功能

- 多平台直播聚合播放，支持分区浏览、热门推荐、搜索
- 多播放器内核切换：**MPV / IJK / EXO**
- 弹幕：显示、过滤、屏蔽词、显示优化
- 仅音频播放模式（后台听直播）
- 收藏 / 历史记录 / 自定义标签
- 本地备份与恢复、WebDAV 同步、电视端数据扫码同步
- 工具箱：直播链接识别与解析
- 定时关闭、深色模式、自定义主题、播放器手势等

### 已移除的功能（相对原版）

- 应用内更新（检查更新 / 下载安装）
- IPTV / M3U / EPG 直播源导入
- 网易 CC、快手直播平台
- 直播录制功能
- Firebase 登录与云配置同步

## 与原版的区别

| 项目 | 原版 | 本自定义版 |
| --- | --- | --- |
| 包名 | `com.mystyle.purelive` | `com.superxyline.purelive` |
| 应用名 | 纯粹直播 | 纯粹直播（自定义版） |
| 版本 | 跟随上游 | 独立版本线（当前 0.1.2） |
| 签名密钥 | 仓库内置 | 独立新密钥，仅本机保存 |
| 更新功能 | 有 | 无 |
| IPTV/M3U | 有 | 无 |
| 网易 CC / 快手 | 有 | 无 |
| 直播录制 | 有 | 无 |
| Firebase 登录 | 有 | 无（各平台 Cookie 登录保留） |

## 安全加固

- **签名密钥**：仓库与 APK 内不再包含任何密钥材料，使用独立新密钥签名
- **本地数据加密**：设置数据（含 Cookie、WebDAV 密码）使用 AES 加密存储，加密密钥保存在系统安全存储
- **备份脱敏**：备份/导出不再包含 Cookie 与 WebDAV 密码，恢复时也不覆盖当前账号信息
- **网络传输**：默认禁止明文 HTTP，仅允许 HTTPS
- **日志安全**：日志调试服务仅绑定本机回环地址，内存日志有上限
- **系统备份**：`allowBackup` 已关闭，防止备份被提取

## 构建说明

环境要求：

- Flutter 3.44+（Dart 3.12+）
- JDK 17
- Android SDK（compileSdk 37 + build-tools）+ NDK

构建 release APK（按架构拆分）：

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

产物位于 `build/app/outputs/flutter-apk/`：

- `app-arm64-v8a-release.apk`（主流手机 / 电视盒）
- `app-armeabi-v7a-release.apk`
- `app-x86_64-release.apk`

签名说明：

- 签名密钥保存在本机 `android/key.jks`，密码配置在 `android/key.properties`（两者均已 gitignore，不会入库）
- 新机器构建前需自行生成密钥：`keytool -genkeypair -v -keystore android/key.jks -alias key -keyalg RSA -keysize 2048 -validity 36500`

> 国内网络提示：项目已配置阿里云 Maven 镜像与 Gradle 国内镜像，GitHub 依赖可自行配置 ghfast 等加速通道。

## 声明与合规

- 本项目为**非营利性开源软件**，遵循仓库内 [LICENSE](LICENSE)（AGPL-3.0）。
- **不提供任何 VIP 解锁、视频破解或盗链服务**，高清直播需在对应平台拥有合法账号权限。
- 所有直播内容（视频、音频、图片等）**版权归属原平台所有**，本软件仅作技术聚合与转码展示。
- 用户 Cookie 仅用于本地请求身份认证（如 B站高清直播），**不会上传或存储到任何服务器**。
- 应用无广告、无追踪、无后台服务。若杀毒软件误报，请自行判断或拒绝使用。

## 致谢

- 原作者：[liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)
- 参考项目：[dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)

本项目仅作个人学习与技术交流用途，请勿用于商业用途。
