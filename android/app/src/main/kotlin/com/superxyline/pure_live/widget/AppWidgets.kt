package com.superxyline.purelive.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.superxyline.purelive.MainActivity
import com.superxyline.purelive.R
import org.json.JSONArray
import org.json.JSONObject

/// 桌面小组件（澎湃OS 风格 2×2）：
/// - 直播间热度榜：已开播关注直播间按热度前 4（单行：主播名+热度），点击直达直播间；
/// - 赛事日程：已关注赛事按开始时间前 2 场，每场两行完整信息，点击进赛事中心。
///
/// 数据流：Dart 侧 [MainActivity] 的 `pure_live/app_widget` 通道把 JSON 写进
/// SharedPreferences → 渲染成 RemoteViews；行点击复用快捷方式通道
/// （`EXTRA_SHORTCUT_ROOM` = "platform|roomId" / "esports"）；
/// 刷新按钮广播给 [WidgetRefreshReceiver]：先用现有缓存重绘（秒回），
/// 再唤醒 Dart 拉最新数据回写。
object WidgetData {
    private const val PREFS = "pure_live_widget"
    private const val KEY_LIVE = "live_json"
    private const val KEY_ESPORTS = "esports_json"

    private const val MAX_ROWS = 4

    /// 赛事小组件 2×2 幅面只放得下 2 场（每场两行完整信息）
    private const val MAX_ESPORTS_ROWS = 2
    private const val ACTION_REFRESH = "com.superxyline.purelive.WIDGET_REFRESH"

