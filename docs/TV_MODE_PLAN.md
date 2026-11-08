# pure_live TV 模式完整实施计划（M1-M4）

> 目标：**同一个 APK**，检测到电视设备时启动独立的 TV UI（外观与交互对齐原作者 pure_live_TV 项目），手机端行为零变化。
> 原则：**只抄设计不抄代码**（pure_live_TV 为 AGPL-3.0，自写组件规避许可传染）；数据层 100% 复用现有 GetX controllers 与站点层；只做现有功能（关注/热门/分类/搜索/播放/设置/弹幕/清晰度），不做 35 站/IPTV/VOD/多内核/手机遥控。
> 参考素材：`E:\codex\_purelive_tv_ref`（只读克隆，UI 分析结论已固化在本文件）。

---

## 0. 总体架构

```
main.dart
  └─ AppInitializer（现有，不动）
      └─ TvDeviceService.detect()  ← 新增：原生 MethodChannel 'pure_live/device_type'
          ├─ 手机（默认）→ runApp(MyApp())            ← 现有代码，零改动
          └─ TV          → runApp(TvApp())             ← 新增 TV 树
```

新增目录（全部在 `lib/tv/` 下，与现有 `lib/modules` 隔离）：

```
lib/tv/
  tv_app.dart                 # TvApp 根 Widget：强制横屏 + 深色 MaterialApp + 全局焦点层
  core/
    tv_device_service.dart     # 检测通道（isTv + 缓存）
    tv_theme.dart              # TV 主题（颜色/字号/圆角/动画常量，见 §2）
    tv_focus.dart              # 焦点系统核心（见 §3）
  widgets/                     # 自写 Tv* 组件（见 §4 清单）
    tv_scaffold.dart           #   侧栏+内容窗格壳
    tv_side_nav.dart           #   左侧导航栏（时钟/菜单/设置）
    tv_tab_bar.dart            #   平台 Tab 条（带刷新进度线）
    tv_room_card.dart          #   直播间卡片
    tv_focusable.dart          #   通用可聚焦件
    tv_panel.dart              #   右侧浮层面板容器
    tv_index_panel.dart        #   索引选择面板（M2）
    tv_page_shell.dart         #   子页壳（标题+返回，M3）
    tv_dialog.dart             #   TV 对话框（M3）
    tv_marquee_text.dart       #   聚焦跑马灯
    tv_status_chip.dart        #   封面角标（平台/人气/关注）
    tv_empty.dart / tv_loading.dart
  pages/
    tv_home_page.dart          # 壳装配（M1）
    tv_favorite_page.dart      # 关注（M1）
    tv_popular_page.dart       # 热门（M1）
    tv_areas_page.dart         # 分类（M3）
    tv_search_page.dart        # 搜索（M3）
    tv_play_page.dart          # 播放（M2）
    tv_settings_page.dart      # 设置（M3）
```

**硬性约束**：手机路径不 import 任何 `lib/tv/`；TV 路径复用 `lib/modules/*` 的 controller/model，不复用其页面 Widget。

---

## 1. TV 检测（M1）

- 原生：`MainActivity` 加 channel `pure_live/device_type`：
  - `UiModeManager.getCurrentModeType() == Configuration.UI_MODE_TYPE_TELEVISION`，或
  - `packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)`
- Dart：`TvDeviceService.isTv`（启动时取一次缓存）；无该通道（桌面/iOS）恒 false
- 已有 LEANBACK_LAUNCHER 声明，电视桌面可见；无需改动 Manifest

---

## 2. 视觉规格（对齐 pure_live_TV 实测参数）

### 颜色（深色固定；TV 上"跟随系统"解析为深色）

| 语义 | 值 |
|---|---|
| 页面底色 backgroundColor | `#121212` |
| 卡片 cardColor | `#1F1F1F` |
| 聚焦卡片 focusedCardColor | `#FFFFFF`（聚焦时文字自动切深色） |
| 主色 focusColor / 主文字 | `#00A1FF` / `#FFFFFF` |
| 次要文字 secondaryTextColor | `#B3FFFFFF`（70% 白） |
| 弱填充 subtleRowFill | 主文字色 6% 透明度 |
| 聚焦光晕 | focusColor @ 0.75、blur 18、spread 1.5 |
| 页面背景 | 底色向 focusColor lerp 10% 的对角渐变（无壁纸时） |

### 字号（1080p 设计基准，物理高度 <1080p 时整体 ×(1080/实际高) 补偿，上限 1.6）

t10/t12/t14/t15/t16/t17/t18/t19/t20/t22/t24/t25/t26/t28/t30/t32/t34/t40；正文主力 t14~t18，卡片标题 t18 w700，主播名 t16 w700，Tab/侧栏 t16~t18，页面标题 t24+。

### 几何与动画

