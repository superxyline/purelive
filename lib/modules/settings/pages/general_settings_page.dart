import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';

class GeneralSettingsPage extends GetView<SettingsService> {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n("general"))),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("general")),
          context.buildModernCard([
            context.buildSwitchTile(
              title: i18n('splash_animation'),
              subtitle: i18n("splash_animation_subtitle"),
              value: SettingsService.to.app.showSplashPage,
              icon: Remix.rocket_2_line,
            ),
            context.buildSwitchTile(
              title: i18n('show_live_duration_badge'),
              subtitle: i18n("show_live_duration_badge_subtitle"),
              value: SettingsService.to.app.showLiveDurationBadge,
              icon: Remix.time_line,
            ),
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
                    final displayTime = StopWatchTimer.getDisplayTime(value, hours: false, milliSecond: false);
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

          ]),
          const SizedBox(height: 32),
        ],
      ),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: TextField(
                              controller: inputController,
                              keyboardType: TextInputType.number,
                              style: AppTextStyles.t14,
                              maxLines: 1,
                              decoration: InputDecoration(
                                hintText: i18n('custom_duration'),
                                suffixText: i18n('minutes'),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          minimumSize: const Size(0, 40),
                          fixedSize: const Size.fromHeight(40),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          final int? parsedValue = int.tryParse(inputController.text);
                          if (parsedValue != null && parsedValue > 0) {
                            SettingsService.to.exit.updateShutDownTime(parsedValue);
                          }
                          Navigator.of(context).pop();
                        },
                        child: Text(i18n('confirm')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
