#!/usr/bin/env node
/* ==========================================================================
 * 红桃视频 H5 (rt-v0202005) 接口加解密 —— 分析报告 + 参考实现（单文件）
 * 目标站点: https://www.bgi5688uht.vip:9527
 * 前端产物: https://rc210f01byte.masxqf.cn/gm/rt-v0202005/
 * 状态: 已实测验证通过（真实调用接口返回 code:10000 并成功解密业务数据）
 * ==========================================================================
 *
 * 一、结论速查
 * --------------------------------------------------------------------------
 *   算法            AES-128-CBC
 *   填充            ZeroPadding（补 0x00 到 16 字节整数倍）
 *   Key/IV 编码     UTF-8 原始字符串（不是 Hex、不是 Base64）
 *   密文输出        Base64
 *   请求 Content-Type  text/plain（密文原文直接作为 body）
 *   signKey         52S8VB&uiFR^hprd
 *   bundleId        com.ht9.web20.video
 *   version         1.0.0
 *   brandId         hongtao
 *   默认 userId     U11336548
 *
 * 二、Key / IV 派生（每次请求都不同）
 * --------------------------------------------------------------------------
 *   key = t.slice(-6) + signKey.slice(0,4) + bundleId.slice(0,6)
 *       = <时间戳后6位> + "52S8" + "com.ht"            → 恒 16 字节
 *
 *   iv  = bundleId.slice(-6) + signKey.slice(-4) + deviceId.slice(0,6)
 *       = "0.video" + "hprd" + <设备号前6位>           → 恒 16 字节
 *
 *   deviceId = 'H5-' + nanoid(21)
 *     字母表 useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict
 *     首次生成后写入 localStorage["h5_deviceId"]，之后固定不变
 *     所以 deviceId.slice(0,6) === "H5-" + 3 位随机字符
 *
 * 三、请求签名 sign（32 位大写 MD5）
 * --------------------------------------------------------------------------
 *   sign = MD5( 所有参数值按参数名升序拼接 + signKey + path ).toUpperCase()
 *     参数值之间没有任何分隔符；不包含 sign 自身
 *     path 为完整接口路径，如 /ht/content/v2/getArts
 *     特例：/ht/users/sessionLogin 使用签名密钥 opum3_Loily$SV^6H
 *
 * 四、完整流程
 * --------------------------------------------------------------------------
 *   请求：
 *     1) 生成 t（毫秒时间戳字符串）与 deviceId
 *     2) 按上述规则算出 key / iv
 *     3) 组装业务参数 → 计算 sign 并追加进参数对象
 *     4) JSON.stringify(params) → 补 0x00 到 16 字节倍数
 *        → AES-128-CBC 加密 → Base64
 *     5) 密文作为纯文本 body 发送，Content-Type: text/plain
 *
 *   请求头：
 *     Content-Type: text/plain
 *     deviceId / x-device-id : H5-xxxxxxxxxxxxxxxxxxxxx
 *     bundleId / x-bundle-id : com.ht9.web20.video
 *     deviceType/ x-device-type: H5-<platform>
 *     t / x-t                : <毫秒时间戳>
 *     encrypt                : true
 *     lang                   : cn
 *     userId                 : U11336548
 *     sessionId              : <会话 id>
 *     channelId              : 41              (window.__xyz_cid_)
 *     channelId2             : www.bgi5688uht.vip (window.location.host)
 *     x-token                : <游客/会员 token，登录后才有>
 *     x-req-info             : channelId,channelId2,brandId,deviceId,
 *                              deviceType,bundleId,t,version（逗号分隔，顺序固定）
 *
 *   响应：
 *     { "code": 10000, "msg": "成功", "data": "<Base64 密文>" }
 *     data 是字符串 → 用同一对 key/iv 解密 → 去掉所有 \u0000 → JSON.parse
 *     data 是对象   → 多为错误响应，直接使用，不加密
 *
 *   注意：微信/浏览器抓包想离线解密任意一条记录，必须同时拿到该次请求的
 *        t 与 deviceId 两个请求头，缺一不可（key 依赖时间戳、iv 依赖设备号）。
 *
 * 五、免加密接口白名单（仅请求体为明文 JSON，响应仍是密文）
 * --------------------------------------------------------------------------
 *   /ht/users/v2/guestLogin          /ht/content/v2/queryRecommendWord
 *   /ht/content/v2/home              /ht/content/v2/home2
 *   /ht/content/v2/homeH5            /ht/users/v2/appConfig
 *   /ht/users/v2/userLevelConfig     /ht/users/v2/initH5
 *   /ht/users/v2/initH5_1            /ht/users/v2/initH5_2
 *   /ht/ai/v2/queryAiVideoType
 *
 * 六、已实测接口与参数
 * --------------------------------------------------------------------------
 *   POST /ht/content/v2/getArts
 *        params { pageNo (从 0 开始), pageSize }  → data.artList / data.totalPage
 *   POST /ht/content/v2/queryTypeVideosH5
 *        params { typeId, page (从 1 开始), pageSize } → data.typeVideoList
 *   POST /ht/users/v2/guestLogin
 *        params {}（明文提交）→ data.token 写入 x-token
 *
 *   getArts 鉴权：无 token → 20005 用户认证错误
 *                 游客 token + 错参数名 → 20000 系统错误
 *                 游客 token + pageNo/pageSize → 10000 成功
 *
 * 七、另一对与业务无关的静态密钥
 * --------------------------------------------------------------------------
 *   用于解 CDN 配置 https://rc210f01byte.masxqf.cn/interface2/<name>.json
 *     静态 Key: iu8^-0dXL#klP=y6
 *     静态 IV : kRc^%4kL54Xr-(8d
 *   调用方式与业务接口一致（AES-128-CBC / ZeroPadding / UTF-8）
 *
 * 八、还原方法备注（可复现）
 * --------------------------------------------------------------------------
 *   1) 站点是 Vite 打包的 SPA，业务代码在 assets/rt-*.js 主包
 *   2) 主包经 javascript-obfuscator 混淆（字符串数组 + 位移轮转 + 局部字典）
 *   3) 提取字符串数组函数 _0x18f6()、解码函数 _0x1f68()（内部 idx-0x6c）
 *      与顶部位移 IIFE，在 Node 中 eval 后建表，再批量替换源码中的
 *      所有 _0xXXXX(0xNNN) 为字面量
 *   4) 加密库为 crypto-js（打包在 assets/chunk-CylEdDF8.js），只用到
 *      AES / MD5 / enc.Utf8 / mode.CBC / pad.ZeroPadding
 *
 * ==========================================================================
 * 用法
 * ==========================================================================
 *   node ht-api.js                                    显示摘要与用法
 *   node ht-api.js demo                               端到端实测（真实请求接口）
 *   node ht-api.js keys   --t <t> [--deviceId <id>]   打印 key / iv
 *   node ht-api.js decrypt --t <t> --deviceId <id> --data "<响应data Base64>"
 *   node ht-api.js encrypt --t <t> --deviceId <id> --path <接口路径> --json '{"a":1}'
 *   node ht-api.js call   --path <接口路径> --json '{"a":1}' [--token <x-token>]
 *
 * 示例：
 *   node ht-api.js decrypt --t 1790674475116 --deviceId H5-1waycYtXuiZmfdYRfXGOl \
 *        --data "53W6rrBO92xOya86+H/T/TOEzcbW+zlULfGj1AGPokBfmddGD+R+FcM/8VADC96u3US6OCdT7ZWnxdMsuncRjMmIQLv9r63zhtM0vXinoLQ="
 *
 * ==========================================================================
 */

