export const libTypes = {
  // `require('cheerio')` 与 axios 一样要取**默认导出**：模块命名空间上并没有 `load`，
  // 写成 `typeof import('cheerio')` 会让 `const cheerio = require('cheerio')` 之后
  // `cheerio.` 只提示出一个 default。
  require: `declare function require(moduleName: 'axios'): typeof import('axios').default;
    declare function require(moduleName: 'cheerio'): typeof import('cheerio').default;
    declare function require(moduleName: 'crypto-js'): typeof import('crypto-js').default;`,
  axios: `declare module 'axios' {
    export interface AxiosRequestConfig {
      url?: string;
      method?: string;
      baseURL?: string;
      headers?: any;
      params?: any;
      data?: any;
      timeout?: number;
      withCredentials?: boolean;
      responseType?: string;
    }
    
    export interface AxiosResponse<T = any> {
      data: T;
      status: number;
      statusText: string;
      headers: any;
      config: AxiosRequestConfig;
      request?: any;
    }
    
    export interface AxiosError extends Error {
      config: AxiosRequestConfig;
      code?: string;
      request?: any;
      response?: AxiosResponse;
    }
    
    export interface AxiosInstance {
      request<T = any>(config: AxiosRequestConfig): Promise<AxiosResponse<T>>;
      get<T = any>(url: string, config?: AxiosRequestConfig): Promise<AxiosResponse<T>>;
      delete<T = any>(url: string, config?: AxiosRequestConfig): Promise<AxiosResponse<T>>;
      head<T = any>(url: string, config?: AxiosRequestConfig): Promise<AxiosResponse<T>>;
      post<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<AxiosResponse<T>>;
      put<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<AxiosResponse<T>>;
      patch<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<AxiosResponse<T>>;
    }
    
    export interface AxiosStatic extends AxiosInstance {
      create(config?: AxiosRequestConfig): AxiosInstance;
      Cancel: any;
      CancelToken: any;
      isCancel(value: any): boolean;
      all<T>(values: (T | Promise<T>)[]): Promise<T[]>;
      spread<T, R>(callback: (...args: T[]) => R): (array: T[]) => R;
    }
    
    const axios: AxiosStatic;
    export default axios;
  }`,
  cheerio: `declare module 'cheerio' {
    export interface CheerioSelection {
      length: number;
      text(): string;
      html(): string | null;
      attr(name: string): string | undefined;
      attr(name: string, value: string): CheerioSelection;
      data(name?: string): any;
      val(): string | string[] | undefined;
      hasClass(className: string): boolean;
      find(selector: string): CheerioSelection;
      children(selector?: string): CheerioSelection;
      parent(selector?: string): CheerioSelection;
      parents(selector?: string): CheerioSelection;
      closest(selector: string): CheerioSelection;
      next(selector?: string): CheerioSelection;
      prev(selector?: string): CheerioSelection;
      siblings(selector?: string): CheerioSelection;
      first(): CheerioSelection;
      last(): CheerioSelection;
      eq(index: number): CheerioSelection;
      slice(start?: number, end?: number): CheerioSelection;
      filter(selector: string | ((index: number, element: any) => boolean)): CheerioSelection;
      not(selector: string): CheerioSelection;
      has(selector: string): CheerioSelection;
      each(callback: (index: number, element: any) => any): CheerioSelection;
      map<T>(callback: (index: number, element: any) => T): { toArray(): T[]; get(): T[] };
      toArray(): any[];
      get(index?: number): any;
      [index: number]: any;
    }
    export interface CheerioRoot extends CheerioSelection {
      (selector: string | any, context?: any): CheerioSelection;
      html(): string;
      xml(): string;
      text(): string;
    }
    export interface CheerioAPI {
      (selector: string | any, context?: any): CheerioSelection;
      load(html: string | any, options?: any): CheerioRoot;
      [key: string]: any;
    }
    const cheerio: CheerioAPI;
    export default cheerio;
  }`,
  // crypto-js：沙箱内置单例，`import CryptoJS from 'crypto-js'` / `require('crypto-js')`
  // 与直接用全局 `CryptoJS` 三种写法等价。命名对齐库自身导出
  // （MD5 / SHA256 / HmacSHA256 / AES / enc / mode / pad / format）。
  cryptoJs: `declare module 'crypto-js' {
    export interface WordArray {
      words: number[];
      sigBytes: number;
      toString(encoder?: Encoder): string;
      concat(other: WordArray): WordArray;
      clamp(): void;
      clone(): WordArray;
    }

    export interface Encoder {
      stringify(wordArray: WordArray): string;
      parse(str: string): WordArray;
    }

    export interface CipherParams {
      ciphertext: WordArray;
      key?: WordArray;
      iv?: WordArray;
      salt?: WordArray;
      toString(formatter?: any): string;
    }

    export interface Hasher {
      (message: string | WordArray, cfg?: any): WordArray;
      create(cfg?: any): any;
    }

    export interface HmacHasher {
      (message: string | WordArray, key: string | WordArray): WordArray;
    }

    export interface Cipher {
      encrypt(message: string | WordArray, key: string | WordArray, cfg?: any): CipherParams;
      decrypt(ciphertext: string | CipherParams, key: string | WordArray, cfg?: any): WordArray;
    }

    export interface CryptoJSApi {
      MD5: Hasher;
      SHA1: Hasher;
      SHA224: Hasher;
      SHA256: Hasher;
      SHA384: Hasher;
      SHA512: Hasher;
      SHA3: Hasher;
      RIPEMD160: Hasher;
      HmacMD5: HmacHasher;
      HmacSHA1: HmacHasher;
      HmacSHA224: HmacHasher;
      HmacSHA256: HmacHasher;
      HmacSHA384: HmacHasher;
      HmacSHA512: HmacHasher;
      HmacSHA3: HmacHasher;
      HmacRIPEMD160: HmacHasher;
      AES: Cipher;
      DES: Cipher;
      TripleDES: Cipher;
      RC4: Cipher;
      RC4Drop: Cipher;
      Rabbit: Cipher;
      RabbitLegacy: Cipher;
      enc: {
        Utf8: Encoder;
        Latin1: Encoder;
        Hex: Encoder;
        Base64: Encoder;
        Utf16: Encoder;
        Utf16LE: Encoder;
      };
      mode: { CBC: any; CFB: any; CTR: any; CTRGladman: any; OFB: any; ECB: any };
      pad: {
        Pkcs7: any;
        AnsiX923: any;
        Iso10126: any;
        Iso97971: any;
        ZeroPadding: any;
        NoPadding: any;
      };
      format: { OpenSSL: any; Hex: any };
      lib: { WordArray: any; CipherParams: any };
      algo: any;
      kdf: { OpenSSL: any };
    }

    const CryptoJS: CryptoJSApi;
    export default CryptoJS;
  }`
}