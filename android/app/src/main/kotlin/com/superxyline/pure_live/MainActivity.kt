package com.superxyline.purelive

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.hardware.display.DisplayManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.Display
import com.ryanheise.audioservice.AudioServiceActivity
import com.superxyline.purelive.widget.WidgetData
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val DISPLAY_MODE_CHANNEL = "pure_live/display_mode"
        private const val BACKGROUND_PLAYBACK_CHANNEL = "pure_live/background_playback"
        private const val APP_SHORTCUTS_CHANNEL = "pure_live/app_shortcuts"
        private const val SHARE_CHANNEL = "pure_live/share"
        private const val LOCAL_NETWORK_CHANNEL = "pure_live/local_network"
        private const val APP_WIDGET_CHANNEL = "pure_live/app_widget"
        private const val LOCAL_NETWORK_REQUEST_CODE = 0x4C4E

        /// 快捷方式/小组件共用的导航参数："platform|roomId" 或 "esports"
        const val EXTRA_SHORTCUT_ROOM = "pure_live.shortcut.ROOM"

        /// 小组件刷新按钮 → Dart 的实时转发通道（App 进程存活才非空）
        @Volatile
        var widgetRefreshChannel: MethodChannel? = null

        /// 由 [com.superxyline.purelive.widget.WidgetRefreshReceiver] 调用：
        /// App 进程存活时把刷新请求转发给 Dart 拉最新数据；未存活则静默忽略
        /// （小组件保留最后一次缓存内容）。
        fun requestWidgetRefresh(target: String) {
            val channel = widgetRefreshChannel ?: return
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("refresh", target)
            }
        }

        private var playbackWakeLock: PowerManager.WakeLock? = null
        private var playbackWifiLock: WifiManager.WifiLock? = null
    }

    private var highRefreshRateEnabled = true
    private var displayModeChannel: MethodChannel? = null
    private var appShortcutsChannel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private var pendingShortcutRoom: String? = null
    private var pendingShareText: String? = null
    private var displayListenerRegistered = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val displayModeRefresh = Runnable {
        val info = applyPreferredDisplayMode(highRefreshRateEnabled)
        displayModeChannel?.invokeMethod("displayModeChanged", info)
    }
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = scheduleDisplayModeRefresh()

        override fun onDisplayRemoved(displayId: Int) = scheduleDisplayModeRefresh()

        override fun onDisplayChanged(displayId: Int) {
            val currentDisplayId = activeDisplay()?.displayId
            if (currentDisplayId == null || currentDisplayId == displayId) {
                scheduleDisplayModeRefresh()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appShortcutsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_SHORTCUTS_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setShortcuts" -> {
                        val items = call.argument<ArrayList<HashMap<String, String>>>("items")
                        setRecentRoomShortcuts(items ?: arrayListOf())
                        result.success(true)
                    }
                    "getPendingShortcut" -> result.success(consumePendingShortcutRoom())
                    else -> result.notImplemented()
                }
            }
        }
        pendingShortcutRoom = intent?.getStringExtra(EXTRA_SHORTCUT_ROOM)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingShare" -> result.success(consumePendingShareText())
                    else -> result.notImplemented()
                }
            }
        }
        // 冷启动：分享进来的链接在 Flutter 起来之前就到了，这里先存起来，
        // Dart 侧注册好 handler 后会主动 getPendingShare 取走。
        captureShareText(intent)
        displayModeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DISPLAY_MODE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHighRefreshRate" -> {
                        highRefreshRateEnabled = call.argument<Boolean>("enabled") ?: true
                        result.success(applyPreferredDisplayMode(highRefreshRateEnabled))
                    }

                    "getDisplayModeInfo" -> result.success(displayModeInfo())
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_PLAYBACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepAlive" -> {
                    setPlaybackKeepAlive(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCAL_NETWORK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensure" -> result.success(ensureLocalNetworkPermission())
                "granted" -> result.success(isLocalNetworkGranted())
                else -> result.notImplemented()
            }
        }
        // 桌面小组件：Dart 推送数据（JSON）+ 触发重绘；刷新按钮经
        // WidgetRefreshReceiver → widgetRefreshChannel 反向唤醒 Dart
        widgetRefreshChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_WIDGET_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidgets" -> {
                        WidgetData.save(this, call.argument<String>("live"), call.argument<String>("esports"))
                        WidgetData.renderAll(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        applyPreferredDisplayMode(highRefreshRateEnabled)
    }

    override fun onStart() {
        super.onStart()
        registerDisplayListener()
        scheduleDisplayModeRefresh(delayMillis = 0)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val shortcutRoom = intent.getStringExtra(EXTRA_SHORTCUT_ROOM)
        if (!shortcutRoom.isNullOrEmpty()) {
            pendingShortcutRoom = shortcutRoom
            appShortcutsChannel?.invokeMethod("onShortcut", shortcutRoom)
        }
        // 热启动：App 已在后台，直接把分享文本推给 Dart 侧
        captureShareText(intent)
    }

    /// 取分享进来的直播链接文本（`ACTION_SEND` 的 EXTRA_TEXT，或 `ACTION_VIEW` 的 data）。
    ///
    /// 只接管含 http 的内容：`purelive://`、`content://`、`file://` 这类自有 scheme
    /// 走的是别的入口，交给链接解析只会误报"不支持"。
    private fun captureShareText(intent: Intent?) {
        if (intent == null) return
        val raw = when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }?.trim()
        if (raw.isNullOrEmpty() || !raw.contains("http")) return
        pendingShareText = raw
        shareChannel?.invokeMethod("onShare", raw)
    }

    private fun consumePendingShareText(): String? {
        val value = pendingShareText
        pendingShareText = null
        return value
    }

    private fun consumePendingShortcutRoom(): String? {
        val value = pendingShortcutRoom
        pendingShortcutRoom = null
        return value
    }

    /// 局域网权限（Android 16 / API 36 起）：NAS 同步、局域网代理访问 192.168.x.x
    /// 之前必须先拿到 ACCESS_LOCAL_NETWORK，否则系统直接拒绝连接且没有异常提示。
    private fun isLocalNetworkGranted(): Boolean {
        if (Build.VERSION.SDK_INT < 36) return true
        return checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun ensureLocalNetworkPermission(): Boolean {
        if (isLocalNetworkGranted()) return true
        requestPermissions(
            arrayOf("android.permission.ACCESS_LOCAL_NETWORK"),
            LOCAL_NETWORK_REQUEST_CODE,
        )
        // 授权是异步的：这里返回 false 表示"已弹出系统授权框"，调用方不阻塞。
        return false
    }

    /// 更新桌面长按快捷方式：最近打开的直播间（最多 3 个）。
    private fun setRecentRoomShortcuts(items: List<Map<String, String>>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val manager = getSystemService(ShortcutManager::class.java) ?: return
        try {
            val shortcuts = items.take(3).mapNotNull { item ->
                val id = item["id"] ?: return@mapNotNull null
                val intent = Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    putExtra(EXTRA_SHORTCUT_ROOM, id)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                ShortcutInfo.Builder(this, id)
                    .setShortLabel(item["label"] ?: "")
                    .setIcon(Icon.createWithResource(this, R.drawable.ic_launcher_foreground))
                    .setIntent(intent)
                    .build()
            }
            manager.removeAllDynamicShortcuts()
            manager.setDynamicShortcuts(shortcuts)
        } catch (e: Exception) {
            // 桌面不支持动态快捷方式或应用处于后台，忽略。
        }
    }

    @Suppress("DEPRECATION")
    private fun setPlaybackKeepAlive(enabled: Boolean) {
        if (enabled) {
            if (playbackWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                playbackWakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "$packageName:backgroundPlayback",
                ).apply { setReferenceCounted(false) }
            }
            if (playbackWakeLock?.isHeld != true) playbackWakeLock?.acquire()

            if (playbackWifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                playbackWifiLock = wifiManager.createWifiLock(mode, "$packageName:backgroundPlayback").apply {
                    setReferenceCounted(false)
                }
            }
            if (playbackWifiLock?.isHeld != true) playbackWifiLock?.acquire()
        } else {
            if (playbackWifiLock?.isHeld == true) playbackWifiLock?.release()
            if (playbackWakeLock?.isHeld == true) playbackWakeLock?.release()
        }
    }

    override fun onResume() {
        super.onResume()
        scheduleDisplayModeRefresh(delayMillis = 0)
    }

    override fun onStop() {
        unregisterDisplayListener()
        super.onStop()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(displayModeRefresh)
        displayModeChannel = null
        widgetRefreshChannel = null
        super.onDestroy()
    }

    private fun registerDisplayListener() {
        if (displayListenerRegistered) return
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager.registerDisplayListener(displayListener, mainHandler)
        displayListenerRegistered = true
    }

    private fun unregisterDisplayListener() {
        if (!displayListenerRegistered) return
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager.unregisterDisplayListener(displayListener)
        displayListenerRegistered = false
        mainHandler.removeCallbacks(displayModeRefresh)
    }

    private fun scheduleDisplayModeRefresh(delayMillis: Long = 160) {
        mainHandler.removeCallbacks(displayModeRefresh)
        mainHandler.postDelayed(displayModeRefresh, delayMillis)
    }

    @Suppress("DEPRECATION")
    private fun activeDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay

    private fun applyPreferredDisplayMode(enabled: Boolean): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return displayModeInfo()
        val activeDisplay = activeDisplay() ?: return displayModeInfo()
        val currentMode = activeDisplay.mode
        val compatibleModes = activeDisplay.supportedModes.filter {
            it.physicalWidth == currentMode.physicalWidth &&
                it.physicalHeight == currentMode.physicalHeight
        }
        val preferredMode = compatibleModes.maxWithOrNull(
            compareBy<Display.Mode> { it.refreshRate }.thenBy { it.modeId },
        ) ?: currentMode

        val attributes = window.attributes
        val targetModeId = if (enabled) preferredMode.modeId else 0
        val targetRefreshRate = if (enabled) preferredMode.refreshRate else 0f
        if (
            attributes.preferredDisplayModeId != targetModeId ||
            kotlin.math.abs(attributes.preferredRefreshRate - targetRefreshRate) > 0.01f
        ) {
            attributes.preferredDisplayModeId = targetModeId
            attributes.preferredRefreshRate = targetRefreshRate
            window.attributes = attributes
        }
        return displayModeInfo(if (enabled) preferredMode else currentMode)
    }

    private fun displayModeInfo(preferredMode: Display.Mode? = null): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "enabled" to highRefreshRateEnabled,
                "currentRefreshRate" to 60.0,
                "maxRefreshRate" to 60.0,
                "preferredRefreshRate" to 60.0,
                "supportedRefreshRates" to listOf(60.0),
            )
        }

        val activeDisplay = activeDisplay()
            ?: return mapOf("enabled" to highRefreshRateEnabled)
        val currentMode = activeDisplay.mode
        val compatibleModes = activeDisplay.supportedModes.filter {
            it.physicalWidth == currentMode.physicalWidth &&
                it.physicalHeight == currentMode.physicalHeight
        }
        val rates = compatibleModes
            .map { it.refreshRate.toDouble() }
            .distinctBy { kotlin.math.round(it * 100).toInt() }
            .sorted()
        val bestMode = preferredMode ?: compatibleModes.maxByOrNull { it.refreshRate } ?: currentMode

        return mapOf(
            "enabled" to highRefreshRateEnabled,
            "currentRefreshRate" to currentMode.refreshRate.toDouble(),
            "maxRefreshRate" to (rates.maxOrNull() ?: currentMode.refreshRate.toDouble()),
            "preferredRefreshRate" to bestMode.refreshRate.toDouble(),
            "supportedRefreshRates" to rates,
            "width" to currentMode.physicalWidth,
            "height" to currentMode.physicalHeight,
            "displayId" to activeDisplay.displayId,
            "preferredDisplayModeId" to window.attributes.preferredDisplayModeId,
            "requestedRefreshRate" to window.attributes.preferredRefreshRate.toDouble(),
        )
    }
}
