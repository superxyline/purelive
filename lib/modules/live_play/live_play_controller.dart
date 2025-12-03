import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/huya_site.dart';
import 'widgets/video_player/video_controller.dart';
import 'package:pure_live/plugins/emoji_manager.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/player/switchable_global_player.dart';

enum VideoMode { normal, widescreen, fullscreen }

class LivePlayController extends StateController {
  LivePlayController({required this.room, required this.site});
  final String site;
  final StopWatchTimer _stopWatchTimer = StopWatchTimer(mode: StopWatchMode.countDown); // Create instance.
  late final Site currentSite = Sites.of(site);
  late final LiveDanmaku liveDanmaku = Sites.of(site).liveSite.getDanmaku();

  final settings = Get.find<SettingsService>();

  final messages = <LiveMessage>[].obs;

  // 控制唯一子组件
  VideoController? videoController;

  final LiveRoom room;

  Rx<LiveRoom?> detail = Rx<LiveRoom?>(LiveRoom());

  final success = false.obs;

  var liveStatus = false.obs;

  Map<String, List<String>> liveStream = {};

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  final currentQuality = 0.obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  /// 当前线路
  final currentLineIndex = 0.obs;

  int lastExitTime = 0;

  /// 双击退出Flag
  bool doubleClickExit = false;

  /// 双击退出Timer
  Timer? doubleClickTimer;

  // 当前直播间信息 下一个频道或者上一个
  var currentPlayRoom = LiveRoom().obs;

  var closeTimes = 240.obs;

  var closeTimeFlag = false.obs;

  final screenMode = VideoMode.normal.obs;

  bool hasUseDefaultResolution = false;

  Future<bool> onBackPressed() async {
    if (videoController!.showSettting.value) {
      videoController?.showSettting.toggle();
      return await Future.value(false);
    }
    if (videoController!.isFullscreen.value) {
      videoController?.exitFullScreen();
      return await Future.value(false);
    }
    bool doubleExit = Get.find<SettingsService>().doubleExit.value;
    if (!doubleExit) {
      return Future.value(true);
    }
    int nowExitTime = DateTime.now().millisecondsSinceEpoch;
    if (nowExitTime - lastExitTime > 1000) {
      lastExitTime = nowExitTime;
      SmartDialog.showToast(S.current.double_click_to_exit);
      return await Future.value(false);
    }
    return await Future.value(true);
  }

  @override
  void onClose() {
    SwitchableGlobalPlayer().stop();
    super.onClose();
  }

  @override
  void dispose() {
    SwitchableGlobalPlayer().stop();
    super.dispose();
  }

  @override
  void onInit() {
    super.onInit();
    currentPlayRoom.value = room;
    onInitPlayerState();
    EmojiManager().preload(site);
    debounce(closeTimeFlag, (callback) {
      if (closeTimeFlag.isTrue) {
        _stopWatchTimer.onStopTimer();
        _stopWatchTimer.setPresetMinuteTime(closeTimes.value, add: false);
        _stopWatchTimer.onStartTimer();
      } else {
        _stopWatchTimer.onStopTimer();
      }
    }, time: 1.seconds);

    debounce(closeTimes, (callback) {
      if (closeTimeFlag.isTrue) {
        _stopWatchTimer.onStopTimer();
        _stopWatchTimer.setPresetMinuteTime(closeTimes.value, add: false);
        _stopWatchTimer.onStartTimer();
      } else {
        _stopWatchTimer.onStopTimer();
      }
    }, time: 1.seconds);
    _stopWatchTimer.fetchEnded.listen((value) {
      _stopWatchTimer.onStopTimer();
      exit(0);
    });
  }

  void resetRoom(Site site, String roomId) async {
    success.value = false;
    if (videoController != null) {
      await videoController?.destory();
      videoController = null;
    }
    Timer(const Duration(milliseconds: 4000), () {
      if (Get.currentRoute == '/live_play') {
        onInitPlayerState();
      }
    });
  }

