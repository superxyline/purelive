import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';

class LanguageSettingsPage extends GetView<SettingsService> {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(i18n("language_settings"))),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("language_settings")),
          context.buildModernCard([
            Obx(
              () => Column(
                children: AppConsts.languages.keys.map<Widget>((name) {
                  final bool isSelected = SettingsService.to.theme.languageName.v == name;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Remix.global_line : Remix.global_fill,
                      color: isSelected ? theme.colorScheme.primary : theme.hintColor,
                    ),
                    title: Text(name, style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w500)),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                        : null,
                    onTap: () {
                      SettingsService.to.theme.changeLanguage(name);
                    },
                  );
                }).toList(),
              ),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
