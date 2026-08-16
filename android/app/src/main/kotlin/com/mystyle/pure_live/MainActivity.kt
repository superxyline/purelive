package com.mystyle.purelive

import android.os.Build
import android.os.SystemClock
import android.view.KeyEvent
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    /** 上一次返回键触发 Flutter popRoute 的时间，用于拦截 MIUI 返回键双路径（系统回调 + KeyEvent 分发）导致的重复 pop。 */
    private var lastBackPopAt = 0L

    /** Flutter framework 是否在自行处理返回键（对应 setFrameworkHandlesBack 的最近一次状态）。 */
    private var frameworkHandlesBack = false

    /**
     * 高优先级返回回调：抢在系统输入法（IME）之前处理返回键。
     * 场景：从搜索页进入直播间后，MIUI 的输入法进程会持续拦截返回键（键盘已隐藏但输入法内部状态残留），
     * 导致返回键完全到不了 App。用 PRIORITY_OVERLAY 注册可以让 App 先于输入法收到返回事件。
     */
    private val highPriorityBackCallback: OnBackInvokedCallback? =
        if (Build.VERSION.SDK_INT >= 33) {
            OnBackInvokedCallback { handleBackKey() }
        } else {
            null
        }

    private var highPriorityCallbackRegistered = false

    /** 统一返回入口：把返回键转给 Flutter 路由（与左上角返回箭头同一条链路）；防重窗口内的重复触发直接吞掉。 */
    private fun handleBackKey(): Boolean {
        val engine = flutterEngine ?: return false
        val now = SystemClock.uptimeMillis()
        if (now - lastBackPopAt < 400) return true
        lastBackPopAt = now
        engine.navigationChannel.popRoute()
        return true
    }

    /** 记录 framework 的返回处理状态（Flutter 路由变化时通过 channel 更新）。 */
    override fun setFrameworkHandlesBack(frameworkHandlesBack: Boolean) {
        this.frameworkHandlesBack = frameworkHandlesBack
        super.setFrameworkHandlesBack(frameworkHandlesBack)
        // framework 处理返回时注册高优先级回调（抢在 IME 前）；不处理时注销，让系统按默认行为处理（如首页退出 App）。
        if (Build.VERSION.SDK_INT >= 33) {
            val callback = highPriorityBackCallback ?: return
            if (frameworkHandlesBack && !highPriorityCallbackRegistered) {
                onBackInvokedDispatcher.registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_OVERLAY, callback,
                )
                highPriorityCallbackRegistered = true
            } else if (!frameworkHandlesBack && highPriorityCallbackRegistered) {
                onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback)
                highPriorityCallbackRegistered = false
            }
        }
    }

    /** 系统返回路径（framework 处理返回 / OnBackInvoked 时调用）。 */
    override fun onBackPressed() {
        if (!handleBackKey()) {
            super.onBackPressed()
        }
    }

    /** 键盘路径：部分 MIUI 版本返回键同时以 KeyEvent 分发给窗口；DOWN 先消费并追踪，等 UP 统一处理。 */
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && event.repeatCount == 0) {
            event.startTracking()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && event.isTracking && !event.isCanceled) {
            // 仅当 framework 不处理返回时（回调未注册，KeyEvent 是唯一路径）才在这里兜底；
            // framework 处理时（直播间等），返回键由 onBackPressed 统一走，KeyEvent 是 MIUI 的重复路径，
            // 交给 super.onKeyUp 的默认行为（再次进 onBackPressed），由 handleBackKey 的防重窗口拦截重复 pop。
            if (!frameworkHandlesBack) {
                if (handleBackKey()) return true
            }
        }
        return super.onKeyUp(keyCode, event)
    }
}
