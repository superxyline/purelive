import 'dart:io';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/update.dart';
import 'package:url_launcher/url_launcher.dart';

class NoNewVersionDialog extends StatelessWidget {
  const NoNewVersionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).check_update),
      content: Text(S.of(context).no_new_version_info),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class NewVersionDialog extends StatelessWidget {
  const NewVersionDialog({super.key, this.entry});

  final OverlayEntry? entry;

  @override
  Widget build(BuildContext context) {
    final apkUrl =
        '${VersionUtil.projectUrl}/releases/download/v${VersionUtil.latestVersion}/app-armeabi-v7a-release.apk';
    final windowsExecutableUrl =
        '${VersionUtil.projectUrl}/releases/download/v${VersionUtil.latestVersion}/PureLive-${VersionUtil.version}-windows-x64-setup.exe';

    return AlertDialog(
      title: Text(S.of(context).check_update),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(S.of(context).new_version_info(VersionUtil.latestVersion)),
          const SizedBox(height: 20),
          Text(VersionUtil.latestUpdateLog, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              if (entry != null) {
                entry!.remove();
              } else {
                Navigator.pop(context);
              }
              launchUrl(Uri.parse('https://github.com/liuchuancong/pure_live'), mode: LaunchMode.externalApplication);
            },
            child: const Text('本软件开源免费'),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.start,
      actions: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.start,
                spacing: 10,
                runSpacing: 10,
                children: [
                  ...getMirrorUrls(Platform.isWindows ? windowsExecutableUrl : apkUrl).asMap().entries.map((entry) {
                    int index = entry.key;
                    String url = entry.value;

                    return ElevatedButton(
                      child: Text('下载 ${index + 1}'),
                      onPressed: () {
                        downloadAndInstallApk(url);
                      },
                    );
                  }),
                ],
              ),
            ),
            SizedBox(
              width: 60,
              child: TextButton(
                child: Text(S.of(context).cancel),
                onPressed: () {
                  if (entry != null) {
                    entry!.remove();
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
