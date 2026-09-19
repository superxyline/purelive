// 一次性生成器：从 Dart 源提取内嵌 JS，生成 src/sign/douyin.ts（生成后本文件删除）
const fs = require('fs');

const dartLines = fs.readFileSync('E:/codex/pure_live/lib/core/scripts/douyin_sign_io.dart', 'utf8').split('\n');
const kABogus = dartLines.slice(7, 442).join('\n'); // kABogus = r''' 内容（8..442 行）
const kWebMsSDK = dartLines.slice(445, 10647).join('\n'); // kWebMsSDK = r''' 内容（446..10647 行）

const header = `/**
 * 抖音签名（M1 移植自 lib/core/scripts/douyin_sign_io.dart）：
 * - evalDouyinAbogus：执行上游原版 a_bogus 混淆 JS（K_ABOGUS_JS，原样提取），
 *   Node 内置 vm 执行（替代 Flutter 端 QuickJS），返回带 msToken + a_bogus 的完整 URL。
 * - evalDouyinSignature / evalDouyinMsStub：弹幕 wss 签名，对应
 *   lib/core/danmaku/douyin_danmaku.dart getSignature + lib/core/danmaku/xbogus.dart
 *   （纯算法：RC4 + 自定义 base64 字符表）。
 * - evalDouyinWebMsSignature：K_WEB_MS_SDK_JS（getMSSDKSignature）为 Dart 端旧路径，备用。
 */
import { createHash } from 'crypto';
import vm from 'vm';
`;

const jsBlock = (name, code) => `const ${name} = \`${code}\`;\n`;

