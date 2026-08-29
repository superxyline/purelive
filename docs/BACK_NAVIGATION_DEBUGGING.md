# 滑动返回失效问题排查全记录

> 本文记录 pure_live 定制版"滑动返回失效"系列问题从现象到根因的完整排查过程与最终结论，
> 供后续维护参考。所有结论均基于设备日志实证，非推测。

## 一、症状时间线

同一类"滑动返回没反应/行为错误"的表象，先后在以下场景被报告：

1. 全屏状态下滑动返回，直接退出直播间并残留横屏（最初报告）。
2. 点击弹幕输入框或送礼物后，全屏滑动返回大概率失效。
3. 开启双开副窗口并切换主副后，滑动返回、音量按钮、左上角箭头全部失效，
   且换其他直播间也一样。
4. 通过搜索进入直播间后，滑动返回完全无反应（非全屏与全屏都失效），
   杀掉 App 重开后暂时恢复。

这些表象背后其实是 **五个相互独立的缺陷叠加**，任何一个未修复都会表现为
"滑动返回不正常"。

## 二、根因清单（按事件链从上游到下游）

### 根因 1：GetX `popRoute` 绕过 PopScope（全屏滑动返回直接退直播间）

系统返回经 `WidgetsBinding.handlePopRoute` → `RouterDelegate.popRoute` 分发。
GetX 原版 `GetDelegate.popRoute` 只对 PopupRoute 调 `maybePop`，对普通页面
直接改 `_activePages` 并重建 pages——**完全绕过页面内 `PopScope(canPop:false)`**，
直播间被直接弹掉。

**修复**：普通页面改为 `await navigator.maybePop(result)`，让 PopScope 参与决策；
真弹出时由 Navigator 的 `onPopPage` 回调（`_onPopVisualRoute` → `_popWithResult`）
自动同步 GetX 路由栈。

**关键教训**：Flutter 的 `Navigator.maybePop` 在**被 PopScope 拦截（doNotPop）时
同样返回 `true`**（见 Flutter `navigator.dart` 的 `maybePop` 实现，`doNotPop`
分支回调 `onPopInvokedWithResult(false)` 后 `return true`）。不能用它的返回值
区分"真弹出"与"被拦截"，否则会在拦截场景误删 GetX 栈记录，引发 pages 重建
把路由真弹掉（这正是修复过程中出现过的一次回归）。

### 根因 2：全屏切换标志卡死 + 无条件吞事件分支（输入框/送礼后失效）

`enterFullScreen/exitFullScreen` 置位 `isTransitioningFullScreen` 后，
依赖横竖屏切换的**平台通道调用返回**才复位。MIUI 上键盘收起/系统栏动画期间
该调用可能长时间不返回；而 PopScope 回调里有一个"切换进行中就直接吞掉返回
事件"的早退分支——标志一旦卡死，**之后所有滑动返回都被无声吞掉**。

**修复**：
- 删除吞事件早退分支（`handleBackPress` 自身幂等，且有 600ms 连发保护兜底）；
- 给 `landScape()/verticalScreen()/SystemChrome` 调用加 3 秒超时，
  保证切换标志必然复位；
- 按钮路径退出全屏（含全屏左上角箭头）也纳入连发保护窗口（`markFullscreenExit`），
  并补全箭头缺失的"恢复竖屏+系统栏"逻辑。

### 根因 3：自动全屏定时器（双开切换后被"拉回"全屏）

每次播放器初始化都会武装一个 1 秒后的"自动进入全屏"定时器
（`_setupDefaultFullscreen`）。主副切换会重建播放器、重新武装该定时器，
把用户刚退出的全屏又强行拉回去，表现为"退出全屏没生效"。

**修复**：双开副窗口激活期间跳过自动全屏。

### 根因 4：画中画标志卡死 + escape 处理器吞键（点弹幕输入/送礼场景加重）

- 安卓返回键会被 Flutter 引擎映射为 **`LogicalKeyboardKey.escape`**；
- `VideoKeyboardShortcuts` 注册了全局 `HardwareKeyboard` 处理器捕获 escape
  （用于键盘退出全屏），并在**画中画标志为 true 时静默跳过、但仍返回"已处理"**；