- 卡片圆角 24、面板圆角 20、对话框行 12、按钮全圆角 999
- 卡片网格：默认 6 列（纵横比 1.5）/ 用户可调密度（列数 4~8，纵横比 1.3~1.5），行/列间距 16
- 统一动画：**聚焦 scale 1→1.05、按下 0.97，120ms easeOutCubic；失焦 Duration.zero**；页面切换 fadeIn 200ms + scale 0.95→1 250ms easeOutCubic；侧栏展开/收起 150ms
- 强制横屏：`SystemChrome` 锁定 landscapeLeft/Right（进入 TvApp 时设置，退出不走——TV 永远在 TV 树内）

---

## 3. 焦点系统设计（自写核心）

Flutter 原生 `FocusNode`/`FocusTraversalGroup` 之上做四件事：

1. **`TvFocusable`**：通用可聚焦包装。持有 FocusNode，onFocusChange 驱动 scale + 光晕 + 描边；`onSelect` 回调（OK/Enter/ DPAD_CENTER）；弹窗打开时吞 OK；处理"长按释放不误触发"。
2. **`TvFocusRegion`**：区域包装（= 侧栏 / Tab 条 / 内容网格 / 面板）。`memoryKey` 记住区域最后焦点（ValueNotifier 存内存即可，不落盘）；边缘行为参数 `edgeTop/edgeLeft/...`：
   - `leave`：把焦点交给相邻区域（网格 ↑→Tab 条，←→侧栏；侧栏 →→内容区）
   - `stop`：停在边缘（网格底部）
3. **自动滚动**：焦点变化时对滚动祖先做 `Scrollable.ensureVisible`（alignmentPolicy 保持焦点行上下各留一行上下文）。
4. **全局键兜底**：TvApp 根部 `Focus(onKeyEvent)` 拦截 DPAD_CENTER 长按（500ms 阈值）与未消费按键。

> 不引入 `dpad` ^3.0.0 包（对方生态依赖），用原生 Focus API 自实现等价子集；风险点见 §7。

---

## 4. 自写组件清单

| 组件 | 规格 | 用于 |
|---|---|---|
| TvFocusable | §3 | 全部 |
| TvFocusRegion | §3 | 壳/页面/面板 |
| TvScaffold | Row：侧栏 228（收起 160，背景主底色 62% 透明）+ 内容窗格 padding 8 | 壳与全部页面 |
| TvSideNav | 顶部 `HH:mm:ss` 数字时钟 + 日期；菜单项=图标+文字（聚焦放大、useFadedFocus）；底部固定"设置"；菜单可见性读现有 savedMenuIds 映射 | 壳 |
| TvTabBar | 横向平台 Tab + 刷新进度线（Future 驱动）；重复按当前 Tab=刷新 | 关注/热门/分类/搜索 |
| TvRoomCard | 24 圆角；封面（CachedNetworkImage，memCacheWidth 640）+ 左上平台 chip + 左上关注心 chip + 右下人气 chip；下方头像 56 + 标题（聚焦跑马灯）+ 主播名；聚焦时整卡白底放大 1.05 | 关注/热门/搜索/分类 |
| TvStatusChip | 半透明黑底圆角 chip，t12 | 卡片角标 |
| TvMarqueeText | 聚焦时单行跑马灯，失焦静止 | 卡片标题/长行 |
| TvPanel | 右侧浮层：宽 400、圆角 20、背景 92% + focusColor 35% 描边；`DpadRegion` 包内 | M2 播放面板 |
| TvIndexPanel | 索引选择模型：行= label/subtitle/value/icon，selected int 驱动，↑↓ 移动、OK 确认、← 关闭；选中行出可见带才滚动 | M2 清晰度/线路/弹幕设置 |
| TvPageShell | 标题栏 + 返回按钮（**返回按钮=页面 opening focus**） | M3 全部子页 |
| TvDialog | 居中卡片对话框，行式选项，弹窗锁（打开期间全局 onSelect 早退） | M3 |
| TvEmpty / TvLoading | 空态（图标+文案+提示按键）与加载态（转圈+t14） | 全部 |

---

## 5. 页面规格

### M1-壳 `TvHomePage`
```
┌──────┬──────────────────────────────────────────┐
│ 时钟  │  [关注] [热门] [分类] [搜索]   ← IndexedStack 保活     │
│──────│                                          │
│ 关注  │   TvTabBar(平台tab)                       │
│ 热门  │   ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐    │
│ 分类  │   │卡片│ │卡片│ │卡片│ │卡片│ │卡片│     │
│ 搜索  │   └────┘ └────┘ └────┘ └────┘ └────┘    │
│      │   ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐    │
│      │   │卡片│ │卡片│ │卡片│ │卡片│ │卡片│     │
│ 设置  │   └────┘ └────┘ └────┘ └────┘ └────┘    │
└──────┴──────────────────────────────────────────┘
```
- 侧栏是唯一竖列可滚动区；菜单切换动画 fadeIn+scale
- 关注页数据：`FavoriteController`（onlineRooms 排序逻辑现成）；热门页：站点层 `getRecommendRooms` + 现有分页逻辑
- 进入 M1 验收时：点卡片暂时进**现有手机播放页**（横屏全屏也能看，仅遥控不可用），播放页遥控属 M2

