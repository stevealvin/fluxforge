import { app } from '../src/index.js';

async function runTests() {
  console.log('--- Testing health check ---');
  let res = await app.request('/api');
  console.log('GET /api Status:', res.status);
  console.log('GET /api Body:', await res.text());

  console.log('\n--- Testing GET /api/rules ---');
  res = await app.request('/api/rules');
  console.log('GET /api/rules Status:', res.status);
  const rulesData = await res.json() as any;
  console.log('GET /api/rules Count:', rulesData.total);
  console.log('GET /api/rules first rule:', rulesData.data?.[0]?.name);

  console.log('\n--- Testing GET /api/rules/:id ---');
  if (rulesData.data?.length > 0) {
    const firstId = rulesData.data[0].id;
    res = await app.request(`/api/rules/${firstId}`);
    console.log(`GET /api/rules/${firstId} Status:`, res.status);
    console.log(`GET /api/rules/${firstId} Name:`, (await res.json() as any).name);
  }

  console.log('\n--- Testing POST /api/rules/run (Sandbox) ---');
  res = await app.request('/api/rules/run', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      code: `
        import axios from 'axios';
        export default async function() {
          return 'Sandbox run successful! Axios is available: ' + (typeof axios === 'function');
        }
      `
    })
  });
  console.log('POST /api/rules/run Status:', res.status);
  console.log('POST /api/rules/run Result:', await res.json());

  console.log('\n--- Testing POST /api/rules/run (内置 crypto-js) ---');
  res = await app.request('/api/rules/run', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      // 三种写法必须拿到同一个单例：ESM import / CommonJS require / 全局 CryptoJS
      code: `
        import CryptoJS from 'crypto-js';
        export default async function() {
          const viaImport = CryptoJS.MD5('hello').toString();
          const viaRequire = require('crypto-js').SHA1('hello').toString().slice(0, 8);
          const roundTrip = CryptoJS.AES.decrypt(
            CryptoJS.AES.encrypt('fluxforge', 'secret-key').toString(),
            'secret-key'
          ).toString(CryptoJS.enc.Utf8);
          return [viaImport, viaRequire, roundTrip].join(' | ');
        }
      `
    })
  });
  const cryptoPayload = (await res.json()) as any;
  const cryptoText = String(cryptoPayload?.result ?? '');
  console.log('POST /api/rules/run (crypto-js) Status:', res.status);
  console.log('POST /api/rules/run (crypto-js) Result:', cryptoText);

  // 固定期望值：MD5('hello') 可离线核对，SHA1 只取前 8 位，AES 往返必须还原原文
  const expectedMd5 = '5d41402abc4b2a76b9719d911017c592';
  if (!cryptoText.startsWith(expectedMd5) || !cryptoText.endsWith('fluxforge')) {
    throw new Error(
      `crypto-js 沙箱用例失败：期望以 ${expectedMd5} 开头、以 fluxforge 结尾，实际 ${cryptoText}`
    );
  }

  console.log('\n--- Testing POST /api/rules/run with context and arrow function ---');
  res = await app.request('/api/rules/run', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      context: {
        val: 'TEST_CONTEXT_VALUE'
      },
      code: `
        async (ctx) => {
          return 'Context received: ' + ctx.val;
        }
      `
    })
  });
  console.log('POST /api/rules/run (context) Status:', res.status);
  console.log('POST /api/rules/run (context) Result:', await res.json());

  console.log('\n--- Testing POST /api/rules/run with user-reported ESM import wrapping ---');
  res = await app.request('/api/rules/run', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      code: `
        import axios from 'axios'
        import cheerio from 'cheerio'

        (async () => {
          return 'Success: axios is ' + (typeof axios === 'function') + ' and cheerio is ' + (typeof cheerio === 'object');
        })
      `
    })
  });
  console.log('POST /api/rules/run (ESM import wrapping) Status:', res.status);
  console.log('POST /api/rules/run (ESM import wrapping) Result:', await res.json());
}

runTests().catch(console.error);
