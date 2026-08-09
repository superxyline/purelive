# 纯粹直播（自定义版） Pure Live Custom

基于 [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live) 二次开发、按个人使用需求裁剪的第三方多平台直播聚合播放器，使用 Flutter 构建。

> 本版本使用独立包名 `com.superxyline.purelive`，可与原作者版本**共存安装**，互不影响。

## 当前版本

- 版本号：**0.1.4.2**（构建号 7）
- 应用名：纯粹直播（自定义版）
- 签名：独立新签名密钥（仅保存在本机构建机，不入仓库）
- 支持平台：Android（含 Android TV）

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
| 版本 | 跟随上游 | 独立版本线（当前 0.1.4.2） |
| 签名密钥 | 仓库内置 | 独立新密钥，仅本机保存 |
| 更新功能 | 有 | 无 |
| IPTV/M3U | 有 | 无 |
| 网易 CC / 快手 | 有 | 无 |
| 直播录制 | 有 | 无 |
| Firebase 登录 | 有 | 无（各平台 Cookie 登录保留） |

## 最近更新（0.1.4.2）

- **修复全屏方向**：手机进入全屏自动横屏、退出全屏恢复竖屏，且启动时即按设备类型锁定正确方向；平板（最短边 ≥600dp）全程以横屏平板模式运行

## 最近更新（0.1.4.1）

- **移除桌面端支持**：删除 Windows / macOS / Linux 平台代码与依赖，项目专注移动端（Android / Android TV）
## 最近更新（0.1.4）

- **修复**：退出直播间后仍残留后台音频的问题（非仅音频/后台播放模式下退出即停止播放）
- **GetX 改用 pub 包**：移除内置 GetX fork（lib/get），使用官方 get 依赖，便于跟随上游更新
- **抖音签名 JS 抽离**：douyin_sign.dart 由 642KB 拆分为独立 JS 文件，提升可维护性
- **JS 运行时复用**：抖音/斗鱼签名不再每次创建 4MB 运行时实例
- **依赖升级**：connectivity_plus 7 / permission_handler 13 / pro_mpack 3 / syncfusion 34 等
## 安全加固

- **签名密钥**：仓库与 APK 内不再包含任何密钥材料，使用独立新密钥签名
- **本地数据加密**：设置数据（含 Cookie、WebDAV 密码）使用 AES 加密存储，加密密钥保存在系统安全存储
- **备份脱敏**：备份/导出不再包含 Cookie 与 WebDAV 密码，恢复时也不覆盖当前账号信息
- **网络传输**：默认禁止明文 HTTP，仅允许 HTTPS
- **日志安全**：日志调试服务仅绑定本机回环地址，内存日志有上限
- **系统备份**：llowBackup 已关闭，防止备份被提取
- **精简**：移除无引用资源（CC/快手表情等）与 7 个冗余权限，保持最小权限

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
- 内置/依赖的第三方开源组件声明见 **[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)**。
- **不提供任何 VIP 解锁、视频破解或盗链服务**，高清直播需在对应平台拥有合法账号权限。
- 所有直播内容（视频、音频、图片等）**版权归属原平台所有**，本软件仅作技术聚合与转码展示。
- 用户 Cookie 仅用于本地请求身份认证（如 B站高清直播），**不会上传或存储到任何服务器**。
- 应用无广告、无追踪、无后台服务。若杀毒软件误报，请自行判断或拒绝使用。

## 实现说明

本自定义版（0.1.4.2）的功能裁剪、安全加固、代码优化与版本迭代，均由 **Codex（AI 编程助手）与 DeepSeek（AI 模型）** 协作完成，包括但不限于：

- 功能裁剪：更新、IPTV/M3U、网易 CC、快手、直播录制、Firebase 登录
- 安全加固：签名密钥轮换、本地数据加密、权限精简、明文 HTTP 收紧、日志安全
- 代码结构优化：GetX 去 vendored、抖音签名 JS 抽离、JS 运行时复用
- 依赖升级、体积优化与问题修复
## 致谢

- 原作者：[liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)
- 参考项目：[dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)

本项目仅作个人学习与技术交流用途，请勿用于商业用途。