### M2-播放页 `TvPlayPage`（交互模型对齐 pure_live_TV）
- 视频永远全屏；进房先显示**顶部信息卡**（标题/平台/主播/人气/时钟，几秒后自动隐藏，showRoomInfo 独立于控制栏）
- 单 Focus 节点键位作用域（不走焦点遍历）：

| 状态 | OK | ↑/↓ | ← | → | Back |
|---|---|---|---|---|---|
| 无浮层 | 呼出底部控制栏 | **换台**（300ms 防抖累加，一次 commit） | 双击关注/取关（500ms 双击窗，单击提示） | 打开房间列表面板 | 退出 |
| 面板打开 | 按键归面板 | 面板 | 关面板 | 面板 | 关面板 |
| 控制栏可见 | 控制栏 | 控制栏未吃掉的仍换台 | 控制栏 | 控制栏 | 关控制栏 |
| 阻塞浮层（失败/未开播） | 浮层按钮 | 换台 | 浮层 | 浮层 | 退出 |

- 面板三种：房间列表（PlaylistPanel）/ 弹幕设置 / 屏蔽词；控制栏按钮组 = 暂停/清晰度/线路/画面比例/弹幕开关/收藏/刷新（索引模型）
- 换台横幅：切台时顶部显示频道名 toast
- 数据：复用 `LivePlayController`（换台=同平台下一个已开播关注/热门房间）

### M3-分类/搜索/设置
- 分类：平台 Tab + 分区网格（复用 AreasPage 数据）→ 分区房间页（TvPageShell + 网格）
- 搜索：TvSearchPage = 平台 Tab + 搜索框（android_tv_text_field 思路：遥控器输入引导到弹出的输入面板）+ 结果网格
- 设置：目录页（分组列表：主题/播放/弹幕/账号/关于）+ 子页（TvPageShell + 开关/选项/滑块 Tile 家族）；只收我们现有设置项，组织对齐 TV 目录式

---

## 6. 里程碑与验收标准

| 里程碑 | 内容 | 验收 |
|---|---|---|
| **M1**✅（已完成） | 检测/主题/**索引选择模型**（弃 Focus 遍历，电视上不可靠）/壳/关注/热门 + 扫码同步手机关注（TV 起 HttpServer 显示二维码，手机「备份→发送数据」现有流程零改动直推，并集合并） | 小米电视 237 装机：adb 全链路验证（导航闭环/卡片高亮/自动分页/扫码推送 E2E 合并） |
| **M2** | TvPlayPage 键位作用域 + 索引面板（清晰度/线路/弹幕设置）+ 换台 | 电视上完整看播：换台/切清晰度/开关弹幕全遥控 |
| **M3** | 分类/搜索/设置 TV 化 + TvDialog/弹窗锁 + 关注管理（含删除同步来的房间） | 全功能遥控可达 |
| **M4** | 收尾：回归手机端、README/发版说明、双端 Release | v2.6.0 发版 |

工作量：M1 3~5 天 / M2 2~3 天 / M3 2~3 天 / M4 1 天。每里程碑 bump 不动版本号，M4 统一 bump。

### ⚠️ 实施期发现的三大坑（M2/M3 必读）

1. **TV 下 GetX 路由静默失效**：`Get.toNamed` 在 TvApp 的 GetMaterialApp 下 pushNamed 被调用但页面不渲染、Future 挂起（Get.key 导航器未接上）。TV 内页面跳转一律用 `Navigator.of(Get.context!)` 直推；且 **AppPages.routes 不能挂给 TvApp**（kInitial "/home" 被当 "/" 解析，手机版首页会整个跑进 TV 树）。
2. **Flutter 焦点系统在电视上不可靠**（traversal 静默丢焦/autofocus 竞态）：TV 页面一律用**索引选择模型**（单 Focus 收全键按 zone+索引分派），勿用 Focus 遍历。
3. **gradle 增量构建会吞 Dart 改动**（"4 executed" 出旧包）：改 Dart 后必须 `clean assembleRelease`（clean 后首跑可能不产 APK，再跑一次 assemble）；media_kit 构建需挂 NAS 代理（-Dhttp/https.proxyHost）。

---

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| 自写焦点系统在小米电视上方向键事件异常（部分盒子 KeyEvent 不标准） | M1 第一天先做"焦点探针页"装机验证原始 KeyEvent 流，确认 DPAD 事件可达再铺组件 |
| 现有页面在 TV 分辨率/横屏下的字体过小 | 字号补偿函数（§2）+ 卡片网格列数随密度自适应 |
| 现有 `LivePlayController` 与 TV 播放页耦合（它假设手机 UI 存在） | TvPlayPage 只消费其数据流与播放内核，UI 命令走 controller 公开方法；冲突时在 controller 加 TV 分支而非改手机行为 |
| 分支遗漏（手机用户在 TV 检测误判） | 检测双条件（UiModeManager 或 leanback feature）都满足才判 TV；设置里预留"强制 TV 界面"开关兜底 |
| AGPL 污染 | 只读参考仓库不进我们 repo；组件全部自写；克隆目录 `_purelive_tv_ref` 放 E:\codex 不入库 |
