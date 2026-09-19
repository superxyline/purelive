"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const index_1 = require("./index");
const protocol_1 = require("../protocol");
/** douyu 平台 API 聚合（M1 移植自 lib/core/site/douyu_site.dart）。 */
class DouyuSiteImpl /* implements Site */ {
}
(0, index_1.registerSite)('douyu', {
    async getCategories() { return []; },
    async getCategoryRooms() { return []; },
    async getRecommendRooms() { return []; },
    async searchRooms() { return []; },
    async searchAnchors() { return []; },
    async getRoomDetail(roomId) { return (0, protocol_1.emptyRoom)('douyu', roomId); },
    async getPlayQualites() { return []; },
    async getPlayUrls() { return []; },
    async getLiveStatus() { return false; },
    async sendDanmaku() { return [false, 'not implemented (M1)']; },
});