    fun save(context: Context, liveJson: String?, esportsJson: String?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_LIVE, liveJson)
            .putString(KEY_ESPORTS, esportsJson)
            .apply()
    }

    fun renderAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val manager = AppWidgetManager.getInstance(context) ?: return
        renderLiveRooms(context, manager, prefs.getString(KEY_LIVE, null))
        renderEsports(context, manager, prefs.getString(KEY_ESPORTS, null))
    }

    private fun refreshPendingIntent(context: Context, target: String): PendingIntent {
        val intent = Intent(ACTION_REFRESH).setClass(context, WidgetRefreshReceiver::class.java)
            .putExtra("target", target)
        return PendingIntent.getBroadcast(
            context,
            target.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /// 行点击 → MainActivity（复用快捷方式导航链路，冷/热启动均已打通）
    private fun navigatePendingIntent(context: Context, requestCode: Int, type: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(MainActivity.EXTRA_SHORTCUT_ROOM, type)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun appLaunchPendingIntent(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent()
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // -------------------------------------------------------------------------
    // 直播间热度榜
    // -------------------------------------------------------------------------

    fun renderLiveRooms(context: Context, manager: AppWidgetManager, liveJson: String?) {
        val views = RemoteViews(context.packageName, R.layout.widget_live_rooms)
        views.setOnClickPendingIntent(R.id.widget_live_refresh, refreshPendingIntent(context, "live"))
        views.setOnClickPendingIntent(R.id.widget_live_header, appLaunchPendingIntent(context))

        val rows = mutableListOf<JSONObject>()
        liveJson?.let {
            try {
                val array = JSONArray(it)
                for (i in 0 until array.length()) rows.add(array.getJSONObject(i))
            } catch (_: Exception) {
            }
        }

        if (rows.isEmpty()) {
            views.setViewVisibility(R.id.widget_live_empty, android.view.View.VISIBLE)
            views.setViewVisibility(R.id.widget_live_div_header, android.view.View.GONE)
            for (i in 1..MAX_ROWS) {
                views.setViewVisibility(rowId(context, "widget_live_row", i), android.view.View.GONE)
                if (i < MAX_ROWS) views.setViewVisibility(rowId(context, "widget_live_div", i), android.view.View.GONE)
            }
        } else {
            views.setViewVisibility(R.id.widget_live_empty, android.view.View.GONE)
            views.setViewVisibility(R.id.widget_live_div_header, android.view.View.VISIBLE)
            for (i in 1..MAX_ROWS) {
                val rowId = rowId(context, "widget_live_row", i)
                if (i > rows.size) {
                    views.setViewVisibility(rowId, android.view.View.GONE)
                    if (i < MAX_ROWS) views.setViewVisibility(rowId(context, "widget_live_div", i), android.view.View.GONE)
                    continue
                }
                val item = rows[i - 1]
                val live = item.optBoolean("live", false)
                views.setViewVisibility(rowId, android.view.View.VISIBLE)
                if (i < MAX_ROWS) {
                    views.setViewVisibility(
                        rowId(context, "widget_live_div", i),
                        if (i < rows.size) android.view.View.VISIBLE else android.view.View.GONE,
                    )
                }
                views.setTextViewText(textId(context, "widget_live_nick", i), item.optString("nick", ""))
                views.setTextViewText(textId(context, "widget_live_heat", i), item.optString("heat", ""))
                views.setTextViewText(textId(context, "widget_live_dot", i), "●")
                views.setTextColor(
                    textId(context, "widget_live_dot", i),
                    if (live) context.getColor(R.color.widget_live_badge) else context.getColor(R.color.widget_text_secondary),
                )
                views.setTextColor(
                    textId(context, "widget_live_heat", i),
                    if (live) context.getColor(R.color.widget_accent) else context.getColor(R.color.widget_text_secondary),
                )
                views.setOnClickPendingIntent(
                    rowId,
                    navigatePendingIntent(
                        context,
                        1000 + i,
                        "${item.optString("platform", "")}|${item.optString("roomId", "")}",
                    ),
                )
            }
        }
        manager.updateAppWidget(ComponentName(context, LiveRoomsWidgetProvider::class.java), views)
    }

    // -------------------------------------------------------------------------
    // 赛事日程
    // -------------------------------------------------------------------------

    fun renderEsports(context: Context, manager: AppWidgetManager, esportsJson: String?) {
        val views = RemoteViews(context.packageName, R.layout.widget_esports_schedule)
        views.setOnClickPendingIntent(R.id.widget_esports_refresh, refreshPendingIntent(context, "esports"))
        views.setOnClickPendingIntent(R.id.widget_esports_header, appLaunchPendingIntent(context))
        // 整块点击进赛事中心（行点击也是同一个目的地）
        views.setOnClickPendingIntent(R.id.widget_esports_list, navigatePendingIntent(context, 2000, "esports"))

        val rows = mutableListOf<JSONObject>()
        esportsJson?.let {
            try {
                val array = JSONArray(it)
                for (i in 0 until array.length()) rows.add(array.getJSONObject(i))
            } catch (_: Exception) {
            }
        }

        if (rows.isEmpty()) {
            views.setViewVisibility(R.id.widget_esports_empty, android.view.View.VISIBLE)
            views.setViewVisibility(R.id.widget_esports_div_header, android.view.View.GONE)
            for (i in 1..MAX_ESPORTS_ROWS) {
                views.setViewVisibility(rowId(context, "widget_esports_row", i), android.view.View.GONE)
            }
            views.setViewVisibility(R.id.widget_esports_div_1, android.view.View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_esports_empty, android.view.View.GONE)
            views.setViewVisibility(R.id.widget_esports_div_header, android.view.View.VISIBLE)
            views.setViewVisibility(
                R.id.widget_esports_div_1,
                if (rows.size >= 2) android.view.View.VISIBLE else android.view.View.GONE,
            )
            for (i in 1..MAX_ESPORTS_ROWS) {
                val rowId = rowId(context, "widget_esports_row", i)
                if (i > rows.size) {
                    views.setViewVisibility(rowId, android.view.View.GONE)
                    continue
                }
                val item = rows[i - 1]
                val live = item.optBoolean("live", false)
                val ended = item.optBoolean("ended", false)
                views.setViewVisibility(rowId, android.view.View.VISIBLE)

                // 元信息行：时间 · 赛事名（灰） + 状态（前瞻蓝/进行中红/已结束灰）
                views.setTextViewText(textId(context, "widget_esports_time", i), item.optString("timeText", ""))
                views.setTextViewText(textId(context, "widget_esports_series", i), item.optString("series", ""))
                views.setTextViewText(textId(context, "widget_esports_status", i), item.optString("statusText", ""))
                views.setTextColor(
                    textId(context, "widget_esports_status", i),
                    when {
                        live -> context.getColor(R.color.widget_live_badge)
                        ended -> context.getColor(R.color.widget_text_secondary)
                        else -> context.getColor(R.color.widget_accent)
                    },
                )

                // 对阵行：队徽 + 队名（粗） + vs + 比分；无队徽隐藏占位
                val logoA = decodeLogo(item.optString("logoA", ""))
                val logoB = decodeLogo(item.optString("logoB", ""))
                if (logoA != null) {
                    views.setViewVisibility(viewId(context, "widget_esports_logo_a", i), android.view.View.VISIBLE)
                    views.setImageViewBitmap(viewId(context, "widget_esports_logo_a", i), logoA)
                } else {
                    views.setViewVisibility(viewId(context, "widget_esports_logo_a", i), android.view.View.INVISIBLE)
                }
                if (logoB != null) {
                    views.setViewVisibility(viewId(context, "widget_esports_logo_b", i), android.view.View.VISIBLE)
                    views.setImageViewBitmap(viewId(context, "widget_esports_logo_b", i), logoB)
                } else {
                    views.setViewVisibility(viewId(context, "widget_esports_logo_b", i), android.view.View.INVISIBLE)
                }
                views.setTextViewText(textId(context, "widget_esports_name_a", i), item.optString("teamA", ""))
                views.setTextViewText(textId(context, "widget_esports_name_b", i), item.optString("teamB", ""))
                val score = item.optString("score", "")
                views.setTextViewText(textId(context, "widget_esports_score", i), if (score.isNotEmpty()) score else "--")
            }
        }
        manager.updateAppWidget(ComponentName(context, EsportsWidgetProvider::class.java), views)
    }

    /// base64 → 位图（Dart 侧预下载的队徽；失败返回 null 由调用方隐藏占位）
    private fun decodeLogo(base64: String): android.graphics.Bitmap? = try {
        if (base64.isEmpty()) null
        else {
            val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }
    } catch (_: Exception) {
        null
    }

    private fun rowId(context: Context, name: String, index: Int): Int =
        context.resources.getIdentifier("${name}_$index", "id", context.packageName)

    private fun textId(context: Context, name: String, index: Int): Int =
        context.resources.getIdentifier("${name}_$index", "id", context.packageName)

    private fun viewId(context: Context, name: String, index: Int): Int =
        context.resources.getIdentifier("${name}_$index", "id", context.packageName)
}

/// 直播间热度榜小组件
class LiveRoomsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        WidgetData.renderAll(context)
    }
}

/// 赛事日程小组件
class EsportsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        WidgetData.renderAll(context)
    }
}

/// 小组件刷新按钮：先用缓存立即重绘，再唤醒 Dart 侧拉最新数据。
/// App 未运行时只有缓存重绘这一步生效（用户已接受该策略）。
class WidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WidgetData.renderAll(context)
        MainActivity.requestWidgetRefresh(intent.getStringExtra("target") ?: "all")
    }
}
