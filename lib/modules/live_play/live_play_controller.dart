import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'widgets/video_player/video_controller.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/modules/live_play/danmu_merge.dart';

class LivePlayController extends StateController {
  LivePlayController({
    required this.room,
    required this.site,
  });
  final String site;

  late final Site currentSite = Sites.of(site);

  late final LiveDanmaku liveDanmaku = Sites.of(site).liveSite.getDanmaku();

  final settings = Get.find<SettingsService>();

  final messages = <LiveMessage>[].obs;

  // 控制唯一子组件
  VideoController? videoController;

  final playerKey = GlobalKey();

  final danmakuViewKey = GlobalKey();

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

  var isFirstLoad = true.obs;
  // 0 代表向上 1 代表向下
  int isNextOrPrev = 0;

  // 当前直播间信息 下一个频道或者上一个
  var currentPlayRoom = LiveRoom().obs;

  var getVideoSuccess = true.obs;

  var currentChannelIndex = 0.obs;

  var lastChannelIndex = 0.obs;

  Timer? channelTimer;

  Timer? loadRefreshRoomTimer;

  Timer? networkTimer;
  // 切换线路会添加到这个数组里面
  var isLastLine = false.obs;

  var hasError = false.obs;

  var loadTimeOut = true.obs;
  // 是否是手动切换线路
  var isActive = false.obs;

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
      videoController?.isFullscreen.value = false;
      return await Future.value(false);
    }
    return await Future.value(true);
  }

  @override
  void onClose() {
    videoController?.dispose();
    liveDanmaku.stop();
    super.onClose();
  }

  @override
  void onInit() {
    // 发现房间ID 会变化 使用静态列表ID 对比

    currentPlayRoom.value = room;
    onInitPlayerState();

    isFirstLoad.listen((p0) {
      if (isFirstLoad.value) {
        loadTimeOut.value = true;
        Timer(const Duration(seconds: 5), () {
          isFirstLoad.value = false;
          loadTimeOut.value = false;
          Timer(const Duration(seconds: 5), () {
            loadTimeOut.value = true;
          });
        });
      } else {
        // 防止闪屏
        Timer(const Duration(seconds: 2), () {
          loadTimeOut.value = false;
          Timer(const Duration(seconds: 5), () {
            loadTimeOut.value = true;
          });
        });
      }
    });

    isLastLine.listen((p0) {
      if (isLastLine.value && hasError.value && isActive.value == false) {
        // 刷新到了最后一路线 并且有错误
        SmartDialog.showToast("当前房间无法播放,正在为您每10秒刷新直播间信息...", displayTime: const Duration(seconds: 2));
        Timer(const Duration(seconds: 1), () {
          loadRefreshRoomTimer?.cancel();
          loadRefreshRoomTimer = Timer(const Duration(seconds: 10), () {
            isLastLine.value = false;
            isFirstLoad.value = true;
            restoryQualityAndLines();
            resetRoom(Sites.of(currentPlayRoom.value.platform!), currentPlayRoom.value.roomId!);
          });
        });
      } else {
        if (success.value) {
          isActive.value = false;
          loadRefreshRoomTimer?.cancel();
        }
      }
    });
    super.onInit();
  }

  void resetRoom(Site site, String roomId) async {
    success.value = false;
    hasError.value = false;
    await videoController?.destory();
    videoController = null;
    isFirstLoad.value = true;
    getVideoSuccess.value = true;
    loadTimeOut.value = true;
    Timer(const Duration(milliseconds: 200), () {
      if (lastChannelIndex.value == currentChannelIndex.value) {
        resetPlayerState();
      }
    });
  }

  Future<LiveRoom> resetPlayerState({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    int currentQuality = 0,
  }) async {
    channelTimer?.cancel();
    handleCurrentLineAndQuality(reloadDataType: reloadDataType, line: line, quality: currentQuality);
    var liveRoom = await currentSite.liveSite.getRoomDetail(
      roomId: currentPlayRoom.value.roomId!,
      platform: currentPlayRoom.value.platform!,
      title: currentPlayRoom.value.title!,
      nick: currentPlayRoom.value.nick!,
    );
    detail.value = liveRoom;
    if (liveRoom.liveStatus == LiveStatus.unknown) {
      SmartDialog.showToast("获取直播间信息失败,请按确定建重新获取", displayTime: const Duration(seconds: 2));
      getVideoSuccess.value = false;
      return liveRoom;
    }

    liveStatus.value = liveRoom.status! || liveRoom.isRecord!;
    if (liveStatus.value) {
      getPlayQualites();
      getVideoSuccess.value = true;
      if (currentPlayRoom.value.platform == Sites.iptvSite) {
        settings.addRoomToHistory(currentPlayRoom.value);
      } else {
        settings.addRoomToHistory(liveRoom);
      }
      // start danmaku server
      List<String> except = ['kuaishou', 'iptv', 'cc'];
      if (except.indexWhere((element) => element == liveRoom.platform!) == -1) {
        initDanmau();
        liveDanmaku.start(liveRoom.danmakuData);
      }
    }

    return liveRoom;
  }

  Future<LiveRoom> onInitPlayerState({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    int currentQuality = 0,
    bool active = false,
  }) async {
    isActive.value = active;
    isFirstLoad.value = true;
    var liveRoom = await currentSite.liveSite.getRoomDetail(
      roomId: currentPlayRoom.value.roomId!,
      platform: currentPlayRoom.value.platform!,
      title: currentPlayRoom.value.title!,
      nick: currentPlayRoom.value.nick!,
    );
    isLastLine.value = calcIsLastLine(reloadDataType, line) && reloadDataType == ReloadDataType.changeLine;
    if (isLastLine.value) {
      hasError.value = true;
    } else {
      hasError.value = false;
    }
    // active 代表用户是否手动切换路线 只有不是手动自动切换才会显示路线错误信息

    if (isLastLine.value && hasError.value && active == false) {
      disPoserPlayer();
      restoryQualityAndLines();
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      return liveRoom;
    } else {
      handleCurrentLineAndQuality(reloadDataType: reloadDataType, line: line, quality: currentQuality);
      detail.value = liveRoom;
      if (liveRoom.liveStatus == LiveStatus.unknown) {
        SmartDialog.showToast("获取直播间信息失败,请按确定建重新获取", displayTime: const Duration(seconds: 2));
        getVideoSuccess.value = false;
        isFirstLoad.value = false;
        return liveRoom;
      }

      liveStatus.value = liveRoom.status! || liveRoom.isRecord!;
      if (liveStatus.value) {
        getPlayQualites();
        getVideoSuccess.value = true;
        if (currentPlayRoom.value.platform == Sites.iptvSite) {
          settings.addRoomToHistory(currentPlayRoom.value);
        } else {
          settings.addRoomToHistory(liveRoom);
        }
        // start danmaku server
        List<String> except = ['kuaishou', 'iptv', 'cc'];
        if (except.indexWhere((element) => element == liveRoom.platform!) == -1) {
          initDanmau();
          liveDanmaku.start(liveRoom.danmakuData);
        }
      } else {
        isFirstLoad.value = false;
        success.value = false;
        getVideoSuccess.value = true;
        SmartDialog.showToast("当前主播未开播或主播已下播", displayTime: const Duration(seconds: 2));
        restoryQualityAndLines();
      }

      return liveRoom;
    }
  }

  bool calcIsLastLine(ReloadDataType reloadDataType, int line) {
    var lastLine = line + 1;
    if (playUrls.isEmpty) {
      return true;
    }
    if (playUrls.length == 1) {
      return true;
    }
    if (lastLine == playUrls.length - 1) {
      return true;
    }
    return false;
  }

  disPoserPlayer() {
    videoController?.dispose();
    videoController = null;
    liveDanmaku.stop();
    success.value = false;
    liveDanmaku.stop();
  }

  handleCurrentLineAndQuality({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    int quality = 0,
  }) {
    disPoserPlayer();
    try {
      if (reloadDataType == ReloadDataType.refreash) {
        restoryQualityAndLines();
      } else {
        isFirstLoad.value = false;
      }
    } catch (e) {
      restoryQualityAndLines();
      SmartDialog.showToast("切换线路失败", displayTime: const Duration(seconds: 2));
    }
  }

  restoryQualityAndLines() {
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
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "系统消息",
        message: "开始连接弹幕服务器",
        color: LiveMessageColor.white,
      ),
    );
    liveDanmaku.onMessage = (msg) {
      if (msg.type == LiveMessageType.chat) {
        if (settings.shieldList.every((element) => !msg.message.contains(element))) {
          if (!DanmuMerge().isRepeat(msg.message)) {
            DanmuMerge().add(msg.message);
            messages.add(msg);
            if (videoController != null && videoController!.hasDestory == false) {
              videoController?.sendDanmaku(msg);
            }
          }
        }
      }
    };
    liveDanmaku.onClose = (msg) {
      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: "系统消息",
          message: msg,
          color: LiveMessageColor.white,
        ),
      );
    };
    liveDanmaku.onReady = () {
      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: "系统消息",
          message: "弹幕服务器连接正常",
          color: LiveMessageColor.white,
        ),
      );
    };
  }

  void setResolution(String quality, String index) {
    if (videoController != null && videoController!.hasDestory == false) {
      videoController!.destory();
    }
    currentQuality.value = qualites.map((e) => e.quality).toList().indexWhere((e) => e == quality);
    currentLineIndex.value = int.tryParse(index) ?? 0;
    onInitPlayerState(
      reloadDataType: ReloadDataType.changeLine,
      line: currentLineIndex.value,
      currentQuality: currentQuality.value,
      active: true,
    );
  }

  /// 初始化播放器
  void getPlayQualites() async {
    try {
      var playQualites = await currentSite.liveSite.getPlayQualites(detail: detail.value!);
      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取视频信息,请按确定键重新获取", displayTime: const Duration(seconds: 2));
        getVideoSuccess.value = false;
        isFirstLoad.value = false;
        success.value = false;
        return;
      }
      qualites.value = playQualites;
      // 第一次加载 使用系统默认线路
      if (isFirstLoad.value) {
        int qualityLevel = settings.resolutionsList.indexOf(settings.preferResolution.value);
        if (qualityLevel == 0) {
          //最高
          currentQuality.value = 0;
        } else if (qualityLevel == settings.resolutionsList.length - 1) {
          //最低
          currentQuality.value = playQualites.length - 1;
        } else {
          //中间值
          int middle = (playQualites.length / 2).floor();
          currentQuality.value = middle;
        }
      }
      isFirstLoad.value = false;
      getPlayUrl();
    } catch (e) {
      SmartDialog.showToast("无法读取视频信息,请按确定键重新获取");
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      success.value = false;
    }
  }

  void getPlayUrl() async {
    var playUrl =
        await currentSite.liveSite.getPlayUrls(detail: detail.value!, quality: qualites[currentQuality.value]);
    if (playUrl.isEmpty) {
      SmartDialog.showToast("无法读取播放地址,请按确定键重新获取", displayTime: const Duration(seconds: 2));
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
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
        "referer": "https://live.bilibili.com",
        "user-agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36 Edg/115.0.1901.188"
      };
    } else if (currentSite.id == Sites.huyaSite) {
      headers = {
        "Referer": "https://www.huya.com",
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0"
      };
    }
    videoController = VideoController(
      playerKey: playerKey,
      room: detail.value!,
      datasourceType: 'network',
      datasource: playUrls.value[currentLineIndex.value],
      allowScreenKeepOn: settings.enableScreenKeepOn.value,
      fullScreenByDefault: settings.enableFullScreenDefault.value,
      autoPlay: true,
      headers: headers,
      qualiteName: qualites[currentQuality.value].quality,
      currentLineIndex: currentLineIndex.value,
      currentQuality: currentQuality.value,
    );
    success.value = true;

    networkTimer?.cancel();
    networkTimer = Timer(const Duration(seconds: 10), () async {
      if (videoController != null && videoController!.hasDestory == false) {
        final connectivityResults = await Connectivity().checkConnectivity();
        if (!connectivityResults.contains(ConnectivityResult.none)) {
          if (!videoController!.isActivePause.value && videoController!.isPlaying.value == false) {
            videoController!.refresh();
          }
        }
      }
    });
  }

  openNaviteAPP() async {
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
}
