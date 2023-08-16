import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/supbase.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  void uploadUserConifg() {
    SupBaseManager().uploadConfig();
  }

  void singOut() {
    SupBaseManager().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).supbase_mine),
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
                    subtitle: Text(S.of(context).supbase_mine_streams),
                    title: Text(S.of(context).supbase_mine_profiles),
                    onTap: uploadUserConifg,
                  ),
                  ListTile(
                    leading: const Icon(Icons.login_outlined, size: 32),
                    title: Text(S.of(context).supbase_log_out),
                    onTap: singOut,
                  ),
                ],
              ),
            ),
          ]),
    );
  }
}