'use strict';
const crypto = require('crypto');

// ========================== 常量 ==========================
const SIGN_KEY = '52S8VB&uiFR^hprd';                          // pe.signKey
const BUNDLE_ID = 'com.ht9.web20.video';                      // pe.bundleId
const VERSION = '1.0.0';
const BRAND_ID = 'hongtao';
const SIGN_KEY_SESSION_LOGIN = 'opum3_Loily$SV^6H';           // sessionLogin 专用
const STATIC_KEY = 'iu8^-0dXL#klP=y6';                        // 配置接口静态 key
const STATIC_IV = 'kRc^%4kL54Xr-(8d';                         // 配置接口静态 iv
const NANOID_ALPHABET = 'useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict';
const ORIGIN = 'https://www.bgi5688uht.vip:9527';

const NO_ENCRYPT_PREFIX = [
  '/ht/users/v2/guestLogin',
  '/ht/content/v2/queryRecommendWord',
  '/ht/content/v2/home',
  '/ht/content/v2/home2',
  '/ht/content/v2/homeH5',
  '/ht/users/v2/appConfig',
  '/ht/users/v2/userLevelConfig',
  '/ht/users/v2/initH5',
  '/ht/users/v2/initH5_1',
  '/ht/users/v2/initH5_2',
  '/ht/ai/v2/queryAiVideoType',
];

