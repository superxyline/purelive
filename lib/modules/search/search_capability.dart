import 'package:pure_live/core/sites.dart';

enum NativeSearchCoverage { liveOnly, liveAndOffline, localChannels, webOnly }

class LiveSearchCapability {
  const LiveSearchCapability({required this.coverage, required this.supportsPagination});

  final NativeSearchCoverage coverage;
  final bool supportsPagination;

  bool get supportsNativeSearch => coverage != NativeSearchCoverage.webOnly;
  bool get mayIncludeOffline => coverage == NativeSearchCoverage.liveAndOffline;
}

class LiveSearchCapabilities {
  const LiveSearchCapabilities._();

  static const Map<String, LiveSearchCapability> _byPlatform = {
    Sites.bilibiliSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveAndOffline, supportsPagination: true),
    Sites.douyuSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveAndOffline, supportsPagination: true),
    Sites.huyaSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveOnly, supportsPagination: true),
    Sites.douyinSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveOnly, supportsPagination: true),
  };

  static const LiveSearchCapability _unknown = LiveSearchCapability(
    coverage: NativeSearchCoverage.webOnly,
    supportsPagination: false,
  );

  static LiveSearchCapability forPlatform(String id) => _byPlatform[id.toLowerCase()] ?? _unknown;
}
