"use strict";
/**
 * 与 Flutter 端数据模型逐字段对齐的 JSON 协议。
 * 参考 lib/common/models/live_room.dart (fromJson) 与 lib/model/live_category.dart 等。
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.LiveStatus = exports.PLATFORMS = void 0;
exports.emptyRoom = emptyRoom;
exports.PLATFORMS = ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'];
/** LiveStatus 枚举 index：live=0, offline=1, replay=2, unknown=3, banned=4 */
exports.LiveStatus = { live: 0, offline: 1, replay: 2, unknown: 3, banned: 4 };
function emptyRoom(platform, roomId) {
    return {
        roomId,
        userId: '',
        link: '',
        title: '',
        nick: '',
        avatar: '',
        cover: '',
        area: '',
        watching: '0',
        popularity: '',
        onlineViewers: '',
        totalViewers: '',
        followers: '0',
        platform,
        liveStatus: exports.LiveStatus.unknown,
        status: false,
        notice: '',
        introduction: '',
        isRecord: false,
        epgId: '',
        currentProgramme: '',
        currentProgrammeDescription: '',
    };
}
