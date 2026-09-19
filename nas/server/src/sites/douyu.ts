import { registerSite } from './index';
import { emptyRoom, LiveStatus } from '../protocol';

/** douyu 平台 API 聚合（M1 移植自 lib/core/site/douyu_site.dart）。 */
class DouyuSiteImpl /* implements Site */ {}

registerSite('douyu', {
  async getCategories() { return []; },
  async getCategoryRooms() { return []; },
  async getRecommendRooms() { return []; },
  async searchRooms() { return []; },
  async searchAnchors() { return []; },
  async getRoomDetail(roomId) { return emptyRoom('douyu', roomId); },
  async getPlayQualites() { return []; },
  async getPlayUrls() { return []; },
  async getLiveStatus() { return false; },
  async sendDanmaku() { return [false, 'not implemented (M1)']; },
});