  Future<LiveRoom> onInitPlayerState({ReloadDataType reloadDataType = ReloadDataType.refreash, int line = 0}) async {
    var liveRoom = await currentSite.liveSite.getRoomDetail(
      roomId: currentPlayRoom.value.roomId!,
      platform: currentPlayRoom.value.platform!,
    );
    if (currentSite.id == Sites.iptvSite) {
      liveRoom = liveRoom.copyWith(title: currentPlayRoom.value.title!, nick: currentPlayRoom.value.nick!);
    }
    handleCurrentLineAndQuality(reloadDataType: reloadDataType, line: line);
    detail.value = liveRoom;
    if (liveRoom.liveStatus == LiveStatus.unknown) {
      if (Get.currentRoute == '/live_play') {
        SmartDialog.showToast("获取直播间信息失败,请重新获取", displayTime: const Duration(seconds: 2));
      }
      return liveRoom;
    }

    // 开始播放
    liveStatus.value = liveRoom.status! || liveRoom.isRecord!;
    if (liveStatus.value) {
      await getPlayQualites();
      if (currentPlayRoom.value.platform == Sites.iptvSite) {
        settings.addRoomToHistory(currentPlayRoom.value);
      } else {
        settings.addRoomToHistory(liveRoom);
      }
      // start danmaku server
      List<String> except = ['kuaishou', 'iptv', 'cc'];
      if (except.indexWhere((element) => element == liveRoom.platform!) == -1) {
        liveDanmaku.stop();
        initDanmau();
        liveDanmaku.start(liveRoom.danmakuData);
      }
    } else {
      success.value = false;
      if (liveRoom.liveStatus == LiveStatus.banned) {
        SmartDialog.showToast("服务器错误,请稍后获取", displayTime: const Duration(seconds: 2));
      } else {
        SmartDialog.showToast("当前主播未开播或主播已下播", displayTime: const Duration(seconds: 2));
      }
      restoryQualityAndLines();
    }

    return liveRoom;
  }

  void setNormalScreen() {
    screenMode.value = VideoMode.normal;
  }

  void setWidescreen() {
    screenMode.value = VideoMode.widescreen;
  }

  void setFullScreen() {
    screenMode.value = VideoMode.fullscreen;
  }

  void handleCurrentLineAndQuality({ReloadDataType reloadDataType = ReloadDataType.refreash, int line = 0}) {
    if (reloadDataType == ReloadDataType.changeLine) {
      if (line == playUrls.length - 1) {
        currentLineIndex.value = 0;
      } else {
        currentLineIndex.value = currentLineIndex.value + 1;
      }
    }
  }

