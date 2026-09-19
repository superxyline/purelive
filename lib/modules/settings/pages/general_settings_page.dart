import 'dart:io';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';
import 'package:pure_live/modules/settings/pages/audience_metric_settings_page.dart';
import 'package:pure_live/common/global/platform_utils.dart';

class GeneralSettingsPage extends GetView<SettingsService> {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n("general"))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("general")),
          context.buildModernCard([
            if (PlatformUtils.isAndroid)
              Obx(() {
                final info = DisplayModeService.info.value;
                final suffix = info == null
                    ? ''
                    : ' · ${info.currentRefreshRate.toStringAsFixed(0)} / ${info.maxRefreshRate.toStringAsFixed(0)} Hz';
                return context.buildSwitchTile(
                  title: i18n('high_refresh_rate'),
                  subtitle: '${i18n('high_refresh_rate_subtitle')}$suffix',
                  value: SettingsService.to.app.enableHighRefreshRate,
                  icon: Remix.speed_up_line,
                  isLong: true,
                );
              }),
            if (PlatformUtils.isWindows)
              Obx(() {
                final info = DisplayModeService.info.value;
                final mode = info == null
                    ? i18n('display_mode_detecting')
                    : '${info.width} × ${info.height} · '
                          '${info.currentRefreshRate.toStringAsFixed(0)} Hz '
                          '(${i18n('display_mode_max')} ${info.maxRefreshRate.toStringAsFixed(0)} Hz)';
                return context.buildTile(
                  title: i18n('windows_dynamic_refresh_rate'),
                  subtitle: '${i18n('windows_dynamic_refresh_rate_subtitle')}\n$mode',
                  icon: Remix.speed_up_line,
                  isLong: true,
                  trailing: const Icon(Icons.refresh_rounded),
                  onTap: () => DisplayModeService.refreshInfo(),
                );
              }),
            context.buildTile(
              title: i18n('audience_metric_settings'),
              subtitle: i18n('audience_metric_settings_desc'),
              icon: Icons.groups_2_rounded,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Get.to(() => const AudienceMetricSettingsPage()),
            ),
            context.buildSwitchTile(
              title: i18n('show_live_duration'),
              subtitle: i18n('show_live_duration_desc'),
              value: SettingsService.to.app.showLiveDurationBadge,
              icon: Icons.access_time_rounded,
            ),
            context.buildSwitchTile(
              title: i18n('splash_animation'),
              subtitle: i18n("splash_animation_subtitle"),
              value: SettingsService.to.app.showSplashPage,
              icon: Remix.rocket_2_line,
            ),
            context.buildSwitchTile(
              title: i18n('enable_auto_check_update'),
              subtitle: "",
              value: SettingsService.to.app.enableAutoCheckUpdate,
              icon: Remix.refresh_line,
            ),
            // 赛事提醒：提前分钟数（开关即赛事页的星标关注）
            Obx(() {
              final lead = SettingsService.to.app.esportsReminderLeadMinutes.v;
              return context.buildTile(
                title: i18n('esports_reminder_lead'),
                subtitle: i18n('esports_reminder_lead_subtitle', args: {'minutes': '$lead'}),
                icon: Remix.trophy_line,
                isLong: true,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showReminderLeadDialog(context),
              );
            }),
            context.buildSwitchTile(
              title: i18n('enable_countdown_close'),
              subtitle: i18n('enable_countdown_close_subtitle'),
              value: SettingsService.to.exit.enableAutoShutDownTime,
              icon: Remix.timer_line,
            ),
            Obx(() {
              final bool isEnabled = SettingsService.to.exit.enableAutoShutDownTime.v;
              final int configMinutes = SettingsService.to.exit.autoShutDownTime.v;

              return StreamBuilder<int>(
                key: ValueKey('${isEnabled}_$configMinutes'),
                stream: SettingsService.to.exit.stopWatchTimer.rawTime,
                builder: (context, snapshot) {
                  final int value = snapshot.data ?? 0;
                  String subtitleText = "";

                  if (!isEnabled || value == 0) {
                    subtitleText = "$configMinutes ${i18n('minutes')}";
                  } else {
                    final displayTime = StopWatchTimer.getDisplayTime(value, hours: true, milliSecond: false);
                    subtitleText = "${i18n('remaining_time')}: $displayTime";
                  }

                  return context.buildTile(
                    iconWidget: AnimatedTimerIcon(enabled: isEnabled, remainingMs: value, totalMinutes: configMinutes),

                    title: i18n('countdown_duration'),
                    subtitle: subtitleText,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showCountdownDurationDialog(context),
                  );
                },
              );
            }),

            if (PlatformUtils.isWindows) ...[
              context.buildSwitchTile(
                title: i18n("startup"),
                subtitle: "",
                value: SettingsService.to.startup.enableStartUp,
                icon: Remix.windows_line,
              ),
              context.buildSwitchTile(
                title: i18n("no_exit_confirm"),
                subtitle: "",
                value: SettingsService.to.exit.dontAskExit,
                icon: Remix.error_warning_line,
              ),
              Obx(
                () => context.buildTile(
                  icon: Remix.logout_box_r_line,
                  title: i18n("exit_action"),
                  subtitle: SettingsService.to.exit.exitChoose.v == 'exit'
                      ? i18n("exit_action_exit")
                      : i18n("exit_action_minimize"),
                  onTap: () => _showExitActionDialog(context),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showReminderLeadDialog(BuildContext context) {
    final List<int> options = [5, 10, 15, 30, 60];
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text(i18n('esports_reminder_lead')),
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: options.map<Widget>((minutes) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ChoiceChip(
                    label: Text("$minutes ${i18n('minutes')}"),
                    selected: SettingsService.to.app.esportsReminderLeadMinutes.v == minutes,
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: SettingsService.to.app.esportsReminderLeadMinutes.v == minutes
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (bool selected) {
                      if (selected) {
                        SettingsService.to.app.esportsReminderLeadMinutes.v = minutes;
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                i18n('esports_reminder_lead_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }

  void _showExitActionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text(i18n('exit_action')),
          children: [
            Obx(
              () => RadioGroup<String>(
                groupValue: SettingsService.to.exit.exitChoose.v,
                onChanged: (String? value) {
                  if (value != null) {
                    SettingsService.to.exit.exitChoose.v = value;
                    Navigator.of(context).pop();
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'minimize',
                      title: Text(i18n('exit_action_minimize')),
                    ),
                    RadioListTile<String>(
                      value: 'exit',
                      title: Text(i18n('exit_action_exit')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCountdownDurationDialog(BuildContext context) {
    final List<int> minutesOptions = [15, 30, 45, 60, 90, 120, 180];
    final int currentValue = SettingsService.to.exit.autoShutDownTime.v;
    final bool isCustom = !minutesOptions.contains(currentValue);

    final TextEditingController inputController = TextEditingController(text: isCustom ? currentValue.toString() : "");

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(i18n('select_countdown_duration')),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            width: MediaQuery.of(context).size.width,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i18n('app_exit_timer_explain'), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Obx(() {
                    final selectedValue = SettingsService.to.exit.autoShutDownTime.v;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: minutesOptions.map<Widget>((minutes) {
                        final bool isSelected = selectedValue == minutes;
                        return ChoiceChip(
                          label: Text("$minutes ${i18n('minutes')}"),
                          selected: isSelected,
                          selectedColor: Theme.of(context).colorScheme.primaryContainer,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (bool selected) {
                            if (selected) {
                              SettingsService.to.exit.updateShutDownTime(minutes);
                              Navigator.of(context).pop();
                            }
                          },
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 20),
                  TextField(
                    controller: inputController,
                    keyboardType: TextInputType.number,
                    style: AppTextStyles.t14,
                    maxLines: 1,
                    decoration: InputDecoration(
                      labelText: i18n('custom_duration'),
                      suffixText: i18n('minutes'),
                      helperText: i18n('app_exit_timer_custom_hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
            FilledButton(
              onPressed: () {
                final parsedValue = int.tryParse(inputController.text.trim());
                if (parsedValue == null || parsedValue < 1) {
                  ToastUtil.show(i18n('app_exit_timer_custom_hint'));
                  return;
                }
                SettingsService.to.exit.updateShutDownTime(parsedValue);
                Navigator.of(context).pop();
              },
              child: Text(i18n('save')),
            ),
          ],
        );
      },
    );
  }
}

class AnimatedTimerIcon extends StatelessWidget {
  final bool enabled;
  final int remainingMs;
  final int totalMinutes;

  const AnimatedTimerIcon({super.key, required this.enabled, required this.remainingMs, required this.totalMinutes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.primary;

    double turns = 0.0;
    if (enabled && totalMinutes > 0 && remainingMs > 0) {
      final double totalMs = totalMinutes * 60 * 1000;
      final double passedMs = totalMs - remainingMs;
      turns = (passedMs / (60 * 1000)) * 60.0;
    }

    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: iconColor, width: 2),
            ),
          ),
          RotationTransition(
            turns: AlwaysStoppedAnimation(turns),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 2,
                  height: 7,
                  decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(1)),
                ),
                const SizedBox(height: 7),
              ],
            ),
          ),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
