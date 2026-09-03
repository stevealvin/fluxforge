import axios from 'axios';
import iconv from 'iconv-lite';

export const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

/**
 * 智能嗅探网页编码并转换为标准的 UTF-8 字符串 (解决 GBK / GB2312 / GB18030 / BIG5 等中文乱码问题)
 */
export function detectAndDecodeHtml(buffer: ArrayBuffer | Buffer, contentTypeHeader?: string): string {
  const buf = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer);
  let encoding = 'utf-8';

  // 1. 尝试从响应头 Content-Type 中提取 charset
  if (contentTypeHeader) {
    const match = contentTypeHeader.match(/charset=([a-zA-Z0-9_-]+)/i);
    if (match && match[1]) {
      encoding = match[1].toLowerCase().trim();
    }
  }

  // 2. 从 HTML 前 2048 字节嗅探 <meta ... charset="...">
  const headSnippet = buf.subarray(0, 2048).toString('binary');
  const metaMatch =
    headSnippet.match(/<meta[^>]+charset=["']?([a-zA-Z0-9_-]+)/i) ||
    headSnippet.match(/<meta[^>]+http-equiv=["']?Content-Type["']?[^>]+content=["'][^"']*charset=([a-zA-Z0-9_-]+)/i);

  if (metaMatch && metaMatch[1]) {
    const detected = metaMatch[1].toLowerCase().trim();
    if (['gbk', 'gb2312', 'gb18030', 'big5', 'shift_jis', 'euc-jp', 'euc-kr', 'windows-1252', 'iso-8859-1'].includes(detected)) {
      encoding = detected;
    }
  }

  // 兼容别名
  if (encoding === 'gb2312') encoding = 'gbk';
  if (encoding === 'utf8') encoding = 'utf-8';

  try {
    if (iconv.encodingExists(encoding)) {
      const decoded = iconv.decode(buf, encoding);
      // 如果声明的是 UTF-8 但解码后存在大量无效字符 (\uFFFD)，尝试 GBK 挽救
      if (encoding === 'utf-8' && decoded.includes('\uFFFD')) {
        const gbkTry = iconv.decode(buf, 'gbk');
        if (!gbkTry.includes('\uFFFD')) {
          return gbkTry;
        }
      }
      return decoded;
    }
  } catch {
    // 降级 fallback
  }

  return iconv.decode(buf, 'utf-8');
}

export const crawlerService = {
  /**
   * 抓取目标网址内容并自动解码为标准 UTF-8 文本
   */
  async fetchPage(url: string, headers?: Record<string, string>): Promise<{ url: string; status: number; data: string }> {
    if (!url || !url.startsWith('http')) {
      throw new Error('请提供有效的 HTTP/HTTPS 目标网址');
    }

    const res = await axios.get(url, {
      headers: {
        'User-Agent': DEFAULT_USER_AGENT,
        Accept: '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        ...(headers || {})
      },
      timeout: 15000,
      responseType: 'arraybuffer'
    });

    const contentType = (res.headers['content-type'] || res.headers['Content-Type'] || '') as string;
    const data = detectAndDecodeHtml(res.data, contentType);

    return {
      url,
      status: res.status,
      data
    };
  }
};
