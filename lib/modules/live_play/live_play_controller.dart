import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:floating/floating.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/iptv/src/general_utils_object_extension.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/danmu_merge.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/modules/util/rx_util.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'widgets/video_player/video_controller.dart';

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

  int loopCount = 0;

  int lastExitTime = 0;

  /// 双击退出Flag
  bool doubleClickExit = false;

  /// 双击退出Timer
  Timer? doubleClickTimer;

  var isFirstLoad = true.obs;

  /// 是否在加载视频
  var isLoadingVideo = true.obs;

  // 0 代表向上 1 代表向下
  int isNextOrPrev = 0;

  // 当前直播间信息 下一个频道或者上一个
  var currentPlayRoom = LiveRoom().obs;

  var getVideoSuccess = true.obs;

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

  /// 是否 关注
  var isFavorite = false.obs;
  /// 在线人数
  var online = "".obs;
  /// 是否全屏
  final isFullscreen = false.obs;
  /// PIP画中画
  final pip = Floating();
  StreamSubscription? _pipSubscription;

  /// 释放一些系统状态
  Future resetSystem() async {
    _pipSubscription?.cancel();
    // pip.dispose();
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );

    await videoController?.setPortraitOrientation();
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      // 亮度重置,桌面平台可能会报错,暂时不处理桌面平台的亮度
      try {
        await videoController?.brightnessController.resetScreenBrightness();
      } catch (e) {
        CoreLog.error(e);
      }
    }

    await WakelockPlus.disable();
  }

  Future enablePIP() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (await pip.isPipAvailable == false) {
      SmartDialog.showToast("设备不支持小窗播放");
      return;
    }

    //关闭并清除弹幕
    if (videoController?.videoPlayer.isPipMode.value == true) {
      videoController?.hideDanmaku.value = true;
    }
    videoController?.danmakuController.reset(0);
    // //关闭控制器
    // showControlsState.value = false;

    //监听事件
    var isVertical = videoController?.videoPlayer.isVertical.value ?? false;
    Rational ratio = const Rational.landscape();
    if (isVertical) {
      ratio = const Rational.vertical();
    } else {
      ratio = const Rational.landscape();
    }
    await pip.enable(ImmediatePiP());

    _pipSubscription ??= pip.pipStatusStream.listen((event) {
      if (event == PiPStatus.disabled) {
        // danmakuController?.clear();
        // showDanmakuState.value = danmakuStateBeforePIP;
      }
      CoreLog.w(event.toString());
    });
  }

  Future<bool> onBackPressed() async {
    if (videoController!.showSettting.value) {
      videoController?.showSettting.toggle();
      return await Future.value(false);
    }
    if (videoController!.videoPlayer.isFullscreen.value) {
      videoController?.exitFull();
      return await Future.value(false);
    }
    bool doubleExit = Get.find<SettingsService>().doubleExit.value;
    if (!doubleExit) {
      disPoserPlayer();
      return Future.value(true);
    }
    int nowExitTime = DateTime.now().millisecondsSinceEpoch;
    if (nowExitTime - lastExitTime > 1000) {
      lastExitTime = nowExitTime;
      SmartDialog.showToast(S.current.double_click_to_exit);
      return await Future.value(false);
    }
    disPoserPlayer();
    return await Future.value(true);
  }

  @override
  void onInit() {
    super.onInit();
    // 发现房间ID 会变化 使用静态列表ID 对比
    CoreLog.d('onInit');

    currentPlayRoom.value = room;
    online.value = room.watching ?? "0";
    onInitPlayerState(firstLoad: true);
    isFirstLoad.listen((p0) {
      if (isFirstLoad.value) {
        loadTimeOut.value = true;
        Timer(const Duration(seconds: 8), () {
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
        SmartDialog.showToast("当前房间无法播放,正在为您刷新直播间信息...",
            displayTime: const Duration(seconds: 2));
        isLastLine.value = false;
        isFirstLoad.value = true;
        restoryQualityAndLines();
        resetRoom(Sites.of(currentPlayRoom.value.platform!),
            currentPlayRoom.value.roomId!);
      } else {
        if (success.value) {
          isActive.value = false;
          loadRefreshRoomTimer?.cancel();
        }
      }
    });

    getVideoSuccess.listen((p0) {
      isLoadingVideo.value = true;
      if(p0) {
        isLoadingVideo.value = false;
      }
    });
  }

  void resetRoom(Site site, String roomId) async {
    success.value = false;
    hasError.value = false;
    if (videoController != null && !videoController!.hasDestory) {
      await videoController?.destory();
      videoController = null;
    }

    isFirstLoad.value = true;
    getVideoSuccess.value = false;
    loadTimeOut.value = false;
    isLoadingVideo.value = true;
    Timer(const Duration(milliseconds: 2000), () {
      // log('resetRoom', name: 'LivePlayController');
      CoreLog.d('resetRoom');
      onInitPlayerState(firstLoad: true);
    });
  }

  Future<LiveRoom> onInitPlayerState({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    bool active = false,
    bool firstLoad = false,
  }) async {
    isActive.value = active;
    isFirstLoad.value = firstLoad;
    isLoadingVideo.value = true;
    var liveRoom = currentPlayRoom.value;
    // 只有第一次需要重新配置信息
    if (isFirstLoad.value) {
      liveRoom = await currentSite.liveSite.getRoomDetail(
        roomId: currentPlayRoom.value.roomId!,
        platform: currentPlayRoom.value.platform!,
        title: currentPlayRoom.value.title!,
        nick: currentPlayRoom.value.nick!,
      );
      isFavorite.value = settings.isFavorite(liveRoom);
    }
    isLastLine.value =
        calcIsLastLine(line) && reloadDataType == ReloadDataType.changeLine;
    if (isLastLine.value) {
      hasError.value = true;
    } else {
      hasError.value = false;
    }
    // active 代表用户是否手动切换路线 只有不是手动自动切换才会显示路线错误信息
    if (isLastLine.value && hasError.value && active == false) {
      restoryQualityAndLines();
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      success.value = false;
      return liveRoom;
    } else {
      handleCurrentLineAndQuality(
          reloadDataType: reloadDataType, line: line, active: active);
      detail.value = liveRoom;
      online.value = liveRoom.watching ?? "0";
      if (liveRoom.liveStatus == LiveStatus.unknown) {
        SmartDialog.showToast("获取直播间信息失败,请按重新获取",
            displayTime: const Duration(seconds: 2));
        getVideoSuccess.value = false;
        isFirstLoad.value = false;
        return liveRoom;
      }

      // 开始播放
      liveStatus.value = detail.value!.liveStatus != LiveStatus.unknown && detail.value!.liveStatus != LiveStatus.offline;
      if (liveStatus.value) {
        await getPlayQualites();
        getVideoSuccess.value = true;
        if (currentPlayRoom.value.platform == Sites.iptvSite) {
          settings.addRoomToHistory(currentPlayRoom.value);
        } else {
          settings.addRoomToHistory(liveRoom);
        }
        // start danmaku server
        List<String> except = ['iptv'];
        // 重新刷新才重新加载弹幕
        if ( firstLoad
            && except.indexWhere((element) => element == liveRoom.platform! ) == -1
            && liveRoom.danmakuData != null
        ) {
          initDanmau();
          liveDanmaku.start(liveRoom.danmakuData);
        }
      } else {
        isFirstLoad.value = false;
        success.value = false;
        getVideoSuccess.value = true;
        SmartDialog.showToast("当前主播未开播或主播已下播",
            displayTime: const Duration(seconds: 2));
        messages.add(
          LiveMessage(
            type: LiveMessageType.chat,
            userName: "系统消息",
            message: "当前主播未开播或主播已下播",
            color: Colors.redAccent,
          ),
        );
        restoryQualityAndLines();
      }

      return liveRoom;
    }
  }

  bool calcIsLastLine(int line) {
    var lastLine = line + 1;
    if (playUrls.isEmpty) {
      return true;
    }
    if (playUrls.length == 1) {
      return true;
    }
    if (lastLine == playUrls.length) {
      return true;
    }
    return false;
  }

  disPoserPlayer() {
    videoController?.dispose();
    videoController = null;
    liveDanmaku.stop();
    success.value = false;
    resetSystem();
  }

  handleCurrentLineAndQuality({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    bool active = false,
  }) {
    if (reloadDataType == ReloadDataType.changeLine && active == false) {
      if (line == playUrls.length - 1) {
        currentLineIndex.value = 0;
      } else {
        currentLineIndex.value = currentLineIndex.value + 1;
      }
      loopCount++;
      isFirstLoad.value = false;
    }
  }

  restoryQualityAndLines() {
    // playUrls.value = [];
    currentLineIndex.value = 0;
    // qualites.value = [];
    loopCount = 0;
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
          color: Colors.grey,
        ),
      );
    }
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "系统消息",
        message: "开始连接弹幕服务器",
        color: Colors.blueGrey,
      ),
    );
    liveDanmaku.onMessage = (msg) {
      if (msg.type == LiveMessageType.chat) {
        if (settings.shieldList
            .every((element) => !msg.message.contains(element))) {
          if (!DanmuMerge().isRepeat(msg.message)) {
            DanmuMerge().add(msg.message);
            messages.add(msg);
            if (videoController != null &&
                videoController!.hasDestory == false) {
              videoController?.sendDanmaku(msg);
            }
          }
        }
      } else if (msg.type == LiveMessageType.online) {
        /// 在线人数
        var onlineNum = msg.data as int;
        var numStr = onlineNum.toString();
        // CoreLog.d(online.toString());
        if(online.value != numStr) {
          online.value = onlineNum.toString();
          // detail.value?.watching = online.toString();
          // currentPlayRoom.value.watching = online.toString();
        }
      }
    };
    liveDanmaku.onClose = (msg) {
      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: "系统消息",
          message: msg,
          color: Colors.blueGrey,
        ),
      );
    };
    liveDanmaku.onReady = () {
      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: "系统消息",
          message: "弹幕服务器连接正常",
          color: Colors.blueGrey,
        ),
      );
    };
  }

  /// 选择直播路线
  void setResolution(String quality, String index) {
    CoreLog.d("setResolution");
    CoreLog.d("quality: $quality \t index: $index");
    isLoadingVideo.value = true;
    if (videoController != null && videoController!.hasDestory == false) {
      // videoController!.destory();
      videoController!.pause();
    }

    currentQuality.value =
        qualites.map((e) => e.quality).toList().indexWhere((e) => e == quality);
    currentLineIndex.value = int.tryParse(index) ?? 0;
    onInitPlayerState(
      reloadDataType: ReloadDataType.changeLine,
      line: currentLineIndex.value,
      active: true,
      firstLoad: false,
    );
  }

  /// 初始化播放器
  Future<void> getPlayQualites() async {
    try {
      var playQualites = qualites.value;
      if (isFirstLoad.value) {
        playQualites =
            await currentSite.liveSite.getPlayQualites(detail: detail.value!);
      }
      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取视频信息,请重新获取",
            displayTime: const Duration(seconds: 2));
        getVideoSuccess.value = false;
        isFirstLoad.value = false;
        success.value = false;
        return;
      }
      qualites.value = playQualites;
      // 第一次加载 使用系统默认线路
      if (isFirstLoad.value) {
        int qualityLevel =
            settings.resolutionsList.indexOf(settings.preferResolution.value);
        qualityLevel = math.max(0, qualityLevel);
        qualityLevel = math.min(playQualites.length - 1, qualityLevel);

        // fix 清晰度判断逻辑, 根据名字匹配
        for (var i = 0; i < playQualites.length; i++) {
          var playQuality = playQualites[i];
          if (playQuality.quality.contains(settings.preferResolution.value)) {
            qualityLevel = i;
            break;
          }
        }
        currentQuality.value = qualityLevel;
      }
      isFirstLoad.value = false;
      getPlayUrl();
    } catch (e) {
      CoreLog.error(e);
      SmartDialog.showToast("无法读取视频信息,请重新获取");
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      success.value = false;
    }
  }

  Future<void> getPlayUrl() async {
    var quality = qualites[currentQuality.value];
    var playUrlList = quality.playUrlList;
    if (playUrlList.isNullOrEmpty) {
      playUrlList = await currentSite.liveSite.getPlayUrls(
          detail: detail.value!, quality: qualites[currentQuality.value]);
      quality.playUrlList = playUrlList;
    }
    if (playUrlList.isNullOrEmpty) {
      SmartDialog.showToast("无法读取播放地址,请重新获取",
          displayTime: const Duration(seconds: 2));
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      success.value = false;
      return;
    }
    playUrls.value = playUrlList;
    // log("playUrlList : ${playUrlList}", name: runtimeType.toString());
    setPlayer();
  }

  Map<String, String> getUrlHeaders(){
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
        "sec-ch-ua":
        '"Not A(Brand";v="99", "Google Chrome";v="121", "Chromium";v="121"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"macOS"',
        "sec-fetch-dest": "document",
        "sec-fetch-mode": "navigate",
        "sec-fetch-site": "none",
        "sec-fetch-user": "?1",
        "upgrade-insecure-requests": "1",
        "user-agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
        "referer": "https://live.bilibili.com"
      };
    } else if (currentSite.id == Sites.huyaSite) {
      headers = {
        "Referer": "https://www.huya.com",
        "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0"
      };
    }
    return headers;
  }

  void setPlayer() async {
    var headers = getUrlHeaders();
    try {
      // await videoController?.pause();
    } catch (e){
      // [Player] has been disposed
      videoController?.dispose();
      videoController?.hasDestory = true;
      // log(e.toString());
      CoreLog.error(e);
    }
    // log("playUrls ${playUrls.value}", name: runtimeType.toString());
    // log("currentLineIndex : $currentLineIndex", name: runtimeType.toString());
    // log("current play url : ${playUrls.value[currentLineIndex.value]}", name: runtimeType.toString());
    if(videoController == null || videoController!.hasDestory){
      videoController = VideoController(
        playerKey: playerKey,
        room: detail.value!,
        datasourceType: 'network',
        datasource: playUrls.value[currentLineIndex.value],
        allowScreenKeepOn: settings.enableScreenKeepOn.value,
        allowBackgroundPlay: settings.enableBackgroundPlay.value,
        fullScreenByDefault: settings.enableFullScreenDefault.value,
        autoPlay: true,
        headers: headers,
        qualiteName: qualites[currentQuality.value].quality,
        currentLineIndex: currentLineIndex.value,
        currentQuality: currentQuality.value,
      );
      videoController?.videoPlayer.isFullscreen.listen((e) {
        isFullscreen.updateValueNotEquate(e);
      });
    } else {
      videoController?.datasource = playUrls.value[currentLineIndex.value];
      videoController?.qualiteName = qualites[currentQuality.value].quality;
      videoController?.currentLineIndex = currentLineIndex.value;
      videoController?.currentQuality = currentQuality.value;
      videoController?.setDataSource(playUrls.value[currentLineIndex.value], headers);
      // videoController?.initVideoController();
      // videoController?.play();
    }

    videoController?.datasource = playUrls.value[currentLineIndex.value];
    videoController?.qualiteName = qualites[currentQuality.value].quality;
    videoController?.currentLineIndex = currentLineIndex.value;
    videoController?.currentQuality = currentQuality.value;
    videoController?.setDataSource(playUrls.value[currentLineIndex.value], headers);

    success.value = true;

    networkTimer?.cancel();
    networkTimer = Timer(const Duration(seconds: 10), () async {
      if (videoController != null && videoController!.hasDestory == false) {
        final connectivityResults = await Connectivity().checkConnectivity();
        if (!connectivityResults.contains(ConnectivityResult.none)) {
          if ( videoController?.isActivePause.value != true &&
              videoController?.videoPlayer.isPlaying.value != true) {
            CoreLog.d("videoController refresh");
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
      CoreLog.d("cc_user_id :${detail.value!.userId.toString()}");
      naviteUrl =
          "cc://join-room/${detail.value?.roomId}/${detail.value?.userId}/";
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

  @override
  void onClose() {
    disPoserPlayer();
    super.onClose();
  }

  @override
  void dispose() {
    disPoserPlayer();
    super.dispose();
  }
}