- `isInPip` 标志由第三方画中画插件的 `pipStatusStream` 驱动，**流丢一次事件
  就永久卡在 true**（典型场景：退后台触发自动小窗，回来后小窗已被系统关闭）。

三者叠加：标志卡死后，每次返回键都被 escape 处理器无声吞掉，
直到杀掉 App 重开。

**修复**：
- escape 处理器在画中画状态下不消费事件，交给框架返回路径；
- `PlayerManager.exitPip()` 强制复位 `isInPip`，让状态自愈。

### 根因 5（最终根因）：引擎返回键"重派发"链路丢事件（搜索进直播间场景）

抓到决定性证据：失效的滑动返回，系统层日志显示
`KEYCODE_BACK` 按键事件已送入应用视图层且
`ViewPostImeInputStage ... handled: true`，但 **Dart 侧所有返回处理层
（`handlePopRoute`、Router、PopScope）零日志**。

结论：MIUI 手势返回有时以**按键事件**（而非 predictive-back 回调）形式进入
Flutter 键盘管线（`KeyboardManager`）。`KeyboardManager.handleEvent`
**无条件向视图层返回 `true`**（源码即如此，与 Dart 的处理结果无关），Dart 侧
无人认领该键时，引擎通过"重派发→Activity onBackPressed"补救链触发返回——
**该补救链存在丢事件的情况**（搜索页输入框等产生活跃输入连接的场景更易触发）。
事件丢失后即表现为"完全无反应"，且不留任何 Dart 层日志。

**修复**：App 启动时注册全局 `HardwareKeyboard` 处理器（`main.dart` 的
`_backKeyHandler`），直接接管 `LogicalKeyboardKey.goBack` 按键，走与系统返回
完全一致的 `RouterDelegate.popRoute`（尊重弹窗/全屏拦截/PopScope 全套逻辑），
处理后返回 true 阻止引擎重派发造成双重返回。

## 三、诊断方法论（踩坑经验）

1. **分层探针**是定位此类问题的唯一可靠手段：
   - 系统层：`adb logcat` 过滤 `MIUIInput`（按键投递）、
     `OnBackInvokedCallbackWrapper`（回调投递）、`InsetsController`（键盘状态）；
   - 框架层：直接在本地 Flutter SDK 的 `widgets/binding.dart` 的
     `handlePopRoute/_handleStartBackGesture/_handleCommitBackGesture` 加临时
     打印（工具链是 git 仓库，可干净还原）；
   - 应用层：PopScope 入口、`handleBackPress`、`popRoute`、路由栈名。
2. **"View 层 handled:true"不代表事件被正确处理**——`KeyboardManager`
   无条件返回 true，真正的裁决在异步的 Dart 回复里。
3. MIUI 系统日志刷屏会很快冲掉 logcat 缓冲，必须**流式捕获到文件**
   （`adb logcat > file`），否则复现记录会丢失。
4. 真弹出与被拦截在 Navigator 侧都会回调 `onPopInvokedWithResult`，
   区分只能靠 `didPop` 参数或对比路由栈快照。
5. 修复"返回"类问题时，**必须同时覆盖按钮路径**（箭头/控制条按钮），
   它们与手势路径共享状态位但常常漏掉恢复逻辑（根因 2 的箭头缺陷）。

## 四、当前防护结构

```
系统手势
  ├─ (A) predictive-back 回调路径 → WidgetsBinding → Router.popRoute
  └─ (B) KEYCODE_BACK 按键路径 → 引擎键盘管线 → KeyDownEvent
        ├─ LogicalKeyboardKey.escape → VideoKeyboardShortcuts（仅用于键盘退出全屏；
        │     画中画标志异常时不吞事件，落回框架）
        └─ LogicalKeyboardKey.goBack → main.dart _backKeyHandler
              → GetDelegate.popRoute（与 A 汇合，单一入口）
                     → PopScope（直播间拦截/全屏退出/连发保护）
                     → Navigator.maybePop → onPopPage 同步 GetX 栈
```

## 五、遗留事项

- `_backKeyHandler` 与 `VideoKeyboardShortcuts` 的 escape 处理为有意保留的
  防御层。若未来 Flutter 引擎修复了重派发链路，`_backKeyHandler` 可移除。
- 调试期的 `[BackDebug]`/`[BackDebug] FW` 探针（App 与本地 Flutter SDK）
  在问题闭环后应统一移除。
