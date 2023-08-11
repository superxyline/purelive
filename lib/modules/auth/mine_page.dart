import 'package:flutter/material.dart';
import 'package:pure_live/plugins/supbase.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {

  void uploadUserConifg(){
    SupBaseManager().uploadConfig();
  }

  void singOut(){
    SupBaseManager().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: ListView(
          scrollDirection: Axis.vertical,
          physics: const BouncingScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined, size: 32),
                    subtitle: const Text('关注直播间以及主题等'),
                    title: const Text('上传用户配置文件'),
                    onTap:uploadUserConifg,
                  ),
                  ListTile(
                    leading: const Icon(Icons.login_outlined, size: 32),
                    title: const Text('退出登录'),
                    onTap: singOut,
                  ),
                ],
              ),
            ),
          ]),
    );
  }
}