const tail = `
/** X-Bogus 字符表（lib/core/danmaku/xbogus.dart）。 */
const K_XBOGUS_ALPHABET = 'Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe';
const K_STANDARD_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const K_EMPTY_MD5_BYTES = [0x45, 0x3f];
const K_DOUYIN_DEFAULT_UA =
  'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400';

const alphabetLookup: number[] = (() => {
  const table = new Array<number>(128).fill(0);
  for (let i = 0; i < 64; i++) {
    table[K_STANDARD_ALPHABET.charCodeAt(i)] = K_XBOGUS_ALPHABET.charCodeAt(i);
  }
  return table;
})();

/** RC4（xbogus.dart rc4Encrypt）。 */
function rc4Encrypt(key: number, data: number[]): void {
  const s = Array.from({ length: 256 }, (_, i) => i);
  let j = 0;
  for (let i = 0; i < 256; i++) {
    j = (j + s[i] + key) & 0xff;
    const tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
  }
  let ii = 0;
  j = 0;
  for (let k = 0; k < data.length; k++) {
    ii = (ii + 1) & 0xff;
    j = (j + s[ii]) & 0xff;
    const tmp = s[ii];
    s[ii] = s[j];
    s[j] = tmp;
    data[k] ^= s[(s[ii] + s[j]) & 0xff];
  }
}

/** base64 编码并映射到 X-Bogus 字符表（xbogus.dart encodeBase64）。 */
function encodeXbogusBase64(data: number[]): string {
  let out = '';
  for (let i = 0; i < data.length; i += 3) {
    const b0 = data[i];
    const b1 = data[i + 1];
    const b2 = data[i + 2];
    out += alphabetLookup[K_STANDARD_ALPHABET.charCodeAt((b0 >> 2) & 0x3f)];
    out += alphabetLookup[K_STANDARD_ALPHABET.charCodeAt(((b0 << 4) | (b1 >> 4)) & 0x3f)];
    out += alphabetLookup[K_STANDARD_ALPHABET.charCodeAt(((b1 << 2) | (b2 >> 6)) & 0x3f)];
    out += alphabetLookup[K_STANDARD_ALPHABET.charCodeAt(b2 & 0x3f)];
  }
  return out;
}

/** md5(decode(hexString)) 最后两个字节（xbogus.dart md5Last2）。 */
function md5Last2(hexStr: string): [number, number] {
  const bytes: number[] = [];
  for (let i = 0; i < 16; i++) {
    bytes.push(Number.parseInt(hexStr.substring(i * 2, i * 2 + 2), 16));
  }
  const digest = createHash('md5').update(Uint8Array.from(bytes)).digest();
  return [digest[14], digest[15]];
}

/** 生成 X-Bogus（xbogus.dart generateXBogus；msStub 为 32 位 md5 hex）。 */
export function generateXBogus(msStub: string, counter = 1): string {
  if (msStub.length !== 32) {
    throw new Error('douyin msStub must be 32-char md5 hex string');
  }
  const random1 = Math.floor(Math.random() * 256);
  const random2 = Math.floor(Math.random() * 255);
  const header = 0x40 | (random1 & 0x1f);
  const md5Bytes = md5Last2(msStub);
  const payload = [
    counter & 0x3f,
    0,
    1,
    0x0e,
    K_EMPTY_MD5_BYTES[0],
    K_EMPTY_MD5_BYTES[1],
    md5Bytes[0],
    md5Bytes[1],
    random2,
    0,
  ];
  let checksum = 0;
  for (let i = 0; i < 9; i++) checksum ^= payload[i];
  payload[9] = checksum;
  rc4Encrypt(random2, payload);
  const finalData = new Array<number>(12).fill(0);
  finalData[0] = header;
  finalData[1] = random2;
  for (let i = 0; i < 10; i++) finalData[i + 2] = payload[i];
  return encodeXbogusBase64(finalData);
}

/** 弹幕 wss 签名参数串（douyin_danmaku.dart getSignature 的 params 拼接）。 */
function buildWssSigParam(roomId: string, uniqueId: string): string {
  const params: Record<string, string> = {
    live_id: '1',
    aid: '6383',
    version_code: '180800',
    webcast_sdk_version: '1.0.14-beta.0',
    room_id: roomId,
    sub_room_id: '',
    sub_channel_id: '',
    did_rule: '3',
    user_unique_id: uniqueId,
    device_platform: 'web',
    device_type: '',
    ac: '',
    identity: 'audience',
  };
  return Object.entries(params)
    .map(([k, v]) => \`\${k}=\${v}\`)
    .join(',');
}

/** 弹幕 msStub（douyin_sign_io.dart getMsStub：version_code 为数字 180800）。 */
export function evalDouyinMsStub(roomId: string, uniqueId: string): string {
  const params: Array<[string, string]> = [
    ['live_id', '1'],
    ['aid', '6383'],
    ['version_code', '180800'],
    ['webcast_sdk_version', '1.0.14-beta.0'],
    ['room_id', roomId],
    ['sub_room_id', ''],
    ['sub_channel_id', ''],
    ['did_rule', '3'],
    ['user_unique_id', uniqueId],
    ['device_platform', 'web'],
    ['device_type', ''],
    ['ac', ''],
    ['identity', 'audience'],
  ];
  const sigParams = params.map(([k, v]) => \`\${k}=\${v}\`).join(',');
  return createHash('md5').update(sigParams, 'utf8').digest('hex');
}

/**
 * 弹幕 wss URL 的 signature 参数。
 * 对应 Dart：DouyinDanmaku.getSignature —— generateXBogus(md5(参数串), 1)。
 */
export function evalDouyinSignature(roomId: string, uniqueId: string): string {
  const md5SigParam = createHash('md5').update(buildWssSigParam(roomId, uniqueId), 'utf8').digest('hex');
  return generateXBogus(md5SigParam, 1);
}

function vmSandbox(): Record<string, unknown> {
  const sandbox: Record<string, unknown> = {
    navigator: { userAgent: K_DOUYIN_DEFAULT_UA },
    location: { href: 'https://live.douyin.com/' },
  };
  sandbox.global = sandbox;
  sandbox.window = sandbox;
  sandbox.self = sandbox;
  return sandbox;
}

/** 抖音 107 位 msToken（douyin_sign_io.dart generateMsToken）。 */
export function generateMsToken(length: number): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let out = '';
  for (let i = 0; i < length; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

/**
 * a_bogus 签名：执行上游原版 JS 得到 a_bogus 值，返回
 * '原URL&msToken=<enc>&a_bogus=<enc>'（douyin_sign_io.dart getAbogusUrl）。
 */
export function evalDouyinAbogus(url: string, userAgent: string): string {
  const msToken = generateMsToken(107);
  const params = (\`\${url}&msToken=\${msToken}\`).split('?')[1] ?? '';
  const query = params.includes('?') ? (params.split('?')[1] ?? '') : params;

  const sandbox = vmSandbox();
  vm.createContext(sandbox);
  vm.runInContext(K_ABOGUS_JS, sandbox, { timeout: 10_000 });
  const aBogus = vm.runInContext(
    \`getABogus(\${JSON.stringify(query)}, \${JSON.stringify(userAgent)})\`,
    sandbox,
    { timeout: 10_000 },
  );
  return \`\${url}&msToken=\${encodeURIComponent(msToken)}&a_bogus=\${encodeURIComponent(String(aBogus))}\`;
}

/**
 * msStub → web 端 X-Bogus 签名（douyin_sign_io.dart getSignature，旧路径备用）。
 * 返回值含 -/= 时重试（Dart 同款循环）。
 */
export function evalDouyinWebMsSignature(msStub: string, userAgent: string): string {
  const sandbox = vmSandbox();
  vm.createContext(sandbox);
  vm.runInContext(K_WEB_MS_SDK_JS, sandbox, { timeout: 20_000 });
  const call = () =>
    String(
      vm.runInContext(
        \`getMSSDKSignature(\${JSON.stringify(msStub)}, \${JSON.stringify(userAgent)})\`,
        sandbox,
        { timeout: 20_000 },
      ),
    );
  let signature = call();
  let guard = 0;
  while ((signature.includes('-') || signature.includes('=')) && guard++ < 8) {
    signature = call();
  }
  return signature;
}
`;

fs.writeFileSync('src/sign/douyin.ts', header + '\n' + jsBlock('K_ABOGUS_JS', kABogus) + jsBlock('K_WEB_MS_SDK_JS', kWebMsSDK) + tail);
console.log('written', fs.statSync('src/sign/douyin.ts').size);
