import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/modules/account/huya/huya_cookie_controller.dart';

class HuyaCookiePage extends GetView<HuyaCookieController> {
  const HuyaCookiePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("设置cookie"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12.0),
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('浏览器F12,输入document.cookie,复制cookie到下方输入框，点击设置按钮，即可设置虎牙直播cookie'),
          ),
          buildCard(
            context: context,
            child: ExpansionTile(
              title: const Text("cookie"),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              initiallyExpanded: true,
              children: [
                TextField(
                  minLines: 3,
                  maxLines: 3,
                  controller: controller.cookieController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: "输入虎牙直播cookie",
                    contentPadding: const EdgeInsets.all(12.0),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: .2),
                      ),
                    ),
                  ),
                  onSubmitted: controller.setCookie,
                ),
                Container(
                  margin: const EdgeInsets.only(bottom: 4.0),
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      controller.setCookie(controller.cookieController.text);
                    },
                    icon: const Icon(Remix.settings_2_fill),
                    label: const Text("设置"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCard({required BuildContext context, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.all(Radius.circular(8.0)),
        boxShadow: Get.isDarkMode
            ? []
            : [
                BoxShadow(
                  blurRadius: 8,
                  color: Colors.grey.withValues(alpha: .2),
                )
              ],
      ),
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: child,
      ),
    );
  }
}
