import 'package:pure_live/core/tars/huya_user_id.dart';
import 'package:pure_live/pkg/tars/codec/tars_struct.dart';
import 'package:pure_live/pkg/tars/codec/tars_displayer.dart';
import 'package:pure_live/pkg/tars/codec/tars_input_stream.dart';
import 'package:pure_live/pkg/tars/codec/tars_output_stream.dart';
// ignore_for_file: no_leading_underscores_for_local_identifiers

/// huyauserui.getAllSubscribeToUidList 请求：返回当前账号关注的主播 uid 列表
class GetAllSubscribeToUidListReq extends TarsStruct {
  HuyaUserId tId = HuyaUserId(); // tag 0
  int lUid = 0; // tag 1 (int64)

  @override
  void readFrom(TarsInputStream inputStream) {
    tId = inputStream.read(tId, 0, false);
    lUid = inputStream.read(lUid, 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(tId, 0);
    outputStream.write(lUid, 1);
  }

  @override
  TarsStruct deepCopy() {
    return GetAllSubscribeToUidListReq()
      ..tId = tId
      ..lUid = lUid;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer ds = TarsDisplayer(sb, level: level);
    ds.DisplayTarsStruct(tId, "tId");
    ds.DisplayInt(lUid, "lUid");
  }
}

/// huyauserui.getAllSubscribeToUidList 响应
class GetAllSubscribeToUidListRsp extends TarsStruct {
  String sMessage = ""; // tag 0
  List<int> vAllUid = []; // tag 1 vector<int64>

  @override
  void readFrom(TarsInputStream inputStream) {
    sMessage = inputStream.read(sMessage, 0, false);
    vAllUid = inputStream.readList([0], 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(sMessage, 0);
    outputStream.write(vAllUid, 1);
  }

  @override
  TarsStruct deepCopy() {
    return GetAllSubscribeToUidListRsp()
      ..sMessage = sMessage
      ..vAllUid = List<int>.from(vAllUid);
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer ds = TarsDisplayer(sb, level: level);
    ds.DisplayString(sMessage, "sMessage");
    ds.DisplayList(vAllUid, "vAllUid");
  }
}

/// huyauserui.getUserProfile 请求
class GetUserProfileReq extends TarsStruct {
  HuyaUserId tId = HuyaUserId(); // tag 0
  int lUid = 0; // tag 1 (int64) 目标主播 uid

  @override
  void readFrom(TarsInputStream inputStream) {
    tId = inputStream.read(tId, 0, false);
    lUid = inputStream.read(lUid, 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(tId, 0);
    outputStream.write(lUid, 1);
  }

  @override
  TarsStruct deepCopy() {
    return GetUserProfileReq()
      ..tId = tId
      ..lUid = lUid;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer ds = TarsDisplayer(sb, level: level);
    ds.DisplayTarsStruct(tId, "tId");
    ds.DisplayInt(lUid, "lUid");
  }
}

/// huyauserui.getUserProfile 响应
class GetUserProfileRsp extends TarsStruct {
  HuyaUserProfile tUserProfile = HuyaUserProfile(); // tag 0

  @override
  void readFrom(TarsInputStream inputStream) {
    tUserProfile = inputStream.read(tUserProfile, 0, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(tUserProfile, 0);
  }

  @override
  TarsStruct deepCopy() {
    return GetUserProfileRsp()..tUserProfile = tUserProfile;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer ds = TarsDisplayer(sb, level: level);
    ds.DisplayTarsStruct(tUserProfile, "tUserProfile");
  }
}

class HuyaUserProfile extends TarsStruct {
  HuyaUserBase tUserBase = HuyaUserBase(); // tag 0
  HuyaPresenterBase tPresenterBase = HuyaPresenterBase(); // tag 1

  @override
  void readFrom(TarsInputStream inputStream) {
    tUserBase = inputStream.read(tUserBase, 0, false);
    tPresenterBase = inputStream.read(tPresenterBase, 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(tUserBase, 0);
    outputStream.write(tPresenterBase, 1);
  }

  @override
  TarsStruct deepCopy() {
    return HuyaUserProfile()
      ..tUserBase = tUserBase
      ..tPresenterBase = tPresenterBase;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer ds = TarsDisplayer(sb, level: level);
    ds.DisplayTarsStruct(tUserBase, "tUserBase");
    ds.DisplayTarsStruct(tPresenterBase, "tPresenterBase");
  }
}

/// 只声明同步功能需要的字段（sNickName / sAvatarUrl / lYYId）
class HuyaUserBase extends TarsStruct {
  int lUid = 0; // tag 0 int64
  String sNickName = ""; // tag 1
  String sAvatarUrl = ""; // tag 2
  int lYYId = 0; // tag 4 int64

  @override
  void readFrom(TarsInputStream inputStream) {
    lUid = inputStream.read(lUid, 0, false);
    sNickName = inputStream.read(sNickName, 1, false);
    sAvatarUrl = inputStream.read(sAvatarUrl, 2, false);
    lYYId = inputStream.read(lYYId, 4, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(lUid, 0);
    outputStream.write(sNickName, 1);
    outputStream.write(sAvatarUrl, 2);
    outputStream.write(lYYId, 4);
  }

  @override
  TarsStruct deepCopy() {
    return HuyaUserBase()
      ..lUid = lUid
      ..sNickName = sNickName
      ..sAvatarUrl = sAvatarUrl
      ..lYYId = lYYId;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer ds = TarsDisplayer(sb, level: level);
    ds.DisplayInt(lUid, "lUid");
    ds.DisplayString(sNickName, "sNickName");
    ds.DisplayString(sAvatarUrl, "sAvatarUrl");
    ds.DisplayInt(lYYId, "lYYId");
  }
}

/// 只声明同步功能需要的字段（iRoomId）
class HuyaPresenterBase extends TarsStruct {
  int iRoomId = 0; // tag 10 int32

  @override
  void readFrom(TarsInputStream inputStream) {
    iRoomId = inputStream.read(iRoomId, 10, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(iRoomId, 10);
  }

  @override
  TarsStruct deepCopy() {
    return HuyaPresenterBase()..iRoomId = iRoomId;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer ds = TarsDisplayer(sb, level: level);
    ds.DisplayInt(iRoomId, "iRoomId");
  }
}