// ========================== 基础工具 ==========================
const md5Hex = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');

/** 等价于前端 nanoid()，用于生成设备号 */
function nanoid(len = 21) {
  const b = crypto.randomBytes(len);
  let s = '';
  for (let i = 0; i < len; i++) s += NANOID_ALPHABET[b[i] & 63];
  return s;
}
const newDeviceId = () => 'H5-' + nanoid(21);

/** CryptoJS.pad.ZeroPadding：补 0x00 到 16 字节整数倍（已对齐则补 0 字节） */
function zeroPad(buf) {
  const r = buf.length % 16;
  return r === 0 ? buf : Buffer.concat([buf, Buffer.alloc(16 - r)]);
}

// ========================== 加解密 ==========================
/** 对应前端 ge.aesEncrypt(plain, key, iv) */
function aesEncrypt(plain, key, iv) {
  const c = crypto.createCipheriv('aes-128-cbc', Buffer.from(key, 'utf8'), Buffer.from(iv, 'utf8'));
  c.setAutoPadding(false);
  return Buffer.concat([c.update(zeroPad(Buffer.from(plain, 'utf8'))), c.final()]).toString('base64');
}

/** 对应前端 ge.aesDecrypt(cipher, key, iv)：解密后去掉所有 \u0000 */
function aesDecrypt(cipherB64, key, iv) {
  const d = crypto.createDecipheriv('aes-128-cbc', Buffer.from(key, 'utf8'), Buffer.from(iv, 'utf8'));
  d.setAutoPadding(false);
  return Buffer.concat([d.update(Buffer.from(cipherB64, 'base64')), d.final()])
    .toString('utf8').replace(/\u0000/g, '');
}

const aesEncryptStatic = plain => aesEncrypt(plain, STATIC_KEY, STATIC_IV);
const aesDecryptStatic = b64 => aesDecrypt(b64, STATIC_KEY, STATIC_IV);

// ========================== 派生与签名 ==========================
const signKeyOf = path => path === '/ht/users/sessionLogin' ? SIGN_KEY_SESSION_LOGIN : SIGN_KEY;

/** key = 时间戳后6位 + signKey前4位 + bundleId前6位 */
const deriveKey = (t, signKey = SIGN_KEY) => t.slice(-6) + signKey.slice(0, 4) + BUNDLE_ID.slice(0, 6);

/** iv = bundleId后6位 + signKey后4位 + deviceId前6位 */
const deriveIv = (deviceId, signKey = SIGN_KEY) =>
  BUNDLE_ID.slice(-6) + signKey.slice(-4) + deviceId.slice(0, 6);

/** sign = MD5(参数值按参数名升序拼接 + signKey + path).toUpperCase() */
function makeSign(params, path, signKey = SIGN_KEY) {
  const joined = Object.keys(params).sort().map(k => String(params[k])).join('');
  return md5Hex(joined + signKey + path).toUpperCase();
}

const isPlainText = path => NO_ENCRYPT_PREFIX.some(p => path.startsWith(p));

// ========================== 一体化：构造请求 / 解密响应 ==========================
function buildHeaders(t, deviceId, token) {
  const deviceType = 'H5-other';
  const h = {
    'Content-Type': 'text/plain',
    'deviceId': deviceId,
    'bundleId': BUNDLE_ID,
    'deviceType': deviceType,
    't': t,
    'encrypt': 'true',
    'lang': 'cn',
    'userId': 'U11336548',
    'sessionId': '',
    'channelId': '41',
    'channelId2': 'www.bgi5688uht.vip',
    'x-t': t,
    'x-device-id': deviceId,
    'x-device-type': deviceType,
    'x-bundle-id': BUNDLE_ID,
    'x-req-info': ['41', 'www.bgi5688uht.vip', BRAND_ID, deviceId, deviceType, BUNDLE_ID, t, VERSION].join(','),
  };
  if (token) h['x-token'] = token;
  return h;
}

