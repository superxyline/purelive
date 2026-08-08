import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  static const String _email = '17792321552@163.com';
  static const String _emailUrl = 'mailto:17792321552@163.com?subject=PureLive Feedback';
  static const String _projectUrl = 'https://gitee.com/superxyline/purelive';

  void clipboard(String text) {
    Clipboard.setData(ClipboardData(text: text)).then((value) => SnackBarUtil.success(i18n('copied_to_clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          SectionTitle(title: i18n("contact")),
          ListTile(
            leading: const Icon(CustomIcons.mail_squared, size: 34),
            title: Text(i18n("email")),
            subtitle: const Text(_email),
            onLongPress: () => clipboard(_email),
            onTap: () {
              launchUrl(Uri.parse(_emailUrl), mode: LaunchMode.externalApplication);
            },
          ),
          ListTile(
            leading: const Icon(CustomIcons.github_circled, size: 32),
            title: Text(i18n("project_page")),
            subtitle: const Text(_projectUrl),
            onTap: () {
              launchUrl(Uri.parse(_projectUrl), mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    );
  }
}
