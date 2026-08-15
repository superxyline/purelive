import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/settings/pages/font_settings_page.dart';
import 'package:pure_live/modules/settings/pages/font_family_manager_page.dart';

class FontAndTextPage extends GetView<SettingsService> {
  const FontAndTextPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(i18n("font_text_settings"))),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("font_family_settings")),
          context.buildModernCard([
            Obx(
              () => context.buildTile(
                icon: Remix.font_color,
                title: i18n("change_font_family"),
                subtitle: "${i18n("current_font_prefix")}: ${SettingsService.to.font.fontFamilyName.v}",
                onTap: () => Get.to(() => const FontFamilyManagerPage()),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("text_size_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.font_size,
              title: i18n("font_settings_title"),
              subtitle: i18n("font_settings_desc"),
              onTap: () => Get.to(() => const FontSettingsPage()),
            ),
            const SizedBox(height: 20),
            Obx(
              () => context.buildSliderTile(
                context,
                icon: Remix.text_spacing,
                title: i18n("text_size_title"),
                value: SettingsService.to.font.textScaleFactor.v,
                min: 0.5,
                max: 2.0,
                displayValue: SettingsService.to.font.textScaleFactor.v.toStringAsFixed(2),
                onChanged: (val) {
                  SettingsService.to.font.textScaleFactor.v = val;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.center,
                child: Text(i18n("text_size_preview"), style: TextStyle(color: theme.colorScheme.outline)),
              ),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
