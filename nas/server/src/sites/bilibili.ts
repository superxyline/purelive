import { registerSite } from './index';
import { emptyRoom, LiveStatus } from '../protocol';

/** bilibili 平台 API 聚合（M1 移植自 lib/core/site/bilibili_site.dart）。 */
class BilibiliSiteImpl /* implements Site */ {}

registerSite('bilibili', {
  async getCategories() { return []; },
  async getCategoryRooms() { return []; },
  async getRecommendRooms() { return []; },
  async searchRooms() { return []; },
  async searchAnchors() { return []; },
  async getRoomDetail(roomId) { return emptyRoom('bilibili', roomId); },
  async getPlayQualites() { return []; },
  async getPlayUrls() { return []; },
  async getLiveStatus() { return false; },
  async sendDanmaku() { return [false, 'not implemented (M1)']; },
});