/** 构造一次加密请求；白名单接口走明文 JSON */
function buildRequest(path, params = {}, t = Date.now().toString(), deviceId = newDeviceId()) {
  const sk = signKeyOf(path);
  const key = deriveKey(t, sk), iv = deriveIv(deviceId, sk);
  const plainPath = isPlainText(path);
  const payload = Object.assign({}, params);
  let body;
  if (plainPath) {
    body = JSON.stringify(payload);
  } else {
    payload.sign = makeSign(payload, path, sk);
    body = aesEncrypt(JSON.stringify(payload), key, iv);
  }
  const headers = buildHeaders(t, deviceId);
  if (plainPath) headers['Content-Type'] = 'application/json';
  return { body, key, iv, payload, headers, deviceId, t, plain: plainPath };
}

/** 响应解密：data 为字符串才需要解密 */
function decryptResponse(json, key, iv) {
  if (json && typeof json.data === 'string' && json.data) {
    json.data = JSON.parse(aesDecrypt(json.data, key, iv));
  }
  return json;
}

/** 离线解密某次响应的 data（需要那次请求的 t 与 deviceId） */
function decodeResponseData(dataB64, t, deviceId) {
  return JSON.parse(aesDecrypt(dataB64, deriveKey(t), deriveIv(deviceId)));
}

// ========================== 真实调用 ==========================
// 重要：游客/会员 token 与签发时的 deviceId 绑定，
//      同一会话内所有请求必须复用同一个 deviceId，否则返回 401 / 20005。
async function post(path, params, token, deviceId) {
  const r = buildRequest(path, params, undefined, deviceId || newDeviceId());
  const headers = Object.assign(r.headers, {});
  if (token) headers['x-token'] = token;
  const res = await fetch(ORIGIN + path, { method: 'POST', headers, body: r.body });
  const json = await res.json();
  if (typeof json.data === 'string' && json.data) {
    try { json.data = decryptResponse({ data: json.data }, r.key, r.iv).data; }
    catch (e) { json.__decryptError = e.message; }
  }
  return { status: res.status, sent: r, ...json };
}

async function guestLogin(deviceId) {
  const r = await post('/ht/users/v2/guestLogin', {}, '', deviceId);
  return (r.data && (r.data.token || r.data.guestToken)) || '';
}

// ========================== CLI ==========================
const argv = process.argv.slice(2);
const cmd = argv[0] && !argv[0].startsWith('--') ? argv[0] : 'help';
const opt = k => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : undefined; };
const jparse = s => { try { return s ? JSON.parse(s) : {}; } catch { return null; } };

/** Git Bash(MSYS) 会把以 / 开头的参数误转成 Windows 路径，这里还原 */
function normPath(p) {
  if (!p || p.startsWith('/')) return p;
  const i = p.lastIndexOf('/ht/');
  return i >= 0 ? p.slice(i) : p;
}

const USAGE = `
红桃视频接口加解密工具（单文件版）

  node ht-api.js                                    显示摘要与用法
  node ht-api.js demo                               端到端实测（真实请求接口）
  node ht-api.js keys   --t <t> [--deviceId <id>]   打印 key / iv
  node ht-api.js decrypt --t <t> --deviceId <id> --data "<响应data Base64>"
  node ht-api.js encrypt --t <t> --deviceId <id> --path <接口路径> --json '{"a":1}'
  node ht-api.js call   --path <接口路径> --json '{"a":1}' [--token <x-token>]

示例：
  node ht-api.js decrypt --t 1790674475116 --deviceId H5-1waycYtXuiZmfdYRfXGOl \\
       --data "53W6rrBO92xOya86+H/T/TOEzcbW+zlULfGj1AGPokBfmddGD+R+FcM/8VADC96u3US6OCdT7ZWnxdMsuncRjMmIQLv9r63zhtM0vXinoLQ="

核心参数：
  AES-128-CBC + ZeroPadding，Key/IV 为 UTF-8 原始字符串，密文 Base64
  key = t后6位 + "52S8" + "com.ht"
  iv  = "0.video" + "hprd" + deviceId前6位
  sign= MD5(参数值按名升序拼接 + "52S8VB&uiFR^hprd" + path).toUpperCase()
`;

