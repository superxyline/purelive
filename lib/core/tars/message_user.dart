import 'package:pure_live/pkg/tars/codec/tars_struct.dart';
import 'package:pure_live/pkg/tars/codec/tars_displayer.dart';
import 'package:pure_live/pkg/tars/codec/tars_input_stream.dart';
import 'package:pure_live/pkg/tars/codec/tars_output_stream.dart';

/// 虎牙醒目留言（SC）里的用户信息（移植自上游 core/tars/types.dart）。
class MessageUser extends TarsStruct {
  String sNick = "";
  String sAvatar = "";

  @override
  void readFrom(TarsInputStream tarsInputStream) {
    sNick = tarsInputStream.read(sNick, 1, false);
    sAvatar = tarsInputStream.read(sAvatar, 2, false);
  }

  @override
  void writeTo(TarsOutputStream tarsOutputStream) {
    tarsOutputStream.write(sNick, 1);
    tarsOutputStream.write(sAvatar, 2);
  }

  @override
  Object deepCopy() {
    return MessageUser()
      ..sNick = sNick
      ..sAvatar = sAvatar;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    final ds = TarsDisplayer(sb, level: level);
    ds.DisplayString(sNick, "sNick");
    ds.DisplayString(sAvatar, "sAvatar");
  }
}
