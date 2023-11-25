import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/supabase.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  void uploadUserConifg() {
    SupaBaseManager().uploadConfig();
  }

  void downloadUserConifg() {
    SupaBaseManager().readConfig();
  }

  void singOut() {
    SupaBaseManager().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).supabase_mine),
      ),
      body: ListView(scrollDirection: Axis.vertical, physics: const BouncingScrollPhysics(), children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sim_card_download_outlined, size: 32),
                subtitle: Text(S.of(context).supabase_mine_streams),
                title: const Text('下载用户配置'),
                onTap: downloadUserConifg,
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined, size: 32),
                subtitle: Text(S.of(context).supabase_mine_streams),
                title: Text(S.of(context).supabase_mine_profiles),
                onTap: uploadUserConifg,
              ),
              ListTile(
                leading: const Icon(Icons.login_outlined, size: 32),
                title: Text(S.of(context).supabase_log_out),
                onTap: singOut,
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
