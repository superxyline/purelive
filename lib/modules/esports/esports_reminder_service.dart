import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/esports/esports_match.dart';
import 'package:pure_live/modules/esports/favorite_match_controller.dart';
import 'package:pure_live/modules/esports/esports_service.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

/// 赛事提醒服务：在关注的赛事开始前（提前分钟数可在设置中调整，默认10分钟）通过通知提醒
class EsportsReminderService {
  static final EsportsReminderService _instance = EsportsReminderService._internal();
  factory EsportsReminderService() => _instance;
  EsportsReminderService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Map<String, DateTime> _scheduledReminders = {};

  /// 初始化通知服务
  Future<void> init() async {
    if (_initialized) return;
    
    tz.initializeTimeZones();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    
    await _notifications.initialize(settings: initSettings);
    
    await _createNotificationChannel();
    
    _initialized = true;
  }

  /// 创建Android通知渠道
  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      'esports_reminder',
      '赛事提醒',
      description: '关注的赛事开始前提醒',
      importance: Importance.high,
    );
    
    await _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// 处理通知点击跳转
  void _handleNotificationTap(String gameKey) {
    if (gameKey == 'cs') {
      _navigateToCSLiveRoom();
    } else {
      Get.offAllNamed(RoutePath.kInitial);
    }
  }

  /// 跳转到CS直播间
  void _navigateToCSLiveRoom() {
    Get.offAllNamed(RoutePath.kInitial);
  }

  /// 为关注的赛事设置提醒
  Future<void> scheduleReminders() async {
    if (!_initialized) await init();
    
    await _cancelAllReminders();
    
    final favController = Get.find<FavoriteMatchController>();
    final favoriteIds = favController.favoriteMatchIds;
    
    if (favoriteIds.isEmpty) return;
    
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 8));
    
    try {
      final service = EsportsService();
      final matches = await service.fetchMatches(from: from, to: to);
      
      for (final match in matches) {
        if (!favoriteIds.contains(match.matchId)) continue;

        final leadMinutes = SettingsService.to.app.esportsReminderLeadMinutes.v;
        final reminderTime = match.startDateTime.subtract(Duration(minutes: leadMinutes));

        if (reminderTime.isAfter(now)) {
          await _scheduleReminder(match, reminderTime, leadMinutes);
        }
      }
    } catch (e) {
      // 静默失败
    }
  }

  /// 设置单个赛事提醒
  Future<void> _scheduleReminder(EsportsMatch match, DateTime reminderTime, int leadMinutes) async {
    final gameName = _getGameName(match.gameKey);
    final title = '$gameName 赛事即将开始';
    final body = '${match.seriesName} 将在$leadMinutes分钟后开始';
    
    final payload = '${match.gameKey}_${match.matchId}_${match.seriesName}';
    
    final tzScheduledDate = tz.TZDateTime.from(reminderTime, tz.local);
    
    await _notifications.zonedSchedule(
      id: match.matchId.hashCode,
      title: title,
      body: body,
      scheduledDate: tzScheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'esports_reminder',
          '赛事提醒',
          channelDescription: '关注的赛事开始前提醒',
          importance: Importance.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
    
    _scheduledReminders[match.matchId] = reminderTime;
  }

  /// 取消所有提醒
  Future<void> _cancelAllReminders() async {
    await _notifications.cancelAll();
    _scheduledReminders.clear();
  }

  /// 获取游戏名称
  String _getGameName(String gameKey) {
    switch (gameKey) {
      case 'cs':
        return 'CS';
      case 'lol':
        return '英雄联盟';
      case 'valorant':
        return 'VALORANT';
      case 'dota2':
        return 'DOTA2';
      default:
        return '电竞';
    }
  }

  bool hasScheduledReminder(String matchId) {
    return _scheduledReminders.containsKey(matchId);
  }

  int get scheduledReminderCount => _scheduledReminders.length;
}