async function main() {
  switch (cmd) {
    case 'help':
      console.log(USAGE);
      break;

    case 'keys': {
      const t = opt('t');
      if (!t) return console.log('缺少 --t');
      const deviceId = opt('deviceId') || '(未提供)';
      console.log('t        =', t);
      console.log('deviceId =', deviceId);
      console.log('key      =', deriveKey(t), '(' + Buffer.byteLength(deriveKey(t)) + 'B)');
      if (opt('deviceId')) console.log('iv       =', deriveIv(deviceId), '(' + Buffer.byteLength(deriveIv(deviceId)) + 'B)');
      break;
    }

    case 'decrypt': {
      const t = opt('t'), deviceId = opt('deviceId'), data = opt('data');
      if (!t || !deviceId || !data) return console.log('需要 --t / --deviceId / --data');
      const key = deriveKey(t), iv = deriveIv(deviceId);
      console.log('key =', key, '\niv  =', iv, '\n----');
      const raw = aesDecrypt(data, key, iv);
      try { console.log(JSON.stringify(JSON.parse(raw), null, 2)); } catch { console.log(raw); }
      break;
    }

    case 'encrypt': {
      const t = opt('t'), deviceId = opt('deviceId'), path = normPath(opt('path')) || '/ht/content/v2/getArts';
      const body = jparse(opt('json'));
      if (!t || !deviceId || !body) return console.log('需要 --t / --deviceId / --json');
      const key = deriveKey(t), iv = deriveIv(deviceId);
      const payload = Object.assign({}, body, { sign: makeSign(body, path) });
      console.log('key     =', key, '\niv      =', iv);
      console.log('payload =', JSON.stringify(payload));
      console.log('body    =', aesEncrypt(JSON.stringify(payload), key, iv));
      break;
    }

    case 'call': {
      const path = normPath(opt('path')), params = jparse(opt('json'));
      if (!path || params === null) return console.log('需要 --path 与合法 --json');
      const deviceId = opt('deviceId') || newDeviceId();
      let token = opt('token');
      if (!token) token = await guestLogin(deviceId);
      const r = await post(path, params, token, deviceId);
      console.log('deviceId =', deviceId);
      console.log('POST', path, JSON.stringify(params));
      console.log('key =', r.sent.key, ' iv =', r.sent.iv);
      console.log('HTTP', r.status, 'code =', r.code, r.msg);
      console.log(JSON.stringify(r.data, null, 2).slice(0, 3000));
      break;
    }

    case 'demo': {
      const deviceId = newDeviceId();
      console.log('设备号 deviceId =', deviceId);
      const token = await guestLogin(deviceId);
      console.log('游客 token =', token.slice(0, 40), '...');

      const a = await post('/ht/content/v2/getArts', { pageNo: 0, pageSize: 20 }, token, deviceId);
      console.log('\n[getArts] HTTP', a.status, 'code', a.code, a.msg,
        '| artList', (a.data && a.data.artList || []).length, '| totalPage', a.data && a.data.totalPage);
      (a.data && a.data.artList || []).slice(0, 3).forEach(x =>
        console.log('   -', x.artId, x.artName.slice(0, 40)));

      const b = await post('/ht/content/v2/queryTypeVideosH5', { typeId: '3', page: 1, pageSize: 5 }, token, deviceId);
      console.log('\n[queryTypeVideosH5] HTTP', b.status, 'code', b.code, b.msg,
        '| 条数', (b.data && b.data.typeVideoList || []).length);
      break;
    }

    default:
      console.log(USAGE);
  }
}

module.exports = {
  SIGN_KEY, BUNDLE_ID, STATIC_KEY, STATIC_IV,
  md5Hex, nanoid, newDeviceId, aesEncrypt, aesDecrypt,
  aesEncryptStatic, aesDecryptStatic,
  deriveKey, deriveIv, makeSign, isPlainText,
  buildRequest, buildHeaders, decryptResponse, decodeResponseData, post, guestLogin,
};

if (require.main === module) main();