  void restoryQualityAndLines() {
    playUrls.value = [];
    currentLineIndex.value = 0;
    qualites.value = [];
    currentQuality.value = 0;
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    if (detail.value!.isRecord!) {
      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: "系统消息",
          message: "当前主播未开播，正在轮播录像",
          color: LiveMessageColor.white,
        ),
      );
    }
    messages.add(
      LiveMessage(type: LiveMessageType.chat, userName: "系统消息", message: "开始连接弹幕服务器", color: LiveMessageColor.white),
    );
    liveDanmaku.onMessage = (msg) {
      if (msg.type == LiveMessageType.chat) {
        if (settings.shieldList.every((element) => !msg.message.contains(element))) {
          messages.add(msg);
          if (videoController != null) {
            videoController?.sendDanmaku(msg);
          }
        }
      }
    };
    liveDanmaku.onClose = (msg) {
      messages.add(
        LiveMessage(type: LiveMessageType.chat, userName: "系统消息", message: msg, color: LiveMessageColor.white),
      );
    };
    liveDanmaku.onReady = () {
      messages.add(
        LiveMessage(type: LiveMessageType.chat, userName: "系统消息", message: "弹幕服务器连接正常", color: LiveMessageColor.white),
      );
    };
  }

  void setResolution(String quality, String index) {
    if (videoController != null) {
      videoController!.destory();
    }
    currentQuality.value = qualites.map((e) => e.quality).toList().indexWhere((e) => e == quality);
    currentLineIndex.value = int.tryParse(index) ?? 0;
    onInitPlayerState(reloadDataType: ReloadDataType.changeLine, line: currentLineIndex.value);
  }

  /// 初始化播放器
  Future<void> getPlayQualites() async {
    try {
      var playQualites = await currentSite.liveSite.getPlayQualites(detail: detail.value!);
      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取视频信息,请重新获取", displayTime: const Duration(seconds: 2));
        success.value = false;
        return;
      }
      qualites.value = playQualites;
      settings.preferResolution.value = qualites[currentQuality.value].quality;
      if (!hasUseDefaultResolution) {
        int qualityLevel = settings.resolutionsList.indexOf(settings.preferResolution.value);
        if (qualityLevel == 0) {
          currentQuality.value = 0;
        } else if (qualityLevel == settings.resolutionsList.length - 1) {
          currentQuality.value = playQualites.length - 1;
        } else {
          int middle = (playQualites.length / 2).floor();
          currentQuality.value = middle;
        }
        hasUseDefaultResolution = true;
      }

      getPlayUrl();
    } catch (e) {
      SmartDialog.showToast("无法读取视频信息,请重新获取");
      success.value = false;
    }
  }

  Future<void> getPlayUrl() async {
    var playUrl = await currentSite.liveSite.getPlayUrls(
      detail: detail.value!,
      quality: qualites[currentQuality.value],
    );
    if (playUrl.isEmpty) {
      SmartDialog.showToast("无法读取播放地址,请重新获取", displayTime: const Duration(seconds: 2));
      success.value = false;
      return;
    }
    playUrls.value = playUrl;
    setPlayer();
  }

  void setPlayer() async {
    Map<String, String> headers = {};
    if (currentSite.id == Sites.bilibiliSite) {
      headers = {
        "cookie": settings.bilibiliCookie.value,
        "authority": "api.bilibili.com",
        "accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "accept-language": "zh-CN,zh;q=0.9",
        "cache-control": "no-cache",
        "dnt": "1",
        "pragma": "no-cache",
        "sec-ch-ua": '"Not A(Brand";v="99", "Google Chrome";v="121", "Chromium";v="121"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"macOS"',
        "sec-fetch-dest": "document",
        "sec-fetch-mode": "navigate",
        "sec-fetch-site": "none",
        "sec-fetch-user": "?1",
        "upgrade-insecure-requests": "1",
        "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
        "referer": "https://live.bilibili.com",
      };
    } else if (currentSite.id == Sites.huyaSite) {
      var ua = await HuyaSite().getHuYaUA();
      headers = {"user-agent": ua, "origin": "https://www.huya.com"};
    }
    videoController = VideoController(
      room: detail.value!,
      datasourceType: 'network',
      videoPlayerIndex: settings.videoPlayerIndex.value,
      datasource: playUrls.value[currentLineIndex.value],
      allowScreenKeepOn: settings.enableScreenKeepOn.value,
      allowBackgroundPlay: settings.enableBackgroundPlay.value,
      autoPlay: true,
      headers: headers,
      qualiteName: qualites[currentQuality.value].quality,
      currentLineIndex: currentLineIndex.value,
      currentQuality: currentQuality.value,
    );
    success.value = true;
  }

  Future<void> openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site == Sites.bilibiliSite) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site == Sites.douyinSite) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site == Sites.huyaSite) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site == Sites.douyuSite) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    } else if (site == Sites.ccSite) {
      log(detail.value!.userId.toString(), name: "cc_user_id");
      naviteUrl = "cc://join-room/${detail.value?.roomId}/${detail.value?.userId}/";
      webUrl = "https://cc.163.com/${detail.value?.roomId}";
    } else if (site == Sites.kuaishouSite) {
      naviteUrl =
          "kwai://liveaggregatesquare?liveStreamId=${detail.value?.link}&recoStreamId=${detail.value?.link}&recoLiveStreamId=${detail.value?.link}&liveSquareSource=28&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE";
      webUrl = "https://live.kuaishou.com/u/${detail.value?.roomId}";
    }
    try {
      if (Platform.isAndroid) {
        await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void switchRoom(LiveRoom room) async {
    success.value = false;
    messages.clear();
    if (videoController != null) {
      await videoController?.destory();
      videoController = null;
    }
    hasUseDefaultResolution = false;
    currentPlayRoom.value = room;
    onInitPlayerState();
  }
}
