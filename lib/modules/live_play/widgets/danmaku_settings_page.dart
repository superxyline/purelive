import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/count_button.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({super.key, required this.controller});
  final VideoController controller;

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  VideoController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = Theme.of(context).colorScheme.onSurface;
    final Color digitColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16),
      child: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Text('显示区域', style: TextStyle(color: labelColor, fontSize: 15)), // 应用 labelColor
                title: Slider(
                  divisions: 10,
                  min: 0.0,
                  max: 1.0,
                  value: controller.danmakuArea.value,
                  onChanged: (val) => controller.danmakuArea.value = val,
                ),
                trailing: Text(
                  '${(controller.danmakuArea.value * 100).toInt()}%',
                  style: TextStyle(color: digitColor),
                ), // 应用 digitColor
              ),
            ),
            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Text('距离顶部', style: TextStyle(color: labelColor, fontSize: 15)), // 应用 labelColor
                title: CountButton(
                  maxValue: 300,
                  minValue: 0,
                  selectedValue: controller.danmakuTopArea.value,
                  onChanged: (val) => controller.danmakuTopArea.value = val,
                  textStyle: TextStyle(color: digitColor, fontSize: 18),
                ),
              ),
            ),
            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Text('距离底部', style: TextStyle(color: labelColor, fontSize: 15)), // 应用 labelColor
                title: CountButton(
                  maxValue: 300,
                  minValue: 0,
                  selectedValue: controller.danmakuBottomArea.value,
                  onChanged: (val) => controller.danmakuBottomArea.value = val,
                  textStyle: TextStyle(color: digitColor, fontSize: 18),
                ),
              ),
            ),

            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Text(
                  S.of(context).settings_danmaku_opacity,
                  style: TextStyle(color: labelColor, fontSize: 15),
                ), // 应用 labelColor
                title: Slider(
                  divisions: 10,
                  min: 0.0,
                  max: 1.0,
                  value: controller.danmakuOpacity.value,
                  onChanged: (val) => controller.danmakuOpacity.value = val,
                ),
                trailing: Text(
                  '${(controller.danmakuOpacity.value * 100).toInt()}%',
                  style: TextStyle(color: digitColor),
                ), // 应用 digitColor
              ),
            ),

            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Text(
                  S.of(context).settings_danmaku_speed,
                  style: TextStyle(color: labelColor, fontSize: 15),
                ), // 应用 labelColor
                title: Slider(
                  divisions: 15,
                  min: 5.0,
                  max: 20.0,
                  value: controller.danmakuSpeed.value,
                  onChanged: (val) => controller.danmakuSpeed.value = val,
                ),
                trailing: Text(
                  controller.danmakuSpeed.value.toInt().toString(),
                  style: TextStyle(color: digitColor),
                ), // 应用 digitColor
              ),
            ),

            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Text(
                  S.of(context).settings_danmaku_fontsize,
                  style: TextStyle(color: labelColor, fontSize: 15),
                ), // 应用 labelColor
                title: Slider(
                  divisions: 20,
                  min: 10.0,
                  max: 30.0,
                  value: controller.danmakuFontSize.value,
                  onChanged: (val) => controller.danmakuFontSize.value = val,
                ),
                trailing: Text(
                  controller.danmakuFontSize.value.toInt().toString(),
                  style: TextStyle(color: digitColor),
                ), // 应用 digitColor
              ),
            ),

            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Text(
                  S.of(context).settings_danmaku_fontBorder,
                  style: TextStyle(color: labelColor, fontSize: 15),
                ), // 应用 labelColor
                title: Slider(
                  divisions: 8,
                  min: 0.0,
                  max: 8.0,
                  value: controller.danmakuFontBorder.value,
                  onChanged: (val) => controller.danmakuFontBorder.value = val,
                ),
                trailing: Text(
                  controller.danmakuFontBorder.value.toStringAsFixed(2),
                  style: TextStyle(color: digitColor),
                ), // 应用 digitColor
              ),
            ),
          ],
        ),
      ),
    );
  }
}
