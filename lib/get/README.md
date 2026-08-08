# lib/get：内置的 GetX 分叉说明

`lib/get/` 是 GetX 框架的完整源码副本（vendored fork），不是通过 pub 包引入的。

## 为什么这样做

仓库需要定制 GetX 的少量行为（测试模式路由参数、对话框/提示条样式等），
直接 fork 源码可以让这些改动随仓库提交、无需等待上游发布。

## 相对上游的改动

1. **新增 `get_navigation/src/routes/test_kit.dart`**：提供 `GetTestMode`
   （测试模式参数/路由参数），被 `extension_navigation.dart` 和 `get_root.dart` 使用。
2. **对话框与 SnackBar 文案样式**：原实现引用 App 的 `AppTextStyles`
   （`package:pure_live/common/style/app_text_styles.dart`），会让框架反向依赖 App 代码；
   已改为框架内静态 `TextStyle`（字号 14/16），保持 `lib/get` 自包含。
3. **导入路径**：框架内部相互引用统一改写为 `package:pure_live/get/...`。

## 升级/维护约定

- 升级时以 GetX 上游对应版本源码为基线，逐文件比对后应用上述补丁。
- 不要在此目录内重新引入 `package:pure_live/common/...` 等 App 依赖，
  否则框架与 App 再次耦合，无法独立升级。
- 可运行 `rg -n "package:pure_live/common" lib/get` 检查耦合是否回潮。
