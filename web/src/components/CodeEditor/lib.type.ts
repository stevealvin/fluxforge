export const libTypes = {
  require: `declare function require(moduleName: 'axios'): typeof import('axios').default;
    declare function require(moduleName: 'cheerio'): typeof import('cheerio');`,
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
  }`
}