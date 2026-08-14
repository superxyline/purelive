
class FFmpegCommandBuilder {
  static String _quote(String value) {
    final escaped = value.replaceAll('"', r'\"');
    return '"$escaped"';
  }

  /// 本地音频流 HTTP Server
  static String buildAudioStreamCommand({
    required String remoteStreamUrl,
    required int port,
    int rwTimeout = 15,
    Map<String, String>? headers,
  }) {
    final ua = headers?['user-agent'];
    final headerStr = _buildHeader(headers);

    final rwTimeoutMicro = (rwTimeout * 1000000).clamp(0, 2147483647);

    final args = <String>[
      // 基础
      '-hide_banner',
      '-loglevel', 'info',

      // 重连
      '-reconnect', '1',
      '-reconnect_streamed', '1',
      '-reconnect_delay_max', '10',
      '-reconnect_at_eof', '1',

      // 网络
      '-rw_timeout', rwTimeoutMicro.toString(),

      // UA
      if (ua != null && ua.isNotEmpty) ...['-user_agent', _quote(ua)],

      // Headers
      if (headerStr.isNotEmpty) ...['-headers', _quote(headerStr)],
      // 输入流
      '-i', remoteStreamUrl,
      '-map', '0:a',
      '-vn',
      '-acodec', 'copy',
      '-listen', '1',
      // 输出 MPEGTS HTTP Server
      '-f', 'mpegts',
      'http://0.0.0.0:$port/live.ts',
    ];

    return args.join(' ');
  }

  static String _buildHeader(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    final lines = headers.entries
        .where((e) => e.key.toLowerCase() != 'user-agent')
        .map((e) => '${e.key}: ${e.value}')
        .join('\r\n');
    return lines.isEmpty ? '' : '$lines\r\n';
  }
}
