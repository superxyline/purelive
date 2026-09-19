/**
 * 抖音签名：a-bogus / X-Bogus（webid 签名）等，与前端 lib/core/scripts/douyin_sign_io.dart 同源。
 * M1 移植。
 */
export function evalDouyinAbogus(url: string, userAgent: string): string {
  throw new Error('douyin abogus: port from lib/core/scripts/douyin_sign_io.dart pending (M1)');
}

export function evalDouyinSignature(roomId: string, uniqueId: string): string {
  throw new Error('douyin signature: port from lib/core/scripts/douyin_sign_io.dart pending (M1)');
}

export function evalDouyinMsStub(roomId: string, uniqueId: string): string {
  throw new Error('douyin msStub: port from lib/core/scripts/douyin_sign_io.dart pending (M1)');
}
