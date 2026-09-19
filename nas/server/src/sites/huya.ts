import { registerSite } from './index';
import { emptyRoom, LiveStatus } from '../protocol';

/** huya 平台 API 聚合（M1 移植自 lib/core/site/huya_site.dart）。 */
class HuyaSiteImpl /* implements Site */ {}

registerSite('huya', {
  async getCategories() { return []; },
  async getCategoryRooms() { return []; },
  async getRecommendRooms() { return []; },
  async searchRooms() { return []; },
  async searchAnchors() { return []; },
  async getRoomDetail(roomId) { return emptyRoom('huya', roomId); },
  async getPlayQualites() { return []; },
  async getPlayUrls() { return []; },
  async getLiveStatus() { return false; },
  async sendDanmaku() { return [false, 'not implemented (M1)']; },
});
